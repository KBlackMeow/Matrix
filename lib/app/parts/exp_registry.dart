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

final List<ExpEntry> expEntries = [
  ExpEntry(
    icon: Icons.cookie,
    title: 'Apache Shiro CVE-2016-4437',
    subtitle: 'rememberMe Key 爆破 / Payload 注入',
    versionRequirement: 'Shiro: <=1.2.4 | 条件: rememberMe 默认密钥场景',
    tag: 'Java · 通用',

    page: shiro.ShiroExpPage(),
  ),
  ExpEntry(
    icon: Icons.php,
    title: 'ThinkPHP CVE-2018-20062/CVE-2019-9082/CNVD-2022-86535',
    subtitle: '3.x/5.x/6.x 漏洞检测、RCE、GetShell',
    versionRequirement: 'ThinkPHP: 2.x / <=5.0.23 / 5.0.22/5.1.29 | 条件: 路由/调用链可达',
    tag: 'PHP · 通用',

    page: ThinkphpExpPage(),
  ),
  ExpEntry(
    icon: Icons.storage,
    title: 'Zentao CVE-2024-24216',
    subtitle: '绕过登录 · Repo 配置写入冰蝎 WebShell',
    versionRequirement: 'Zentao: 请按官方公告版本区间核对 | 条件: 漏洞链路可达',
    tag: 'PHP · 禅道',

    page: ZentaoExpPage(),
  ),
  ExpEntry(
    icon: Icons.bolt,
    title: 'Apache Struts2 S2-032/045/053/057/059',
    subtitle: 'OGNL 表达式注入 RCE 系列',
    versionRequirement:
        'Struts2: S2-032=2.3.20-2.3.28(除2.3.20.3/2.3.24.3); S2-045/053/057/059=2.0.0-2.5.20 | 条件: 对应 OGNL 触发面存在',
    tag: 'Java · Struts2',

    page: Struts2ExpPage(),
  ),
  ExpEntry(
    icon: Icons.local_florist,
    title: 'Spring Framework CVE-2022-22963/22965/2018-1273/2017-8046',
    subtitle: 'Spring4Shell / Cloud Function / Data SpEL 注入系列',
    versionRequirement:
        'Spring: 22965=5.3.17; 22963=SCF 3.2.2; 1273=Data Commons<=2.0.5; 8046=Data REST 2.6.6 | 条件: 各 CVE 对应部署方式满足',
    tag: 'Java · Spring',

    page: SpringExpPage(),
  ),
  ExpEntry(
    icon: Icons.http,
    title: 'Apache HTTP Server CVE-2021-41773',
    subtitle: '路径规范化缺陷 — 路径穿越文件读取 + CGI RCE',
    versionRequirement: 'HTTPd: =2.4.49 | 条件: 目录访问配置允许穿越',
    tag: 'C · Apache',

    page: HttpdExpPage(),
  ),
  ExpEntry(
    icon: Icons.data_object,
    title: 'Apache Druid CVE-2021-25646',
    subtitle: '嵌入式 JavaScript 代码注入 RCE (≤ 0.20.0)',
    versionRequirement: 'Druid: <=0.20.0 | 条件: sampler/indexer 接口可访问',
    tag: 'Java · Druid',

    page: DruidExpPage(),
  ),
  ExpEntry(
    icon: Icons.business,
    title: 'Apache OFBiz CVE-2023-51467 / CVE-2024-38856',
    subtitle: 'Groovy 代码注入无需认证 RCE',
    versionRequirement: 'OFBiz: 18.12.10 / 18.12.11 | 条件: ProgramExport 路径可达',
    tag: 'Java · OFBiz',

    page: OFBizExpPage(),
  ),
  ExpEntry(
    icon: Icons.search,
    title: 'Apache Solr CVE-2017-12629',
    subtitle: 'RunExecutableListener 任意命令执行 (< 7.1.0)',
    versionRequirement: 'Solr: <7.1.0 | 条件: config API 可写 listener',
    tag: 'Java · Solr',

    page: SolrExpPage(),
  ),
  ExpEntry(
    icon: Icons.water_drop,
    title: 'Drupal CVE-2018-7600 (Drupalgeddon2)',
    subtitle: 'Form API #post_render 回调 PHP 代码执行',
    versionRequirement: 'Drupal: <7.58; 8.x<8.3.9/<8.4.6/<8.5.1 | 条件: Form API 路径可达',
    tag: 'PHP · Drupal',

    page: DrupalExpPage(),
  ),
  ExpEntry(
    icon: Icons.manage_search,
    title: 'Elasticsearch CVE-2015-1427',
    subtitle: 'Groovy 脚本沙箱逃逸 RCE (< 1.3.8 / < 1.4.3)',
    versionRequirement: 'Elasticsearch: <1.3.8 或 <1.4.3 | 条件: 动态脚本执行可用',
    tag: 'Java · ES',

    page: ElasticsearchExpPage(),
  ),
  ExpEntry(
    icon: Icons.code,
    title: 'Flask / Jinja2 SSTI',
    subtitle: '服务端模板注入执行任意 Python 代码',
    versionRequirement: 'Flask/Jinja2: 取决于组件版本 | 条件: 存在 SSTI 模板注入点',
    tag: 'Python · Flask',

    page: FlaskSstiExpPage(),
  ),
  ExpEntry(
    icon: Icons.php,
    title: 'PHP 8.1.0-dev 后门 / CVE-2012-1823 PHP-CGI',
    subtitle: 'User-Agentt 后门 + CGI 参数注入 RCE',
    versionRequirement: 'PHP: 8.1.0-dev 或 CGI<5.3.12/<5.4.2 | 条件: 后门头/CGI 参数可达',
    tag: 'PHP · 通用',

    page: PhpExpPage(),
  ),
  ExpEntry(
    icon: Icons.cloud_upload,
    title: 'Apache Tomcat CVE-2017-12615',
    subtitle: 'PUT 方法开启时上传 JSP Webshell RCE',
    versionRequirement: 'Tomcat: 8.5.19 | 条件: DefaultServlet readonly=false',
    tag: 'Java · Tomcat',

    page: TomcatExpPage(),
  ),
  ExpEntry(
    icon: Icons.dns,
    title: 'Oracle WebLogic CVE-2017-10271 / CVE-2020-14882',
    subtitle: 'XMLDecoder 反序列化 + 控制台未授权 + WS 测试页文件上传 RCE',
    versionRequirement: 'WebLogic: 10271<10.3.6; 14882/14883=12.2.1.3(12.2.1+) | 条件: 控制台/组件路径可达',
    tag: 'Java · WebLogic',

    page: WebLogicExpPage(),
  ),
  ExpEntry(
    icon: Icons.article,
    title: 'Supervisor CVE-2017-11610',
    subtitle: 'XML-RPC 未授权方法调用链 RCE (3.3.2)',
    versionRequirement: 'Supervisor: <3.3.3 | 条件: XML-RPC 接口可访问',
    tag: 'Python · Supervisor',

    page: SupervisorExpPage(),
  ),
  ExpEntry(
    icon: Icons.schedule,
    title: 'XXL-JOB 未授权访问执行器 RCE',
    subtitle: 'GLUE_SHELL 类型提交任意 Shell 命令 (2.2.0)',
    versionRequirement: 'XXL-JOB: 按官方公告核对 | 条件: 未授权访问执行器接口',
    tag: 'Java · XXL-JOB',

    page: XxlJobExpPage(),
  ),
  ExpEntry(
    icon: Icons.cloud,
    title: 'Nacos CVE-2021-29441',
    subtitle: 'User-Agent 认证绕过，枚举/创建用户 (< 1.4.1)',
    versionRequirement: 'Nacos: <1.4.1 | 条件: User-Agent 绕过链可达',
    tag: 'Java · Nacos',

    page: NacosExpPage(),
  ),
  ExpEntry(
    icon: Icons.terminal,
    title: 'Bash Shellshock CVE-2014-6271',
    subtitle: '环境变量函数定义解析注入 CGI RCE',
    versionRequirement: 'Bash: <=4.3(补丁前) | 条件: CGI/环境变量注入可达',
    tag: 'Shell · Bash',

    page: ShellshockExpPage(),
  ),
  ExpEntry(
    icon: Icons.grain,
    title: 'SaltStack CVE-2020-16846',
    subtitle: 'SSH 模块 ssh_priv 参数命令注入 RCE',
    versionRequirement: 'SaltStack: 按官方补丁区间核对 | 条件: Master API 未授权调用链',
    tag: 'Python · SaltStack',

    page: SaltstackExpPage(),
  ),
  ExpEntry(
    icon: Icons.download,
    title: 'Aria2 未授权 RPC → Cron 写入 RCE',
    subtitle: 'JSON-RPC 未授权，addUri 写入 /etc/cron.d/ 触发反弹 Shell',
    versionRequirement: 'Aria2: 按官方版本公告核对 | 条件: 未授权 RPC + 可写 cron',
    tag: 'C · Aria2',

    page: Aria2ExpPage(),
  ),
];

List<ExpEntry> visibleExpEntries({bool includeDisabled = false}) {
  return expEntries
      .where((e) => includeDisabled || e.enabled)
      .toList(growable: false);
}
