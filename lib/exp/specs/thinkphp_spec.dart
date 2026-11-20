/// ThinkPHP 家族声明。
library;

import '../core/exploit_module.dart';
import '../core/exp_spec.dart';

const thinkphpSpec = ExpSpec(
  id: 'thinkphp',
  family: 'ThinkPHP',
  title: 'ThinkPHP RCE 系列',
  subtitle: '3 个变体：5.0.23 / 5.0.22·5.1.29 / 2.x',
  category: 'ThinkPHP',
  icon: ExpIcon.thinkphp,
  notes: [
    '原生写马：写到 public 下 php_behinder.php',
    '2.x 的 payload 需要 URL 编码',
  ],
  fields: [],
  variants: [
    ExpVariant(
      id: 'thinkphp-tp5023',
      label: '5.0.23 captcha filter · ThinkPHP 5.0.23',
      moduleId: 'thinkphp-tp5023',
      capabilities: {ExploitCapability.check,
        ExploitCapability.exec,
        ExploitCapability.getShell},
    ),
    ExpVariant(
      id: 'thinkphp-tp5022',
      label: '5.0.22 / 5.1.29 invokefunction · ThinkPHP 5.0.22/5.1.29',
      moduleId: 'thinkphp-tp5022',
      capabilities: {ExploitCapability.check,
        ExploitCapability.exec,
        ExploitCapability.getShell},
    ),
    ExpVariant(
      id: 'thinkphp-tp2',
      label: '2.x preg_replace /e · ThinkPHP 2.x',
      moduleId: 'thinkphp-tp2',
      capabilities: {ExploitCapability.check,
        ExploitCapability.exec,
        ExploitCapability.getShell},
    ),
  ],
);
