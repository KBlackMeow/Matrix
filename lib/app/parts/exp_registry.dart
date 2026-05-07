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
import 'shiro_exp.dart' as shiro;

class ExpEntry {
  final IconData icon;
  final String title;
  final String subtitle;
  final String tag;
  final bool enabled;
  final Widget page;

  const ExpEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tag,
    this.enabled = true,
    required this.page,
  });
}

final List<ExpEntry> expEntries = [
  ExpEntry(
    icon: Icons.cookie,
    title: 'Apache Shiro CVE-2016-4437',
    subtitle: 'rememberMe Key 爆破 / Payload 注入',
    tag: 'Java · 通用',

    page: shiro.ShiroExpPage(),
  ),
  ExpEntry(
    icon: Icons.php,
    title: 'ThinkPHP CVE-2018-20062/CVE-2019-9082/CNVD-2022-86535',
    subtitle: '3.x/5.x/6.x 漏洞检测、RCE、GetShell',
    tag: 'PHP · 通用',

    page: ThinkphpExpPage(),
  ),
  ExpEntry(
    icon: Icons.storage,
    title: 'Zentao CVE-2024-24216',
    subtitle: '绕过登录 · Repo 配置写入冰蝎 WebShell',
    tag: 'PHP · 禅道',

    page: ZentaoExpPage(),
  ),
  ExpEntry(
    icon: Icons.bolt,
    title: 'Apache Struts2 S2-032/045/053/057/059',
    subtitle: 'OGNL 表达式注入 RCE 系列',
    tag: 'Java · Struts2',

    page: Struts2ExpPage(),
  ),
  ExpEntry(
    icon: Icons.local_florist,
    title: 'Spring Framework CVE-2022-22963/22965/2018-1273/2017-8046',
    subtitle: 'Spring4Shell / Cloud Function / Data SpEL 注入系列',
    tag: 'Java · Spring',

    page: SpringExpPage(),
  ),
  ExpEntry(
    icon: Icons.http,
    title: 'Apache HTTP Server CVE-2021-41773',
    subtitle: '路径规范化缺陷 — 路径穿越文件读取 + CGI RCE',
    tag: 'C · Apache',

    page: HttpdExpPage(),
  ),
  ExpEntry(
    icon: Icons.data_object,
    title: 'Apache Druid CVE-2021-25646',
    subtitle: '嵌入式 JavaScript 代码注入 RCE (≤ 0.20.0)',
    tag: 'Java · Druid',

    page: DruidExpPage(),
  ),
  ExpEntry(
    icon: Icons.business,
    title: 'Apache OFBiz CVE-2023-51467 / CVE-2024-38856',
    subtitle: 'Groovy 代码注入无需认证 RCE',
    tag: 'Java · OFBiz',

    page: OFBizExpPage(),
  ),
  ExpEntry(
    icon: Icons.search,
    title: 'Apache Solr CVE-2017-12629',
    subtitle: 'RunExecutableListener 任意命令执行 (< 7.1.0)',
    tag: 'Java · Solr',

    page: SolrExpPage(),
  ),
  ExpEntry(
    icon: Icons.water_drop,
    title: 'Drupal CVE-2018-7600 (Drupalgeddon2)',
    subtitle: 'Form API #post_render 回调 PHP 代码执行',
    tag: 'PHP · Drupal',

    page: DrupalExpPage(),
  ),
  ExpEntry(
    icon: Icons.manage_search,
    title: 'Elasticsearch CVE-2015-1427',
    subtitle: 'Groovy 脚本沙箱逃逸 RCE (< 1.3.8 / < 1.4.3)',
    tag: 'Java · ES',

    page: ElasticsearchExpPage(),
  ),
  ExpEntry(
    icon: Icons.code,
    title: 'Flask / Jinja2 SSTI',
    subtitle: '服务端模板注入执行任意 Python 代码',
    tag: 'Python · Flask',

    page: FlaskSstiExpPage(),
  ),
  ExpEntry(
    icon: Icons.php,
    title: 'PHP 8.1.0-dev 后门 / CVE-2012-1823 PHP-CGI',
    subtitle: 'User-Agentt 后门 + CGI 参数注入 RCE',
    tag: 'PHP · 通用',

    page: PhpExpPage(),
  ),
  ExpEntry(
    icon: Icons.cloud_upload,
    title: 'Apache Tomcat CVE-2017-12615',
    subtitle: 'PUT 方法开启时上传 JSP Webshell RCE',
    tag: 'Java · Tomcat',

    page: TomcatExpPage(),
  ),
  ExpEntry(
    icon: Icons.dns,
    title: 'Oracle WebLogic CVE-2017-10271 / CVE-2020-14882',
    subtitle: 'XMLDecoder 反序列化 + 控制台未授权 + WS 测试页文件上传 RCE',
    tag: 'Java · WebLogic',

    page: WebLogicExpPage(),
  ),
  ExpEntry(
    icon: Icons.article,
    title: 'Supervisor CVE-2017-11610',
    subtitle: 'XML-RPC 未授权方法调用链 RCE (3.3.2)',
    tag: 'Python · Supervisor',

    page: SupervisorExpPage(),
  ),
  ExpEntry(
    icon: Icons.schedule,
    title: 'XXL-JOB 未授权访问执行器 RCE',
    subtitle: 'GLUE_SHELL 类型提交任意 Shell 命令 (2.2.0)',
    tag: 'Java · XXL-JOB',

    page: XxlJobExpPage(),
  ),
  ExpEntry(
    icon: Icons.cloud,
    title: 'Nacos CVE-2021-29441',
    subtitle: 'User-Agent 认证绕过，枚举/创建用户 (< 1.4.1)',
    tag: 'Java · Nacos',

    page: NacosExpPage(),
  ),
  ExpEntry(
    icon: Icons.terminal,
    title: 'Bash Shellshock CVE-2014-6271',
    subtitle: '环境变量函数定义解析注入 CGI RCE',
    tag: 'Shell · Bash',

    page: ShellshockExpPage(),
  ),
  ExpEntry(
    icon: Icons.grain,
    title: 'SaltStack CVE-2020-16846',
    subtitle: 'SSH 模块 ssh_priv 参数命令注入 RCE',
    tag: 'Python · SaltStack',

    page: SaltstackExpPage(),
  ),
  ExpEntry(
    icon: Icons.download,
    title: 'Aria2 未授权 RPC → Cron 写入 RCE',
    subtitle: 'JSON-RPC 未授权，addUri 写入 /etc/cron.d/ 触发反弹 Shell',
    tag: 'C · Aria2',

    page: Aria2ExpPage(),
  ),
];

List<ExpEntry> visibleExpEntries({bool includeDisabled = false}) {
  return expEntries
      .where((e) => includeDisabled || e.enabled)
      .toList(growable: false);
}
