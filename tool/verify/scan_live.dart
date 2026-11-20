// 一键扫描的实靶运行器：把 27 个变体对一个真实目标跑一遍，打印流式事件。
//
// 用途：在本地 vulhub 靶场上验证扫描引擎的**预算/限速/熔断/分级**是否按设计工作，
// 并暴露"哪个变体太慢/太吵/误报"。
//
// 用法：
//   dart tool/verify/scan_live.dart <url> [--budget=90] [--seconds=90] [--rate=3]
//   dart tool/verify/scan_live.dart <url> --only=struts2,spring

import 'dart:io';

import '../../lib/exp/core/exp_catalog.dart';
import '../../lib/exp/core/log_line.dart';
import '../../lib/exp/core/scan_runner.dart';

Future<void> main(List<String> args) async {
  final url = args.where((a) => !a.startsWith('--')).firstOrNull;
  if (url == null) {
    stderr.writeln('usage: scan_live <url> [--budget=90] [--seconds=90] [--rate=3] [--only=a,b]');
    exit(64);
  }
  int flag(String name, int fallback) {
    final arg = args.firstWhere((a) => a.startsWith('--$name='), orElse: () => '');
    if (arg.isEmpty) return fallback;
    return int.tryParse(arg.split('=').last) ?? fallback;
  }

  final only = args
      .firstWhere((a) => a.startsWith('--only='), orElse: () => '')
      .split('=')
      .last;
  final targets = only.isEmpty
      ? allVariants
      : allVariants.where((e) => only.split(',').contains(e.$1.id)).toList();

  final runner = ScanRunner(
    maxRequests: flag('budget', 90),
    maxDuration: Duration(seconds: flag('seconds', 90)),
    perSecond: flag('rate', 3).toDouble(),
  );

  final sw = Stopwatch()..start();
  var hits = 0;
  print('[*] $url · ${targets.length} 个变体 · budget=${flag('budget', 90)} '
      'seconds=${flag('seconds', 90)} rate=${flag('rate', 3)}/s');

  await for (final event in runner.run(url: url, timeoutSeconds: 8, targets: targets)) {
    if (event is ScanHitEvent) {
      final h = event.hit;
      final mark = h.isHit ? (h.confidence == ScanConfidence.confirmed ? '[+]' : '[!]') : '[-]';
      print('$mark ${h.variant.moduleId.padRight(20)} ${h.confidence.name.padRight(9)} '
          '${h.elapsed.inMilliseconds}ms  ${h.outcome.detail}');
      if (h.isHit) hits++;
    } else if (event is ScanFinished) {
      sw.stop();
      print('[*] 结束 reason=${event.reason} hits=$hits skipped=${event.skipped} '
          'requests≈${event.requests} 墙钟=${sw.elapsed.inSeconds}s');
      if (event.skipped > 0) {
        print('[!] 有 ${event.skipped} 个变体没扫 —— 预算/时间不够');
      }
    } else if (event is ScanStarted) {
      // 进度只在调试时看
    }
  }
}
