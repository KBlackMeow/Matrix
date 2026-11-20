/// WebLogic 家族声明。
library;

import '../core/exploit_module.dart';
import '../core/exp_spec.dart';

const weblogicSpec = ExpSpec(
  id: 'weblogic',
  family: 'WebLogic',
  title: 'WebLogic 反序列化 / 控制台绕过',
  subtitle: '2 个变体：CVE-2020-10271 / CVE-2020-14882',
  category: 'WebLogic',
  icon: ExpIcon.weblogic,
  notes: [
    '10271 走 wls-wsat XMLDecoder，口令与 RCE 同一入口',
    '14882 为控制台路径穿越，仅验证可达性',
  ],
  fields: [
    ExpFieldSpec(
      key: 'path',
      label: '起始路径',
      hint: '留空使用 /',
      defaultValue: '',
    ),
  ],
  variants: [
    ExpVariant(
      id: 'weblogic-10271',
      label: 'XMLDecoder 反序列化 · CVE-2020-10271',
      moduleId: 'weblogic-10271',
      evidence: ExpEvidence.weak,
      capabilities: {ExploitCapability.check,
        ExploitCapability.exec,
        ExploitCapability.getShell},
    ),
    ExpVariant(
      id: 'weblogic-14882',
      label: '控制台绕过 · CVE-2020-14882',
      moduleId: 'weblogic-14882',
      evidence: ExpEvidence.weak,
      capabilities: {ExploitCapability.check,
        ExploitCapability.exec,
        ExploitCapability.getShell},
    ),
  ],
);
