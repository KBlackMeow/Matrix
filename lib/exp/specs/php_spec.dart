/// PHP 家族声明。
library;

import '../core/exploit_module.dart';
import '../core/exp_spec.dart';

const phpSpec = ExpSpec(
  id: 'php',
  family: 'PHP',
  title: 'PHP 后门 / CGI 参数注入',
  subtitle: '2 个变体：8.1.0-dev 后门 / CVE-2012-1823',
  category: 'PHP',
  icon: ExpIcon.php,
  notes: [
    '8.1.0-dev 后门走 User-Agentt 头，CI 环境常见',
    'CGI 变体依赖 php://input',
  ],
  fields: [
    ExpFieldSpec(
      key: 'path',
      label: '起始路径',
      hint: '留空使用 /',
      defaultValue: '',
    ),
    ExpFieldSpec(
      key: 'phpPath',
      label: 'PHP 入口路径',
      hint: '8.1.0-dev 后门通常为 /index.php',
      defaultValue: '/index.php',
    ),
  ],
  variants: [
    ExpVariant(
      id: 'php-backdoor',
      label: 'PHP 8.1.0-dev 后门 · PHP 8.1.0-dev',
      moduleId: 'php-backdoor',
      capabilities: {ExploitCapability.check,
        ExploitCapability.exec,
        ExploitCapability.getShell},
    ),
    ExpVariant(
      id: 'php-cgi-2012-1823',
      label: 'PHP-CGI 参数注入 · CVE-2012-1823',
      moduleId: 'php-cgi-2012-1823',
      capabilities: {ExploitCapability.check,
        ExploitCapability.exec,
        ExploitCapability.getShell},
    ),
  ],
);
