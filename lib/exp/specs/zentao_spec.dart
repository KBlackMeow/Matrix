/// Zentao 家族声明。
library;

import '../core/exploit_module.dart';
import '../core/exp_spec.dart';

const zentaoSpec = ExpSpec(
  id: 'zentao',
  family: 'Zentao',
  title: 'Zentao 登录绕过 + 写马',
  subtitle: 'CVE-2024-24216 · Repo 配置写 Behinder',
  category: 'Zentao',
  icon: ExpIcon.zentao,
  notes: [
    '先绕登录拿 zentaosid，再改 Repo 配置写入',
    '写入位置由禅道自身的 repo 同步路径决定',
  ],
  fields: [],
  variants: [
    ExpVariant(
      id: 'zentao-2024-24216',
      label: '登录绕过 + Repo 写马 · CVE-2024-24216',
      moduleId: 'zentao-2024-24216',
      capabilities: {ExploitCapability.check,
        ExploitCapability.getShell},
    ),
  ],
);
