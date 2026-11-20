/// 一键扫描的执行引擎。
///
/// 设计约束（来自 docs/exp-unified-architecture.md §5）：
/// - 流式：每扫完一个 variant 立刻产出一个事件，不等全部完成；
/// - 预算：请求数上限 + 墙钟上限，先到先停，并明说"还有 N 个没扫"；
/// - 限速：默认 3 次/秒，避免触发 WAF 或压垮脆弱服务；
/// - 熔断：连续 3 次探测失败（网络/超时）即中止，区分"打不动"与"没有洞"。
///
/// 请求数是**估算**：`ExploitModule.check` 不透出真实请求数，
/// 这里按家族给的经验值计账，宁可高估（高估只会更早停下来）。
library;

import 'dart:async';

import 'exp_catalog.dart';
import 'exp_spec.dart';
import 'exploit_module.dart';
import 'log_line.dart';

/// 扫描置信度。
enum ScanConfidence {
  /// 回显验证通过：命中且有证据。
  confirmed('确认命中'),

  /// 载荷已发，但只能证明"被接受"（盲打、后台任务、端点特征）。
  noEcho('弱证据·无回显'),

  /// 探测失败：网络/超时/被拦，不代表没有漏洞。
  failed('探测失败'),

  /// 探测完成且未命中。
  miss('未命中');

  const ScanConfidence(this.label);

  final String label;
}

/// 一条扫描结果。
class ScanHit {
  const ScanHit({
    required this.spec,
    required this.variant,
    required this.outcome,
    required this.confidence,
    required this.elapsed,
    required this.requests,
  });

  final ExpSpec spec;
  final ExpVariant variant;
  final ExploitOutcome outcome;
  final ScanConfidence confidence;
  final Duration elapsed;
  final int requests;

  bool get isHit =>
      confidence == ScanConfidence.confirmed ||
      confidence == ScanConfidence.noEcho;
}

/// 扫描事件流。
sealed class ScanEvent {
  const ScanEvent();
}

class ScanStarted extends ScanEvent {
  const ScanStarted(this.index, this.total);
  final int index;
  final int total;
}

class ScanHitEvent extends ScanEvent {
  const ScanHitEvent(this.hit);
  final ScanHit hit;
}

class ScanFinished extends ScanEvent {
  const ScanFinished({
    required this.hits,
    required this.skipped,
    required this.requests,
    required this.elapsed,
    required this.reason,
  });

  final List<ScanHit> hits;

  /// 因预算/熔断而未扫的 variant 数。
  final int skipped;

  final int requests;
  final Duration elapsed;

  /// 结束原因：`done` / `budget` / `aborted`。
  final String reason;
}

/// 置信度映射的唯一实现（矩阵脚本也用它，避免两套口径）。
ScanConfidence confidenceOf(ExpVariant variant, ExploitOutcome outcome) {
  if (outcome.failed) return ScanConfidence.failed;
  if (!outcome.vulnerable) return ScanConfidence.miss;
  if (variant.evidence == ExpEvidence.weak) return ScanConfidence.noEcho;
  return ScanConfidence.confirmed;
}

class ScanRunner {
  ScanRunner({
    this.maxRequests = 90,
    this.maxDuration = const Duration(seconds: 90),
    this.perSecond = 3,
    this.maxConsecutiveFailures = 3,
  });

  final int maxRequests;
  final Duration maxDuration;
  final double perSecond;
  final int maxConsecutiveFailures;

  bool _cancelled = false;

  void cancel() => _cancelled = true;

  /// 每个变体的实测请求数**上限**（来源：`docs/exp-unified-architecture.md` §9 的取证表）。
  ///
  /// 早期版本按家族估算（Struts2 一律记 4），实测发现 S2-007 一个 check 会遍历
  /// 4 条路径 × 2 种表单 = 8 发，导致预算在半程就耗尽（27 个变体只跑了 26 个）。
  /// 按变体记账后误差落在个位数。
  static const Map<String, int> _costByVariant = {
    'struts2-s2005': 8,
    'struts2-s2007': 8,
    'struts2-s2032': 1,
    'struts2-s2045': 1,
    'struts2-s2052': 1,
    'struts2-s2053': 1,
    'struts2-s2057': 1,
    'struts2-s2059': 1,
    'spring-22963': 2,
    'spring-22965': 18,
    'spring-1273': 1,
    'spring-8046': 2,
    'spring-4977': 2,
    'php-backdoor': 1,
    'php-cgi-2012-1823': 1,
    'tomcat-2017-12615': 4,
    'weblogic-10271': 5,
    'weblogic-14882': 2,
    'httpd-2021-41773': 2,
    'drupal-2018-7600': 1,
    'nacos-2021-29441': 1,
    'xxl-job-unacc': 1,
    'thinkphp-tp5023': 3,
    'thinkphp-tp5022': 6,
    'thinkphp-tp2': 2,
    'shiro-2016-4437': 2,
    'zentao-2024-24216': 6,
  };

