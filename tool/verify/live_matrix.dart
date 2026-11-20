// 实靶矩阵：起容器 → 跑真模块 → 断言 → 拆容器。
//
// 存在理由：这几轮的缺陷（S2-007 数组载荷、base64 依赖、Spring4Shell 双文件名、
// XXL-JOB 假阴性）都是靠"手敲 module_smoke + 盯输出"发现的，改一次代码就要重来一遍。
// 这里把已验证过的场景固化成可重跑用例，`--only` 可只跑一个。
//
// 前置：本机有 docker，且对应镜像已存在（vulhub/* 与 mxlab-*）。
// 用法：
//   dart tool/verify/live_matrix.dart
//   dart tool/verify/live_matrix.dart --only=struts2-s2007,php-backdoor
//   dart tool/verify/live_matrix.dart --keep   # 失败时保留容器便于排查

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../lib/exp/core/exploit_module.dart';
import '../../lib/exp/core/exp_catalog.dart';
import '../../lib/exp/core/exp_spec.dart';
import '../../lib/exp/core/scan_runner.dart';

enum Expect {
  /// 正常通过：check 命中 / exec 有回显 / shell 非空。
  pass,

  /// 被 WAF 拦截：check 必须报"探测失败（被拦）"，而不是"未检测到"。
  blockedOnCheck,

  /// 被 WAF 拦截：check 可以过，但 exec 必须报"被拦"，而不是返回错误页。
  blockedOnExec,
}

class Case {
  const Case({
    required this.moduleId,
    required this.image,
    required this.port,
    this.containerPort,
    required this.wantCheck,
    this.wantExec = false,
    this.wantShell = false,
    this.extra = const {},
    this.note = '',
    this.mount = '',
    this.installer = '',
    this.expect = Expect.pass,
    this.wafPreset = '',
    this.wafPort = 0,
  });

  final String moduleId;
  final String image;
  final int port;
  final int? containerPort;
  final bool wantCheck;
  final bool wantExec;
  final bool wantShell;
  final Map<String, String> extra;
  final String note;

  /// 相对 `VULHUB_DIR` 的挂载（`宿主路径:容器路径:ro`），空表示不需要。
  final String mount;

  /// 非空则启动后先跑安装脚本（`drupal`），失败即跳过本用例。
  final String installer;

  final Expect expect;

  /// 非空则在该容器前挂一层 `waf_proxy.dart`（strict / keywords）。
  final String wafPreset;
  final int wafPort;
}

