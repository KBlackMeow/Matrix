/// Apache httpd 家族声明。
library;

import '../core/exploit_module.dart';
import '../core/exp_spec.dart';

const httpdSpec = ExpSpec(
  id: 'httpd',
  family: 'Apache httpd',
  title: 'Apache httpd 路径穿越',
  subtitle: 'CVE-2021-41773 / 42013',
  category: 'Apache',
  icon: ExpIcon.httpd,
  notes: [
    '读取 /etc/passwd 验证穿越',
    'CGI 场景可 RCE，但无 Web 目录写入口（无 WebShell）',
  ],
  fields: [],
  variants: [
    ExpVariant(
      id: 'httpd-2021-41773',
      label: '路径穿越 → CGI RCE · CVE-2021-41773',
      moduleId: 'httpd-2021-41773',
      capabilities: {ExploitCapability.check,
        ExploitCapability.exec},
    ),
  ],
);
