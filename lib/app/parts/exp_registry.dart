import 'package:flutter/material.dart';

import '../../pages/thinkphp_exp_page.dart';
import '../../pages/vulhub/aria2_exp_page.dart';
import '../../pages/vulhub/drupal_exp_page.dart';
import '../../pages/vulhub/druid_exp_page.dart';
import '../../pages/vulhub/elasticsearch_exp_page.dart';
import '../../pages/vulhub/flask_ssti_exp_page.dart';
import '../../pages/vulhub/httpd_exp_page.dart';
import '../../pages/vulhub/nacos_exp_page.dart';
import '../../pages/vulhub/ofbiz_exp_page.dart';
import '../../pages/vulhub/php_exp_page.dart';
import '../../pages/vulhub/saltstack_exp_page.dart';
import '../../pages/vulhub/shellshock_exp_page.dart';
import '../../pages/vulhub/solr_exp_page.dart';
import '../../pages/vulhub/spring_exp_page.dart';
import '../../pages/vulhub/struts2_exp_page.dart';
import '../../pages/vulhub/supervisor_exp_page.dart';
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
  final Widget page;

  const ExpEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.versionRequirement,
    required this.tag,
    this.enabled = true,
    required this.page,
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
    page: const shiro.ShiroExpPage(),
  ),
  ExpEntry(
    icon: Icons.php,
    title: 'ThinkPHP CVE-2018-20062/CVE-2019-9082/CNVD-2022-86535',
    subtitle: S.expSubtitleThinkphp,
    versionRequirement: S.expVersionThinkphp,
    tag: 'PHP · ${S.expTagGeneric}',
    page: const ThinkphpExpPage(),
  ),
  ExpEntry(
    icon: Icons.storage,
    title: 'Zentao CVE-2024-24216',
    subtitle: S.expSubtitleZentao,
    versionRequirement: S.expVersionZentao,
    tag: 'PHP · ${S.expTagZentao}',
    page: const ZentaoExpPage(),
  ),
  ExpEntry(
    icon: Icons.bolt,
    title: 'Apache Struts2 S2-032/045/053/057/059',
    subtitle: S.expSubtitleStruts2,
    versionRequirement: S.expVersionStruts2,
    tag: 'Java · Struts2',
    page: const Struts2ExpPage(),
  ),
  ExpEntry(
    icon: Icons.local_florist,
    title: 'Spring Framework CVE-2022-22963/22965/2018-1273/2017-8046',
    subtitle: S.expSubtitleSpring,
    versionRequirement: S.expVersionSpring,
    tag: 'Java · Spring',
    page: const SpringExpPage(),
  ),
  ExpEntry(
    icon: Icons.http,
    title: 'Apache HTTP Server CVE-2021-41773',
    subtitle: S.expSubtitleHttpd,
    versionRequirement: S.expVersionHttpd,
    tag: 'C · Apache',
    page: const HttpdExpPage(),
  ),
  ExpEntry(
    icon: Icons.data_object,
    title: 'Apache Druid CVE-2021-25646',
    subtitle: S.expSubtitleDruid,
    versionRequirement: S.expVersionDruid,
    tag: 'Java · Druid',
    page: const DruidExpPage(),
  ),
  ExpEntry(
    icon: Icons.business,
    title: 'Apache OFBiz CVE-2023-51467 / CVE-2024-38856',
    subtitle: S.expSubtitleOfbiz,
    versionRequirement: S.expVersionOfbiz,
    tag: 'Java · OFBiz',
    page: const OFBizExpPage(),
  ),
  ExpEntry(
    icon: Icons.search,
    title: 'Apache Solr CVE-2017-12629',
    subtitle: S.expSubtitleSolr,
    versionRequirement: S.expVersionSolr,
    tag: 'Java · Solr',
    page: const SolrExpPage(),
  ),
  ExpEntry(
    icon: Icons.water_drop,
    title: 'Drupal CVE-2018-7600 (Drupalgeddon2)',
    subtitle: S.expSubtitleDrupal,
    versionRequirement: S.expVersionDrupal,
    tag: 'PHP · Drupal',
    page: const DrupalExpPage(),
  ),
  ExpEntry(
    icon: Icons.manage_search,
    title: 'Elasticsearch CVE-2015-1427',
    subtitle: S.expSubtitleElastic,
    versionRequirement: S.expVersionElastic,
    tag: 'Java · ES',
    page: const ElasticsearchExpPage(),
  ),
  ExpEntry(
    icon: Icons.code,
    title: 'Flask / Jinja2 SSTI',
    subtitle: S.expSubtitleFlaskSsti,
    versionRequirement: S.expVersionFlaskSsti,
    tag: 'Python · Flask',
    page: const FlaskSstiExpPage(),
  ),
  ExpEntry(
    icon: Icons.php,
    title: S.expTitlePhp,
    subtitle: S.expSubtitlePhp,
    versionRequirement: S.expVersionPhp,
    tag: 'PHP · ${S.expTagGeneric}',
    page: const PhpExpPage(),
  ),
  ExpEntry(
    icon: Icons.cloud_upload,
    title: 'Apache Tomcat CVE-2017-12615',
    subtitle: S.expSubtitleTomcat,
    versionRequirement: S.expVersionTomcat,
    tag: 'Java · Tomcat',
    page: const TomcatExpPage(),
  ),
  ExpEntry(
    icon: Icons.dns,
    title: 'Oracle WebLogic CVE-2017-10271 / CVE-2020-14882',
    subtitle: S.expSubtitleWeblogic,
    versionRequirement: S.expVersionWeblogic,
    tag: 'Java · WebLogic',
    page: const WebLogicExpPage(),
  ),
  ExpEntry(
    icon: Icons.article,
    title: 'Supervisor CVE-2017-11610',
    subtitle: S.expSubtitleSupervisor,
    versionRequirement: S.expVersionSupervisor,
    tag: 'Python · Supervisor',
    page: const SupervisorExpPage(),
  ),
  ExpEntry(
    icon: Icons.schedule,
    title: S.expTitleXxljob,
    subtitle: S.expSubtitleXxljob,
    versionRequirement: S.expVersionXxljob,
    tag: 'Java · XXL-JOB',
    page: const XxlJobExpPage(),
  ),
  ExpEntry(
    icon: Icons.cloud,
    title: 'Nacos CVE-2021-29441',
    subtitle: S.expSubtitleNacos,
    versionRequirement: S.expVersionNacos,
    tag: 'Java · Nacos',
    page: const NacosExpPage(),
  ),
  ExpEntry(
    icon: Icons.terminal,
    title: 'Bash Shellshock CVE-2014-6271',
    subtitle: S.expSubtitleShellshock,
    versionRequirement: S.expVersionShellshock,
    tag: 'Shell · Bash',
    page: const ShellshockExpPage(),
  ),
  ExpEntry(
    icon: Icons.grain,
    title: 'SaltStack CVE-2020-16846',
    subtitle: S.expSubtitleSaltstack,
    versionRequirement: S.expVersionSaltstack,
    tag: 'Python · SaltStack',
    page: const SaltstackExpPage(),
  ),
  ExpEntry(
    icon: Icons.download,
    title: S.expTitleAria2,
    subtitle: S.expSubtitleAria2,
    versionRequirement: S.expVersionAria2,
    tag: 'C · Aria2',
    page: const Aria2ExpPage(),
  ),
];

List<ExpEntry> visibleExpEntries({bool includeDisabled = false}) {
  return expEntries
      .where((e) => includeDisabled || e.enabled)
      .toList(growable: false);
}
