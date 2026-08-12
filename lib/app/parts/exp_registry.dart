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
    subtitle: 'rememberMe key bruteforce / Payload injection',
    versionRequirement: 'Shiro: <=1.2.4 | Condition: default rememberMe key',
    tag: 'Java · ${'Generic'}',
    pageBuilder: (url) => shiro.ShiroExpPage(initialTargetUrl: url),
  ),
  ExpEntry(
    icon: Icons.php,
    title: 'ThinkPHP CVE-2018-20062/CVE-2019-9082/CNVD-2022-86535',
    subtitle: '3.x/5.x/6.x vuln detection, RCE, GetShell',
    versionRequirement: 'ThinkPHP: 2.x / <=5.0.23 / 5.0.22/5.1.29 | Condition: route/gadget chain reachable',
    tag: 'PHP · ${'Generic'}',
    pageBuilder: (url) => ThinkphpExpPage(initialTargetUrl: url),
  ),
  ExpEntry(
    icon: Icons.storage,
    title: 'Zentao CVE-2024-24216',
    subtitle: 'Login bypass · Write Behinder WebShell via Repo config',
    versionRequirement: 'Zentao: see official advisory range | Condition: exploit path reachable',
    tag: 'PHP · ${'Zentao'}',
    pageBuilder: (url) => ZentaoExpPage(initialTargetUrl: url),
  ),
  ExpEntry(
    icon: Icons.bolt,
    title: 'Apache Struts2 S2-032/045/053/057/059',
    subtitle: 'OGNL expression injection RCE series',
    versionRequirement: 'Struts2: S2-032=2.3.20-2.3.28(except 2.3.20.3/2.3.24.3); S2-045/053/057/059=2.0.0-2.5.20 | Condition: matching OGNL trigger surface present',
    tag: 'Java · Struts2',
    pageBuilder: (url) => Struts2ExpPage(initialTargetUrl: url),
  ),
  ExpEntry(
    icon: Icons.local_florist,
    title: 'Spring Framework CVE-2022-22963/22965/2018-1273/2017-8046',
    subtitle: 'Spring4Shell / Cloud Function / Data SpEL injection series',
    versionRequirement: 'Spring: 22965=5.3.17; 22963=SCF 3.2.2; 1273=Data Commons<=2.0.5; 8046=Data REST 2.6.6 | Condition: deployment matches each CVE',
    tag: 'Java · Spring',
    pageBuilder: (url) => SpringExpPage(initialTargetUrl: url),
  ),
  ExpEntry(
    icon: Icons.http,
    title: 'Apache HTTP Server CVE-2021-41773',
    subtitle: 'Path normalization flaw — path traversal + CGI RCE',
    versionRequirement: 'HTTPd: =2.4.49 | Condition: directory config allows traversal',
    tag: 'C · Apache',
    pageBuilder: (url) => HttpdExpPage(initialTargetUrl: url),
  ),
  ExpEntry(
    icon: Icons.water_drop,
    title: 'Drupal CVE-2018-7600 (Drupalgeddon2)',
    subtitle: 'Form API #post_render callback PHP execution',
    versionRequirement: 'Drupal: <7.58; 8.x<8.3.9/<8.4.6/<8.5.1 | Condition: Form API path reachable',
    tag: 'PHP · Drupal',
    pageBuilder: (url) => DrupalExpPage(initialTargetUrl: url),
  ),
  ExpEntry(
    icon: Icons.php,
    title: 'PHP 8.1.0-dev backdoor / CVE-2012-1823 PHP-CGI',
    subtitle: 'User-Agentt backdoor + CGI argument injection RCE',
    versionRequirement: 'PHP: 8.1.0-dev or CGI<5.3.12/<5.4.2 | Condition: backdoor header / CGI args reachable',
    tag: 'PHP · ${'Generic'}',
    pageBuilder: (url) => PhpExpPage(initialTargetUrl: url),
  ),
  ExpEntry(
    icon: Icons.cloud_upload,
    title: 'Apache Tomcat CVE-2017-12615',
    subtitle: 'Upload JSP Webshell when PUT method is enabled',
    versionRequirement: 'Tomcat: 8.5.19 | Condition: DefaultServlet readonly=false',
    tag: 'Java · Tomcat',
    pageBuilder: (url) => TomcatExpPage(initialTargetUrl: url),
  ),
  ExpEntry(
    icon: Icons.dns,
    title: 'Oracle WebLogic CVE-2017-10271 / CVE-2020-14882',
    subtitle: 'XMLDecoder deserialization + console unauth + WS test page upload RCE',
    versionRequirement: 'WebLogic: 10271<10.3.6; 14882/14883=12.2.1.3(12.2.1+) | Condition: console/component reachable',
    tag: 'Java · WebLogic',
    pageBuilder: (url) => WebLogicExpPage(initialTargetUrl: url),
  ),
  ExpEntry(
    icon: Icons.schedule,
    title: 'XXL-JOB unauthenticated executor RCE',
    subtitle: 'Submit arbitrary shell commands via GLUE_SHELL type (2.2.0)',
    versionRequirement: 'XXL-JOB: cross-check official advisory | Condition: unauthenticated executor',
    tag: 'Java · XXL-JOB',
    pageBuilder: (url) => XxlJobExpPage(initialTargetUrl: url),
  ),
  ExpEntry(
    icon: Icons.cloud,
    title: 'Nacos CVE-2021-29441',
    subtitle: 'User-Agent auth bypass, enumerate/create users (< 1.4.1)',
    versionRequirement: 'Nacos: <1.4.1 | Condition: User-Agent bypass chain reachable',
    tag: 'Java · Nacos',
    pageBuilder: (url) => NacosExpPage(initialTargetUrl: url),
  ),
];

List<ExpEntry> visibleExpEntries({bool includeDisabled = false}) {
  return expEntries
      .where((e) => includeDisabled || e.enabled)
      .toList(growable: false);
}
