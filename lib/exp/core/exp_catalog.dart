/// 声明层的目录：把 [ExpSpec] 与执行层的 [ExploitModule] 绑起来。
///
/// 迁移完成后 12 个家族全部登记在这里；顺序即入口顺序。
library;

import 'exploit_module.dart';
import 'exp_spec.dart';
import 'module_registry.dart';

import '../specs/drupal_spec.dart';
import '../specs/httpd_spec.dart';
import '../specs/nacos_spec.dart';
import '../specs/php_spec.dart';
import '../specs/shiro_spec.dart';
import '../specs/spring_spec.dart';
import '../specs/struts2_spec.dart';
import '../specs/thinkphp_spec.dart';
import '../specs/tomcat_spec.dart';
import '../specs/weblogic_spec.dart';
import '../specs/xxljob_spec.dart';
import '../specs/zentao_spec.dart';

/// 12 个家族声明。
final List<ExpSpec> expSpecs = [
  struts2Spec,
  springSpec,
  thinkphpSpec,
  drupalSpec,
  phpSpec,
  tomcatSpec,
  weblogicSpec,
  httpdSpec,
  nacosSpec,
  xxljobSpec,
  shiroSpec,
  zentaoSpec,
];

/// 家族声明按 id 查找。
ExpSpec? specById(String id) {
  for (final spec in expSpecs) {
    if (spec.id == id) return spec;
  }
  return null;
}

/// 执行模块按 id 查找（`ExploitVariant.moduleId` → `ExploitModule`）。
ExploitModule? moduleById(String id) {
  for (final module in exploitModules) {
    if (module.id == id) return module;
  }
  return null;
}

/// 变体 → 模块。绑定缺失时返回 null（由 `tool/verify/spec_bind.dart` 兜住）。
ExploitModule? moduleOf(ExpSpec spec, ExpVariant variant) =>
    moduleById(variant.moduleId);

/// 该变体真实可用的能力（以执行模块为准，而不是声明里写了什么）。
Set<ExploitCapability> actualCapabilities(ExpVariant variant) =>
    moduleById(variant.moduleId)?.capabilities ?? const {};

/// 全部 variant 的扁平视图，供一键扫描页枚举。
List<(ExpSpec, ExpVariant)> get allVariants => [
  for (final spec in expSpecs)
    for (final variant in spec.variants) (spec, variant),
];
