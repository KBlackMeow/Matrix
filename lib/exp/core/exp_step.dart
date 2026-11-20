/// 步骤（流程）模型。
///
/// 设计约束（2026-11-20 决议）：
/// - 步骤是 UI 与执行的唯一编排单位；能力接口（check/exec/getShell）保留为底层原语，
///   步骤的 `run` **只允许组合既有服务能力**，不写新的攻击逻辑；
/// - 步骤间靠**产物**传值（key / token / shellUrl…），依赖缺失时禁止执行并说明原因；
/// - 家族级参数（url / timeout）永远以家族为准，步骤只能覆盖其余字段。
library;

import 'exp_spec.dart';
import 'exploit_module.dart';

/// 单个步骤的执行状态。
enum StepStatus {
  /// 从未执行。
  idle,

  /// 正在执行。
  running,

  /// 成功（可能带产物）。
  ok,

  /// 执行了但失败（可原地重试）。
  failed,

  /// 依赖未满足，禁止执行。
  blocked,
}

/// 一次步骤执行的结果。
class StepResult {
  const StepResult({
    required this.ok,
    this.detail = '',
    this.artifacts = const {},
    this.shell,
  });

  const StepResult.ok(
    [this.detail = '',
    this.artifacts = const {},
    this.shell]
  ) : ok = true;

  const StepResult.failed([this.detail = ''])
    : ok = false,
      artifacts = const {},
      shell = null;

  final bool ok;
  final String detail;

  /// 该步骤产出的 WebShell 会话（有值 = UI 需要提示并可跳转工作区）。
  final ShellSession? shell;

  /// 本次执行产出的东西（key / token / shellUrl…），会被并入 [StepRunner.artifacts]。
  final Map<String, String> artifacts;
}

/// 步骤执行时拿到的上下文。
class StepContext {
  StepContext({
    required this.target,
    required this.artifacts,
    required this.log,
    required this.field,
    required this.setField,
  });

  /// 已合并家族参数与步骤参数的 target。
  final ExploitTarget target;

  /// 前序步骤的产物（只读视图）。
  final Map<String, String> artifacts;

  /// 写日志（走会话的统一日志面板）。
  final void Function(String line) log;

  /// 读参数字段（步骤级优先，其次家族级）。
  final String? Function(String key) field;

  /// 写回字段（例如爆破出的 key 回填到「remember Key」输入框）。
  final void Function(String key, String value) setField;

  String? artifact(String key) => artifacts[key];
}

/// 一个可执行步骤。
class ExpStep {
  const ExpStep({
    required this.id,
    required this.title,
    this.description = '',
    this.requires = const [],
    this.produces = const [],
    this.fields = const [],
    this.isProbe = false,
    this.writesField,
    required this.run,
  });

  final String id;
  final String title;
  final String description;

  /// 需要的产物键；缺失（且对应字段为空）时该步骤为 blocked。
  final List<String> requires;

  /// 产出的产物键，成功后并入 runner。
  final List<String> produces;

  /// 步骤私有参数。
  final List<ExpFieldSpec> fields;

  /// 一键扫描只跑带这个标记的步骤（通常是"能得出证据强度"的那一步）。
  final bool isProbe;

  /// 成功后把某个产物写回同名字段（如爆破出的 key）。
  final String? writesField;

  final Future<StepResult> Function(StepContext ctx) run;
}