  int _costOf(ExpSpec spec) => _costByVariant[spec.id] ?? 3;

  Stream<ScanEvent> run({
    required String url,
    required int timeoutSeconds,
    List<(ExpSpec, ExpVariant)>? targets,
  }) async* {
    // 便宜的先跑：预算真的不够时，被跳过的应是"最贵且最不确定"的那几个。
    final all = [...(targets ?? allVariants)]
      ..sort((a, b) => _costOf(a.$1).compareTo(_costOf(b.$1)));
    final hits = <ScanHit>[];
    final stopwatch = Stopwatch()..start();
    final interval = Duration(
      microseconds: (1000000 / (perSecond <= 0 ? 3 : perSecond)).round(),
    );

    var spent = 0;
    var consecutiveFailures = 0;
    var index = 0;
    var reason = 'done';
    var cancelledHere = false;

    try {
      for (final (spec, variant) in all) {
        if (_cancelled) {
          reason = 'aborted';
          cancelledHere = true;
          break;
        }
        if (stopwatch.elapsed >= maxDuration) {
          reason = 'budget';
          break;
        }
        final cost = _costOf(spec);
        if (spent + cost > maxRequests) {
          reason = 'budget';
          break;
        }

        yield ScanStarted(index, all.length);
        index++;
        spent += cost;

        final module = moduleById(variant.moduleId);
        final started = DateTime.now();
        ScanHit hit;
        if (module == null) {
          hit = ScanHit(
            spec: spec,
            variant: variant,
            outcome: ExploitOutcome.probeFailed(variant.label, '模块未注册'),
            confidence: ScanConfidence.failed,
            elapsed: Duration.zero,
            requests: cost,
          );
          consecutiveFailures++;
        } else {
          ExploitOutcome outcome;
          try {
            outcome = await module.check(
              ExploitTarget(
                url: url,
                timeout: Duration(seconds: timeoutSeconds),
              ),
            );
          } catch (e) {
            outcome = ExploitOutcome.probeFailed(variant.label, '$e');
          }
          final elapsed = DateTime.now().difference(started);
          hit = ScanHit(
            spec: spec,
            variant: variant,
            outcome: outcome,
            confidence: _confidenceOf(variant, outcome),
            elapsed: elapsed,
            requests: cost,
          );
          if (outcome.failed) {
            consecutiveFailures++;
          } else {
            consecutiveFailures = 0;
          }
        }

        if (hit.isHit) hits.add(hit);
        yield ScanHitEvent(hit);

        if (consecutiveFailures >= maxConsecutiveFailures) {
          reason = 'aborted';
          break;
        }
        // 限速：保证两次探测之间至少间隔 interval。
        await Future<void>.delayed(interval);
      }
    } finally {
      stopwatch.stop();
      final skipped = (all.length - index).clamp(0, all.length);
      yield ScanFinished(
        hits: hits,
        skipped: cancelledHere ? skipped : skipped,
        requests: spent,
        elapsed: stopwatch.elapsed,
        reason: reason,
      );
    }
  }

  ScanConfidence _confidenceOf(ExpVariant variant, ExploitOutcome outcome) =>
      confidenceOf(variant, outcome);
}

/// 扫描事件 → 日志行（唯一的格式化点）。
extension ScanEventLog on ScanEvent {
  LogLine? toLogLine() => switch (this) {
    ScanStarted(:final index, :final total) => LogLine(
      LogLevel.action,
      '[${index + 1}/$total] scanning…',
    ),
    ScanHitEvent(:final hit) => LogLine(
      switch (hit.confidence) {
        ScanConfidence.confirmed => LogLevel.ok,
        ScanConfidence.noEcho => LogLevel.note,
        ScanConfidence.failed => LogLevel.error,
        ScanConfidence.miss => LogLevel.miss,
      },
      '${hit.variant.label} — ${hit.confidence.label}'
          '${hit.outcome.detail.isEmpty ? '' : '（${hit.outcome.detail}）'}',
    ),
    ScanFinished(:final hits, :final skipped, :final requests, :final reason) =>
      LogLine(
        hits.isEmpty ? LogLevel.miss : LogLevel.ok,
        '扫描结束[$reason]：命中 ${hits.length} 条，消耗约 $requests 次请求'
            '${skipped > 0 ? '，$skipped 个变体未扫' : ''}',
      ),
  };
}
