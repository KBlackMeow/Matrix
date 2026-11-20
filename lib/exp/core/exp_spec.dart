/// 声明契约：一个家族（12 个之一）怎么描述自己。
///
/// 与 [ExploitModule] 的分工：
/// - `ExpSpec` / `ExpVariant`：**声明**——分类、文案、能力位、参数字段。UI 只读。
/// - `ExploitModule`：**执行**——check / exec / getShell。service 实现。
///
/// 二者通过 `moduleId` 一对一绑定，参数值经 [ExploitTarget.extra] 传递
/// （这个字段早就存在，但此前零读写，正是 12 个旧页面无法被统一壳驱动的根因）。
library;

import 'exploit_module.dart';
import 'exp_step.dart';

/// 字段类型。v1 只支持这四种；`textarea` / `secret` 需要时再加，
/// 避免一开始就长成一个小型表单引擎。
enum ExpFieldType { text, number, select, toggle, textarea }

/// 家族图标（语义名，不含 Flutter 类型）。
///
/// 放在 core 而不是直接存 [IconData]，是为了让 spec 层保持不依赖 UI 框架：
/// `tool/verify/spec_bind.dart` 之类可以脱离 Flutter 运行。
enum ExpIcon {
  universal,
  struts2,
  spring,
  drupal,
  thinkphp,
  zentao,
  httpd,
  nacos,
  weblogic,
  php,
  tomcat,
  xxljob,
  shiro,
}

class ExpFieldOption {
  const ExpFieldOption(this.value, this.label);

  final String value;
  final String label;
}

/// 一个参数声明。
class ExpFieldSpec {
  const ExpFieldSpec({
    required this.key,
    required this.label,
    this.hint = '',
    this.type = ExpFieldType.text,
    this.defaultValue = '',
    this.required = false,
    this.options = const [],
  });

  /// 写入 [ExploitTarget.extra] 的键名。
  final String key;
  final String label;
  final String hint;
  final ExpFieldType type;
  final String defaultValue;
  final bool required;
  final List<ExpFieldOption> options;

  /// 归一化外部输入（去空白、开关转 bool 字面量）。
  String normalize(String raw) => switch (type) {
    ExpFieldType.toggle => raw == 'true' ? 'true' : 'false',
    ExpFieldType.number => raw.trim(),
    // textarea 保留换行，其余一律去首尾空白
    ExpFieldType.textarea => raw,
    _ => raw.trim(),
  };

  bool get isToggle => type == ExpFieldType.toggle;
}

/// 命中证据的强度。
///
/// 显式建模，而不是靠 hint 里有没有"盲打"两个字去猜——那既脆弱又容易漏
/// （XXL-JOB 的 hint 写的是"无回显"，就绕过了旧判断，被当成"确认命中"）。
enum ExpEvidence {
  /// 命中即证明代码执行（回显 / 唯一计算值 / 可读回的文件）。
  strong,

  /// 只是"载荷被接受"：盲打、任务后台执行、仅有端点特征。
  weak,
}

/// 家族内的一个具体 CVE / 攻击变体。
///
/// 能力位是 **per-variant** 而不是 per-family：同一个 Struts2 页面里，
/// S2-052 只能盲打（无回显），S2-045 可以直接写文件。
class ExpVariant {
  const ExpVariant({
    required this.id,
    required this.label,
    required this.moduleId,
    required this.capabilities,
    this.fields = const [],
    this.hint = '',
    this.evidence = ExpEvidence.strong,
  });

  final String id;
  final String label;

  /// 对应 `exploitModules` 里的 `ExploitModule.id`。
  final String moduleId;

  final Set<ExploitCapability> capabilities;

  /// 该变体特有的附加字段（叠加在家族字段之上）。
  final List<ExpFieldSpec> fields;

  /// 一句话说明（盲打、需要认证等）。
  final String hint;

  /// 该变体的命中能证明到什么程度。
  final ExpEvidence evidence;

  bool supports(ExploitCapability c) => capabilities.contains(c);
}

/// 一个家族 = 一个页面。
class ExpSpec {
  const ExpSpec({
    required this.id,
    required this.family,
    required this.title,
    required this.subtitle,
    required this.category,
    required this.icon,
    required this.variants,
    this.fields = const [],
    this.defaultPath,
    this.notes = const [],
    this.steps = const [],
  });

  final String id;

  /// 卡片上的家族名（Struts2 / Spring / …）。
  final String family;

  final String title;
  final String subtitle;
  final String category;
  final ExpIcon icon;
  final List<ExpVariant> variants;

  /// 家族级字段（所有变体共享：url / timeout / path / 凭据…）。
  final List<ExpFieldSpec> fields;

  /// 固定端点，UI 可预填。
  final String? defaultPath;

  /// 卡片上的要点（版本范围、前提条件）。
  final List<String> notes;

  /// 该家族的流程步骤；为空表示沿用"检测/执行/取 shell"三按钮的旧形态。
  final List<ExpStep> steps;

  ExpVariant get defaultVariant => variants.first;

  ExpVariant? variantById(String id) {
    for (final v in variants) {
      if (v.id == id) return v;
    }
    return null;
  }

  /// 某个变体生效时的完整字段表：家族字段 + 变体附加字段（按 key 去重，后者优先）。
  List<ExpFieldSpec> fieldsFor(ExpVariant variant) {
    final merged = <String, ExpFieldSpec>{};
    for (final f in fields) {
      merged[f.key] = f;
    }
    for (final f in variant.fields) {
      merged[f.key] = f;
    }
    return merged.values.toList(growable: false);
  }

  /// 默认字段值（含必填校验用）。
  Map<String, String> defaultValuesFor(ExpVariant variant) => {
    for (final f in fieldsFor(variant))
      if (f.defaultValue.isNotEmpty) f.key: f.defaultValue,
  };
}
