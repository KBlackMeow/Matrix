/// Drupal 家族声明。
library;

import '../core/exploit_module.dart';
import '../core/exp_spec.dart';

const drupalSpec = ExpSpec(
  id: 'drupal',
  family: 'Drupal',
  title: 'Drupalgeddon2',
  subtitle: 'CVE-2018-7600 · 表单 API RCE',
  category: 'Drupal',
  icon: ExpIcon.drupal,
  notes: [
    '#post_render 属性注入，回显带唯一标记',
    '落盘 PHP 小马需要可写 web 根',
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
      id: 'drupal-2018-7600',
      label: 'Drupalgeddon2 RCE · CVE-2018-7600',
      moduleId: 'drupal-2018-7600',
      capabilities: {ExploitCapability.check,
        ExploitCapability.exec,
        ExploitCapability.getShell},
    ),
  ],
);
