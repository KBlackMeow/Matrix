/// 语义图标 → Flutter [IconData] 的唯一映射。
///
/// spec 层只存 [ExpIcon]，这样声明文件不必依赖 Flutter；
/// 真正的图标在这里解析，改一处即全局生效。
library;

import 'package:flutter/material.dart';

import '../core/exp_spec.dart';

extension ExpIconData on ExpIcon {
  IconData get data => switch (this) {
    ExpIcon.universal => Icons.hub,
    ExpIcon.struts2 => Icons.bolt,
    ExpIcon.spring => Icons.eco,
    ExpIcon.drupal => Icons.water_drop_outlined,
    ExpIcon.thinkphp => Icons.php,
    ExpIcon.zentao => Icons.storage,
    ExpIcon.httpd => Icons.http,
    ExpIcon.nacos => Icons.tune,
    ExpIcon.weblogic => Icons.dns,
    ExpIcon.php => Icons.code,
    ExpIcon.tomcat => Icons.dns_outlined,
    ExpIcon.xxljob => Icons.schedule,
    ExpIcon.shiro => Icons.cookie,
  };
}