const _cases = <Case>[
  Case(
    moduleId: 'struts2-s2007',
    image: 'mxlab-struts2:latest',
    port: 18110,
    containerPort: 8080,
    wantCheck: true,
    wantExec: true,
    wantShell: true,
    extra: {'path': 'user.action'},
    note: 'S2-007 需要 user.action 表单入口；exec 用 ProcessBuilder(list) 载荷',
  ),
  Case(
    moduleId: 'php-backdoor',
    image: 'vulhub/php:8.1-backdoor',
    port: 18111,
    containerPort: 80,
    wantCheck: true,
    wantExec: true,
    wantShell: true,
    note: 'User-Agentt 后门；镜像不含 index.php，需要从 vulhub 挂载',
    mount: 'php/8.1-backdoor/index.php:/var/www/html/index.php:ro',
  ),
  Case(
    moduleId: 'thinkphp-tp5023',
    image: 'vulhub/thinkphp:5.0.23',
    port: 18112,
    containerPort: 80,
    wantCheck: true,
    wantExec: true,
    wantShell: true,
    note: '原生写马；曾因 "url Pass:pwd" 返回展示字符串而连不上',
  ),
  Case(
    moduleId: 'spring-22965',
    image: 'vulhub/spring-webmvc:5.3.17',
    port: 18113,
    containerPort: 8080,
    wantCheck: true,
    wantExec: true,
    note: 'AccessLogValve 写 JSP；check/exec 必须共用 m4xm.jsp',
  ),
  Case(
    moduleId: 'shiro-2016-4437',
    image: 'vulhub/shiro:1.2.4',
    port: 18114,
    containerPort: 8080,
    wantCheck: true,
    wantShell: true,
    note: 'rememberMe 爆破 + Filter 内存马',
  ),
  Case(
    moduleId: 'nacos-2021-29441',
    image: 'vulhub/nacos:1.4.0',
    port: 18848,
    containerPort: 8848,
    wantCheck: true,
    note: '认证绕过读用户列表（无 exec 能力）',
  ),
  Case(
    moduleId: 'httpd-2021-41773',
    image: 'mxlab-httpd-2021-41773-apache:latest',
    port: 18115,
    containerPort: 80,
    wantCheck: true,
    wantExec: true,
    note: '路径穿越 + CGI；错误页不能当命令输出',
  ),
  Case(
    moduleId: 'tomcat-2017-12615',
    image: 'mxlab-tomcat-2017-12615-tomcat:latest',
    port: 18116,
    containerPort: 8080,
    wantCheck: true,
    wantExec: true,
    wantShell: true,
    note: 'PUT 写 JSP；WAF 下 exec 必须报"被拦"而不是返回 404 页',
  ),
  Case(
    moduleId: 'struts2-s2045',
    image: 'mxlab-struts2:latest',
    port: 18117,
    containerPort: 8080,
    wantCheck: false,
    wantExec: false,
    expect: Expect.blockedOnCheck,
    wafPreset: 'strict',
    wafPort: 18118,
    note: '严格 WAF 下 S2-045 的 Content-Type 载荷会被拦：必须报"没测通"',
  ),
  Case(
    moduleId: 'tomcat-2017-12615',
    image: 'mxlab-tomcat-2017-12615-tomcat:latest',
    port: 18119,
    containerPort: 8080,
    wantCheck: true,
    wantExec: true,
    expect: Expect.blockedOnExec,
    wafPreset: 'keywords',
    wafPort: 18120,
    note: '关键字 WAF 会拦 shell JSP 的 PUT：exec 必须报"被拦"，不能返回 404 页',
  ),
  Case(
    moduleId: 'struts2-s2032',
    image: 'vulhub/struts2:2.3.28',
    port: 18160,
    containerPort: 8080,
    wantCheck: true,
    note: 'S2-032 DMI；marker 改为服务端计算 (235*235) 后仍需真阳性',
  ),
  Case(
    moduleId: 'struts2-s2045',
    image: 'vulhub/struts2:2.3.30',
    port: 18161,
    containerPort: 8080,
    wantCheck: true,
    note: 'S2-045 Content-Type；marker 236*236',
  ),
  Case(
    moduleId: 'struts2-s2052',
    image: 'vulhub/struts2:2.5.12-rest-showcase',
    port: 18162,
    containerPort: 8080,
    wantCheck: true,
    note: 'S2-052 REST/XStream：只认 XStream 特征（旧实现任何 REST 端点都命中）',
  ),
  Case(
    moduleId: 'struts2-s2053',
    image: 'vulhub/struts2:s2-053',
    port: 18163,
    containerPort: 8080,
    wantCheck: true,
    note: 'S2-053 Freemarker 二次求值；marker 237*237',
  ),
  Case(
    moduleId: 'struts2-s2059',
    image: 'vulhub/struts2:2.5.16',
    port: 18164,
    containerPort: 8080,
    wantCheck: true,
    note: 'S2-059 标签属性二次求值；marker 239*239',
  ),
  Case(
    moduleId: 'spring-8046',
    image: 'vulhub/spring-rest-data:2.6.6',
    port: 18184,
    containerPort: 8080,
    wantCheck: true,
    note: 'Spring Data REST PATCH；判定已收紧到 SpEL 异常特征，需真阳性仍在',
  ),
  Case(
    moduleId: 'spring-1273',
    image: 'vulhub/spring-data-commons:2.0.5',
    port: 18185,
    containerPort: 8080,
    wantCheck: true,
    note: 'Spring Data Commons；命中依据是绑定异常回显（盲执行）',
  ),
  Case(
    moduleId: 'spring-4977',
    image: 'vulhub/spring-security-oauth2:2.0.8',
    port: 18186,
    containerPort: 8080,
    wantCheck: true,
    note: 'Spring Security OAuth；marker 240*240 服务端计算',
  ),
  Case(
    moduleId: 'struts2-s2005',
    image: 'mxlab-struts2-s2-005-struts2:latest',
    port: 18166,
    containerPort: 8080,
    wantCheck: true,
    note: 'S2-005：check 用 POST 回显；exec 在该镜像上无回显（已知）',
  ),
  Case(
    moduleId: 'spring-22963',
    image: 'vulhub/spring-cloud-function:3.2.2',
    port: 18167,
    containerPort: 8080,
    wantCheck: true,
    note: 'SCF 时间侧信道；exec 无回显通道（已如实报错）',
  ),
  Case(
    moduleId: 'thinkphp-tp2',
    image: 'vulhub/thinkphp:2.1',
    port: 18168,
    containerPort: 80,
    wantCheck: true,
    note: 'ThinkPHP 2.x preg_replace /e',
  ),
  Case(
    moduleId: 'thinkphp-tp5022',
    image: 'vulhub/thinkphp:5.0.20',
    port: 18169,
    containerPort: 80,
    wantCheck: true,
    note: 'ThinkPHP 5.0.20 invokefunction 链',
  ),
  Case(
    moduleId: 'php-cgi-2012-1823',
    image: 'vulhub/php:5.4.1-cgi',
    port: 18170,
    containerPort: 80,
    wantCheck: true,
    wantExec: true,
    mount: 'php/CVE-2012-1823/www:/var/www/html:ro',
    note: '镜像本身只有 index.html，必须挂载 labs 的 www 目录才有 index.php',
  ),
  Case(
    moduleId: 'drupal-2018-7600',
    image: 'vulhub/drupal:8.5.0',
    port: 18165,
    containerPort: 80,
    wantCheck: true,
    wantExec: true,
    wantShell: true,
    installer: 'drupal',
    note: '镜像默认未安装；安装脚本必须跑完批次（半装时 check 会正确报"未安装"）',
  ),
  Case(
    moduleId: 'weblogic-10271',
    image: 'vulhub/weblogic:10.3.6.0-2017',
    port: 17001,
    containerPort: 7001,
    wantCheck: true,
    note: 'WLS-WSAT XMLDecoder；启动慢，超时给足',
  ),
];

