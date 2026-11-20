/// Nacos 家族声明。
library;

import '../core/exploit_module.dart';
import '../core/exp_spec.dart';

const nacosSpec = ExpSpec(
  id: 'nacos',
  family: 'Nacos',
  title: 'Nacos 认证绕过',
  subtitle: 'CVE-2021-29441 · 默认 UA 直读用户列表',
  category: 'Nacos',
  icon: ExpIcon.nacos,
  notes: [
    '只读：拉取用户列表，常用于给 Derby RCE 做前置',
    '执行器无 Web 目录，不提供 shell',
  ],
  fields: [],
  variants: [
    ExpVariant(
      id: 'nacos-2021-29441',
      label: '认证绕过读用户 · CVE-2021-29441',
      moduleId: 'nacos-2021-29441',
      capabilities: {ExploitCapability.check},
    ),
  ],
);
