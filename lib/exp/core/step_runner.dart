/// 步骤执行器：管状态、产物、依赖与失败停留。
///
/// 语义（与设计决议一致）：
/// - 依赖 = 产物已存在 **或** 对应字段非空（用户手填的 key 也算满足）；
/// - 失败停在原地，可重试；后续步骤变 blocked 并说明缺什么；
/// - 不允许并行执行同一步骤（running 期间忽略重复触发）。
library;

import 'exp_spec.dart';
import 'exp_step.dart';
import 'exploit_module.dart';
import 'log_line.dart';

class StepRunner {
  StepRunner({
    required this.steps,
    required ExploitTarget Function() targetBuilder,
    required String? Function(String key) readField,
    required void Function(String key, String value) writeField,
    required void Function(LogLevel level, String text) log,
    this.onChanged,
  }) : _targetBuilder = targetBuilder,
       _readField = readField,
       _writeField = writeField,
       _log = log;

  /// 状态变化回调（不依赖 Flutter，UI 层用它 setState）。
  final void Function()? onChanged;

  void _notify() => onChanged?.call();

  final List<ExpStep> steps;
  final ExploitTarget Function() _targetBuilder;
  final String? Function(String key) _readField;
  final void Function(String key, String value) _writeField;
  final void Function(LogLevel level, String text) _log;

  final Map<String, StepStatus> _status = {};
  final Map<String, String> _error = {};
  final Map<String, String> _detail = {};

  /// 步骤产物（key / token / shellUrl…）。
  final Map<String, String> artifacts = {};

  /// 最近一次成功步骤产出的 WebShell 会话（UI 用它提示并跳转）。
  ShellSession? lastShell;

  /// 当前正在跑的步骤下标；null 表示空闲。
  int? _runningIndex;

  int? get runningIndex => _runningIndex;
  bool get running => _runningIndex != null;

  StepStatus statusOf(ExpStep step) => _status[step.id] ?? StepStatus.idle;
  String? errorOf(ExpStep step) => _error[step.id];
  String? detailOf(ExpStep step) => _detail[step.id];

  /// 该步骤还缺哪些产物。
  List<String> missingFor(ExpStep step) => [
    for (final key in step.requires)
      if (!_satisfied(key)) key,
  ];

  bool _satisfied(String key) {
    if (artifacts.containsKey(key) && artifacts[key]!.isNotEmpty) return true;
    final fromField = _readField(key);
    return fromField != null && fromField.trim().isNotEmpty;
  }

  /// 依赖未满足时禁止执行；返回 false 并置 blocked。
  bool canRun(ExpStep step) {
    if (running) return false;
    final missing = missingFor(step);
    if (missing.isNotEmpty) {
      _status[step.id] = StepStatus.blocked;
      _error[step.id] = '缺少：${missing.join('、')}';
      _notify();
      return false;
    }
    return true;
  }

  Future<void> run(ExpStep step) async {
    if (running) return;
    if (!canRun(step)) return;
    _runningIndex = steps.indexOf(step);
    _status[step.id] = StepStatus.running;
    _error.remove(step.id);
    _detail.remove(step.id);
    _notify();

    final ctx = StepContext(
      target: _targetBuilder(),
      artifacts: Map.unmodifiable(artifacts),
      // 步骤级参数优先：合并进 target.extra 由调用方负责，这里只读。
      log: (line) => _log(LogLine.parse(line).level, LogLine.parse(line).text),
      field: (key) {
        final stepField = step.fields.where((f) => f.key == key);
        if (stepField.isNotEmpty) {
          final v = _readField('${step.id}.$key');
          if (v != null && v.isNotEmpty) return v;
        }
        return _readField(key);
      },
      setField: _writeField,
    );

    try {
      final result = await step.run(ctx);
      if (result.ok) {
        _status[step.id] = StepStatus.ok;
        _detail[step.id] = result.detail;
        artifacts.addAll(result.artifacts);
        if (result.shell != null) lastShell = result.shell;
        final writeBack = step.writesField;
        if (writeBack != null && result.artifacts.containsKey(writeBack)) {
          _writeField(writeBack, result.artifacts[writeBack]!);
        }
        _log(LogLevel.ok, '${step.title}：${result.detail}');
      } else {
        _status[step.id] = StepStatus.failed;
        _error[step.id] = result.detail;
        _log(LogLevel.error, '${step.title} 失败：${result.detail}');
      }
    } catch (e) {
      _status[step.id] = StepStatus.failed;
      _error[step.id] = '$e';
      _log(LogLevel.error, '${step.title} 异常：$e');
    } finally {
      _runningIndex = null;
      // 依赖本步产物的下游步骤，状态回落成 blocked（如果之前是 ok/failed）
      _recomputeBlocked();
      _notify();
    }
  }

  void _recomputeBlocked() {
    for (final step in steps) {
      final status = statusOf(step);
      if (status != StepStatus.ok && status != StepStatus.failed) {
        final missing = missingFor(step);
        _status[step.id] = missing.isEmpty ? StepStatus.idle : StepStatus.blocked;
        if (missing.isEmpty) {
          _error.remove(step.id);
        } else {
          _error[step.id] = '缺少：${missing.join('、')}';
        }
      }
    }
  }

  /// 供扫描器使用：找到该家族的探测步骤。
  ExpStep? get probeStep {
    for (final s in steps) {
      if (s.isProbe) return s;
    }
    return steps.isEmpty ? null : steps.first;
  }
}