Future<void> main(List<String> args) async {
  final only = args
      .firstWhere((a) => a.startsWith('--only='), orElse: () => '')
      .split('=')
      .last;
  final keep = args.contains('--keep');
  final jobsArg =
      args.firstWhere((a) => a.startsWith('--jobs='), orElse: () => '');
  final jobs = jobsArg.isEmpty
      ? 3
      : (int.tryParse(jobsArg.split('=').last) ?? 3).clamp(1, 8);
  final cases = only.isEmpty
      ? _cases
      : _cases.where((c) => only.split(',').contains(c.moduleId)).toList();

  stdout.writeln('[*] ${cases.length} 个用例，并发 $jobs');

  // 每个用例的端口互不重叠，容器名互不冲突，可以安全并行。
  // 输出按用例缓冲，避免多行交错。
  final buffers = List<List<String>?>.filled(cases.length, null);
  final queue = List<int>.generate(cases.length, (i) => i).toList();

  Future<void> worker() async {
    while (queue.isNotEmpty) {
      final idx = queue.removeAt(0);
      buffers[idx] = await _runCase(cases[idx], keep: keep);
    }
  }

  await Future.wait(List.generate(jobs, (_) => worker()));

  var pass = 0;
  final failures = <String>[];
  for (var i = 0; i < cases.length; i++) {
    final lines = buffers[i] ?? ['[!] 用例未执行'];
    for (final l in lines) {
      stdout.writeln(l);
    }
    if (lines.isNotEmpty && lines.last == '[+] PASS') {
      pass++;
    } else if (lines.isNotEmpty && lines.last.startsWith('[!] FAIL')) {
      failures.add('${cases[i].moduleId}: ${lines.last.substring(8)}');
    } else {
      failures.add('${cases[i].moduleId}: 未完成');
    }
  }

  stdout.writeln('\n===== 结果：$pass/${cases.length} 通过 =====');
  for (final f in failures) {
    stdout.writeln('[!] $f');
  }
  exit(failures.isEmpty ? 0 : 1);
}

