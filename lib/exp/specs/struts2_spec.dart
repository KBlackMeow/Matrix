/// Struts2 家族声明：8 个 OGNL / 反序列化变体。
library;

import '../core/exploit_module.dart';
import '../core/exp_spec.dart';

const _shellCapabilities = {
  ExploitCapability.check,
  ExploitCapability.exec,
  ExploitCapability.getShell,
};

const struts2Spec = ExpSpec(
  id: 'struts2',
  family: 'Struts2',
  title: 'Struts2 · OGNL 注入系列',
  subtitle: '8 个变体：S2-005 / 007 / 032 / 045 / 052 / 053 / 057 / 059',
  category: 'Struts2',
  icon: ExpIcon.struts2,
  notes: [
    'S2-052 走 XStream 反序列化，无回显，只能盲打 + HTTP 验证',
    '落盘目录由 ShellDeployer 探测（webapp / ROOT / webapps …）',
  ],
  fields: [
    ExpFieldSpec(
      key: 'path',
      label: '起始路径',
      hint: '例如 struts2-showcase，留空用 /',
      defaultValue: '',
    ),
  ],
  variants: [
    ExpVariant(
      id: 'struts2-s2005',
      label: 'S2-005 · 参数名 OGNL',
      moduleId: 'struts2-s2005',
      capabilities: _shellCapabilities,
    ),
    ExpVariant(
      id: 'struts2-s2007',
      label: 'S2-007 · 类型转换注入',
      moduleId: 'struts2-s2007',
      capabilities: _shellCapabilities,
    ),
    ExpVariant(
      id: 'struts2-s2032',
      label: 'S2-032 · DMI OGNL',
      moduleId: 'struts2-s2032',
      capabilities: _shellCapabilities,
    ),
    ExpVariant(
      id: 'struts2-s2045',
      label: 'S2-045 · Content-Type OGNL',
      moduleId: 'struts2-s2045',
      capabilities: _shellCapabilities,
    ),
    ExpVariant(
      id: 'struts2-s2052',
      label: 'S2-052 · XStream 反序列化',
      moduleId: 'struts2-s2052',
      evidence: ExpEvidence.weak,
      capabilities: _shellCapabilities,
      hint: '盲打：无命令回显，只能靠 HTTP 验证 shell 是否写入',
    ),
    ExpVariant(
      id: 'struts2-s2053',
      label: 'S2-053 · Freemarker 二次求值',
      moduleId: 'struts2-s2053',
      capabilities: _shellCapabilities,
    ),
    ExpVariant(
      id: 'struts2-s2057',
      label: 'S2-057 · namespace OGNL',
      moduleId: 'struts2-s2057',
      capabilities: _shellCapabilities,
      hint: '仅当 struts.mapper.alwaysSelectFullNamespace=true 且存在 redirect 结果时可验证；'
          '本地 2.3.34-showcase 镜像打不出信号，属未验证变体',
    ),
    ExpVariant(
      id: 'struts2-s2059',
      label: 'S2-059 · id 参数二次求值',
      moduleId: 'struts2-s2059',
      capabilities: _shellCapabilities,
    ),
  ],
);
