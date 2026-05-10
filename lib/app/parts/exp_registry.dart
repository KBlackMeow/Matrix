import 'package:flutter/material.dart';

import '../../pages/thinkphp_exp_page.dart';
import '../../pages/vulhub/drupal_exp_page.dart';
import '../../pages/vulhub/httpd_exp_page.dart';
import '../../pages/vulhub/nacos_exp_page.dart';
import '../../pages/vulhub/php_exp_page.dart';
import '../../pages/vulhub/spring_exp_page.dart';
import '../../pages/vulhub/struts2_exp_page.dart';
import '../../pages/vulhub/tomcat_exp_page.dart';
import '../../pages/vulhub/weblogic_exp_page.dart';
import '../../pages/vulhub/xxljob_exp_page.dart';
import '../../pages/zentao_exp_page.dart';
import '../localization.dart';
import 'shiro_exp.dart' as shiro;

class ExpEntry {
  final IconData icon;
  final String title;
  final String subtitle;
  final String versionRequirement;
  final String tag;
  final bool enabled;
  final Widget Function(String defaultTargetUrl) pageBuilder;

  ExpEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.versionRequirement,
    required this.tag,
    this.enabled = true,
    required this.pageBuilder,
  });
}

/// 入口卡片列表。延迟为 getter，保证语言切换后立即重建文案。
List<ExpEntry> get expEntries => [
  ExpEntry(
    icon: Icons.cookie,
    title: 'Apache Shiro CVE-2016-4437',
    subtitle: S.expSubtitleShiro,
    versionRequirement: S.expVersionShiro,
    tag: 'Java · ${S.expTagGeneric}',
    pageBuilder: (url) => shiro.ShiroExpPage(initialTargetUrl: url),
  ),
  ExpEntry(
    icon: Icons.php,
    title: 'ThinkPHP CVE-2018-20062/CVE-2019-9082/CNVD-2022-86535',
    subtitle: S.expSubtitleThinkphp,
    versionRequirement: S.expVersionThinkphp,
    tag: 'PHP · ${S.expTagGeneric}',
    pageBuilder: (url) => ThinkphpExpPage(initialTargetUrl: url),
  ),
  ExpEntry(
    icon: Icons.storage,
    title: 'Zentao CVE-2024-24216',
    subtitle: S.expSubtitleZentao,
    versionRequirement: S.expVersionZentao,
    tag: 'PHP · ${S.expTagZentao}',
    pageBuilder: (url) => ZentaoExpPage(initialTargetUrl: url),
  ),
  ExpEntry(
    icon: Icons.bolt,
    title: 'Apache Struts2 S2-032/045/053/057/059',
    subtitle: S.expSubtitleStruts2,
    versionRequirement: S.expVersionStruts2,
    tag: 'Java · Struts2',
    pageBuilder: (url) => Struts2ExpPage(initialTargetUrl: url),
  ),
  ExpEntry(
    icon: Icons.local_florist,
    title: 'Spring Framework CVE-2022-22963/22965/2018-1273/2017-8046',
    subtitle: S.expSubtitleSpring,
    versionRequirement: S.expVersionSpring,
    tag: 'Java · Spring',
    pageBuilder: (url) => SpringExpPage(initialTargetUrl: url),
  ),
  ExpEntry(
    icon: Icons.http,
    title: 'Apache HTTP Server CVE-2021-41773',
    subtitle: S.expSubtitleHttpd,
    versionRequirement: S.expVersionHttpd,
    tag: 'C · Apache',
    pageBuilder: (url) => HttpdExpPage(initialTargetUrl: url),
  ),
  ExpEntry(
    icon: Icons.water_drop,
    title: 'Drupal CVE-2018-7600 (Drupalgeddon2)',
    subtitle: S.expSubtitleDrupal,
    versionRequirement: S.expVersionDrupal,
    tag: 'PHP · Drupal',
    pageBuilder: (url) => DrupalExpPage(initialTargetUrl: url),
  ),
  ExpEntry(
    icon: Icons.php,
    title: S.expTitlePhp,
    subtitle: S.expSubtitlePhp,
    versionRequirement: S.expVersionPhp,
    tag: 'PHP · ${S.expTagGeneric}',
    pageBuilder: (url) => PhpExpPage(initialTargetUrl: url),
  ),
  ExpEntry(
    icon: Icons.cloud_upload,
    title: 'Apache Tomcat CVE-2017-12615',
    subtitle: S.expSubtitleTomcat,
    versionRequirement: S.expVersionTomcat,
    tag: 'Java · Tomcat',
    pageBuilder: (url) => TomcatExpPage(initialTargetUrl: url),
  ),
  ExpEntry(
    icon: Icons.dns,
    title: 'Oracle WebLogic CVE-2017-10271 / CVE-2020-14882',
    subtitle: S.expSubtitleWeblogic,
    versionRequirement: S.expVersionWeblogic,
    tag: 'Java · WebLogic',
    pageBuilder: (url) => WebLogicExpPage(initialTargetUrl: url),
  ),
  ExpEntry(
    icon: Icons.schedule,
    title: S.expTitleXxljob,
    subtitle: S.expSubtitleXxljob,
    versionRequirement: S.expVersionXxljob,
    tag: 'Java · XXL-JOB',
    pageBuilder: (url) => XxlJobExpPage(initialTargetUrl: url),
  ),
  ExpEntry(
    icon: Icons.cloud,
    title: 'Nacos CVE-2021-29441',
    subtitle: S.expSubtitleNacos,
    versionRequirement: S.expVersionNacos,
    tag: 'Java · Nacos',
    pageBuilder: (url) => NacosExpPage(initialTargetUrl: url),
  ),
];

List<ExpEntry> visibleExpEntries({bool includeDisabled = false}) {
  return expEntries
      .where((e) => includeDisabled || e.enabled)
      .toList(growable: false);
}