/// 跑单个用例，返回该用例的输出行（最后一行是 PASS/FAIL）。
Future<List<String>> _runCase(Case c, {required bool keep}) async {
  final out = <String>[];
  final name = 'lm-${c.moduleId}-${c.port}';
  out.add('\n=== ${c.moduleId}  (${c.image}) ===');
  if (c.note.isNotEmpty) out.add('    ${c.note}');

  await _docker(['rm', '-f', name], allowFail: true);
  final vulhub =
      Platform.environment['VULHUB_DIR'] ?? '/Users/illya/Projects/vulhub';
  final run = await _docker([
    'run', '-d', '--rm', '--name', name,
    '-p', '${c.port}:${c.containerPort ?? c.port}',
    if (c.mount.isNotEmpty) ...['-v', '$vulhub/${c.mount}'],
    c.image,
  ], allowFail: true);
  if (run != 0) {
    out.add('[!] FAIL docker run 失败');
    return out;
  }

  var url = 'http://127.0.0.1:${c.port}';
  if (!await _waitHttp(url, const Duration(seconds: 300))) {
    out.add('[!] FAIL 端口未就绪');
    if (!keep) await _docker(['rm', '-f', name], allowFail: true);
    return out;
  }

  if (c.installer.isNotEmpty) {
    out.add('    install: ${c.installer}');
    final r = await Process.run(
      'python3',
      ['tool/verify/drupal_install.py', url],
      workingDirectory: Directory.current.path,
    ).timeout(const Duration(minutes: 8));
    if (r.exitCode != 0) {
      out.add('[!] FAIL 安装脚本失败');
      if (!keep) await _docker(['rm', '-f', name], allowFail: true);
      return out;
    }
  }

  Process? waf;
  if (c.wafPreset.isNotEmpty) {
    waf = await Process.start(
      Platform.resolvedExecutable,
      ['tool/verify/waf_proxy.dart', url, '${c.wafPort}', '--preset=${c.wafPreset}'],
      workingDirectory: Directory.current.path,
    );
    waf.stdout.transform(utf8.decoder).listen((_) {});
    waf.stderr.transform(utf8.decoder).listen((_) {});
    url = 'http://127.0.0.1:${c.wafPort}';
    if (!await _waitHttp(url, const Duration(seconds: 60))) {
      out.add('[!] FAIL WAF 代理未就绪');
      waf.kill();
      if (!keep) await _docker(['rm', '-f', name], allowFail: true);
      return out;
    }
    out.add('    waf: --preset=${c.wafPreset} @ :${c.wafPort}');
  }

  final module = moduleById(c.moduleId);
  final variant = allVariants
      .firstWhere((e) => e.$2.moduleId == c.moduleId, orElse: () => allVariants.first)
      .$2;
  if (module == null) {
    out.add('[!] FAIL 模块未注册');
    waf?.kill();
    if (!keep) await _docker(['rm', '-f', name], allowFail: true);
    return out;
  }

  final target = ExploitTarget(
    url: url,
    timeout: const Duration(seconds: 10),
    extra: c.extra,
  );
  final problems = <String>[];

  if (c.expect == Expect.blockedOnCheck) {
    final r = await module.check(target);
    out.add('    check: ${r.summary}');
    if (r.vulnerable) {
      problems.add('被拦却报命中（假阳性）');
    } else if (!r.failed) {
      problems.add('被拦却报"未检测到"（假阴性）');
    }
  } else if (c.wantCheck) {
    final r = await module.check(target);
    if (!r.vulnerable) problems.add('check 未命中（${r.summary}）');
    // 标了 strong 的变体，必须真的拿到"确认命中"，否则说明强度标错了。
    if (r.vulnerable) {
      final conf = confidenceOf(variant, r);
      out.add('    check: ${r.summary}  [${conf.label}]');
      if (variant.evidence == ExpEvidence.strong &&
          conf != ScanConfidence.confirmed) {
        problems.add('标称强证据，实际 ${conf.label}');
      }
    } else {
      out.add('    check: ${r.summary}');
    }
  }

  if (c.expect == Expect.blockedOnExec) {
    try {
      final o = await module.exec(target, 'id');
      final head = (o ?? '').trimLeft().toLowerCase();
      out.add('    exec : ${o?.trim().split('\n').first ?? 'null'}');
      if (head.startsWith('<!doctype') || head.startsWith('<html')) {
        problems.add('把错误页当成命令输出（假成功）');
      } else if (o != null && !o.contains('被 WAF 拦截')) {
        problems.add('被拦却没有报"被拦"（返回：${o.split('\n').first}）');
      }
    } catch (e) {
      out.add('    exec : [!] $e');
    }
  } else if (c.wantExec && module.supports(ExploitCapability.exec)) {
    try {
      final o = await module.exec(target, 'id');
      final ok = o != null && o.contains('uid=');
      if (!ok) problems.add('exec 无有效输出（${o?.split('\n').first ?? 'null'}）');
      out.add('    exec : ${o?.trim().split('\n').first ?? 'null'}');
    } catch (e) {
      problems.add('exec 抛错：$e');
      out.add('    exec : [!] $e');
    }
  }

  if (c.wantShell && module.supports(ExploitCapability.getShell)) {
    final shell = await module.getShell(target);
    if (shell == null) {
      problems.add('shell 为空');
      out.add('    shell: null');
    } else {
      out.add('    shell: ${shell.summary}');
    }
  }

  waf?.kill();
  if (!keep) await _docker(['rm', '-f', name], allowFail: true);

  if (problems.isEmpty) {
    out.add('[+] PASS');
  } else {
    out.add('[!] FAIL ${problems.join(' / ')}');
  }
  return out;
}

Future<int> _docker(List<String> args, {bool allowFail = false}) async {
  final r = await Process.run('docker', args).timeout(const Duration(minutes: 6));
  if (r.exitCode != 0 && !allowFail) {
    stderr.writeln('[docker ${args.first}] ${r.stderr}');
  }
  return r.exitCode;
}

Future<bool> _waitHttp(String url, Duration limit) async {
  final deadline = DateTime.now().add(limit);
  while (DateTime.now().isBefore(deadline)) {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
      final req = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 3));
      final res = await req.close().timeout(const Duration(seconds: 3));
      await res.drain<void>();
      client.close();
      if (res.statusCode > 0) return true;
    } catch (_) {
      // 还没起来
    }
    try {
      // 传递性一致：避免容器只起了端口但应用没起
      await Process.run('sleep', ['2']);
    } catch (_) {
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }
  return false;
}

// 让 linter 知道 jsonEncode 被用到（保留给后续扩展打印结构体）
// ignore: unused_element
String _pretty(Object o) => const JsonEncoder.withIndent('  ').convert(o);
