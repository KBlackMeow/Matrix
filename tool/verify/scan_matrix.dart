// 扫描矩阵：在真实靶场上跑完整 27 变体扫描，断言"命中集合完全相等"。
//
// 为什么单独一个脚本：`scan_live` 只打印结果，人眼判断；这里把"这个靶场应该
// 只命中哪几个变体"变成断言。任何跨家族假阳性（比如扫 spring 靶场却命中
// struts2）都会直接变红。
//
// 前置：本机有 docker 且镜像已存在。
// 用法：
//   dart tool/verify/scan_matrix.dart
//   dart tool/verify/scan_matrix.dart --only=spring-22965
//   VULHUB_DIR=/path/to/vulhub dart tool/verify/scan_matrix.dart

import 'dart:io';

import '../../lib/exp/core/exp_catalog.dart';
import '../../lib/exp/core/scan_runner.dart';

class ScanCase {
  const ScanCase({
    required this.name,
    required this.image,
    required this.port,
    this.containerPort,
    this.mount = '',
    required this.expectedHits,
    this.note = '',
  });

  final String name;
  final String image;
  final int port;
  final int? containerPort;

  /// 相对 VULHUB_DIR 的挂载（宿主:容器:ro）。
  final String mount;

  /// 期望命中的 moduleId 集合（要求**完全相等**）。
  final Set<String> expectedHits;

  final String note;
}

const _cases = <ScanCase>[
  ScanCase(
    name: 'tomcat',
    image: 'mxlab-tomcat-2017-12615-tomcat:latest',
    port: 18130,
    containerPort: 8080,
    expectedHits: {'tomcat-2017-12615'},
    note: '纯 Tomcat：只应命中 PUT 写 JSP',
  ),
  ScanCase(
    name: 'spring-22965',
    image: 'vulhub/spring-webmvc:5.3.17',
    port: 18131,
    containerPort: 8080,
    expectedHits: {'spring-22965'},
    note: 'Spring4Shell：不应命中其余 4 个 spring 变体，也不应命中 struts2',
  ),
  ScanCase(
    name: 'spring-1273',
    image: 'vulhub/spring-data-commons:2.0.5',
    port: 18137,
    containerPort: 8080,
    expectedHits: {'spring-1273'},
    note: 'Data Commons：其余 spring 变体不应跟着响',
  ),
  ScanCase(
    name: 'spring-4977',
    image: 'vulhub/spring-security-oauth2:2.0.8',
    port: 18138,
    containerPort: 8080,
    expectedHits: {'spring-4977'},
    note: 'OAuth SpEL：marker 240*240 服务端计算',
  ),
  ScanCase(
    name: 'thinkphp-2.1',
    image: 'vulhub/thinkphp:2.1',
    port: 18139,
    containerPort: 80,
    expectedHits: {'thinkphp-tp2'},
    note: 'ThinkPHP 2.x：tp5023/tp5022 不应跟着响',
  ),
  ScanCase(
    name: 'thinkphp-5.0.20',
    image: 'vulhub/thinkphp:5.0.20',
    port: 18140,
    containerPort: 80,
    expectedHits: {'thinkphp-tp5022'},
    note: 'ThinkPHP 5.0.20：要验证 tp5023 的 captcha 判定不会误报到同族旧版本',
  ),
  ScanCase(
    name: 'php-cgi',
    image: 'vulhub/php:5.4.1-cgi',
    port: 18141,
    containerPort: 80,
    mount: 'php/CVE-2012-1823/www:/var/www/html:ro',
    expectedHits: {'php-cgi-2012-1823'},
    note: 'PHP-CGI：php-backdoor 不应跟着响',
  ),
  ScanCase(
    name: 'spring-8046',
    image: 'vulhub/spring-rest-data:2.6.6',
    port: 18136,
    containerPort: 8080,
    expectedHits: {'spring-8046'},
    note: '同族里只应命中 8046：22963/1273/4977 不能跟着响',
  ),
  ScanCase(
    name: 'thinkphp-5.0.23',
    image: 'vulhub/thinkphp:5.0.23',
    port: 18132,
    containerPort: 80,
    expectedHits: {'thinkphp-tp5023'},
    note: 'ThinkPHP 5.0.23：tp5022/tp2 不应被误报',
  ),
  ScanCase(
    name: 'shiro',
    image: 'vulhub/shiro:1.2.4',
    port: 18133,
    containerPort: 8080,
    expectedHits: {'shiro-2016-4437'},
    note: 'Shiro 指纹：只应命中 shiro',
  ),
  ScanCase(
    name: 'struts2-s2007',
    image: 'mxlab-struts2:latest',
    port: 18134,
    containerPort: 8080,
    expectedHits: {'struts2-s2007'},
    note: 'S2-007：其余 7 个 struts2 变体共用同族页面，必须靠唯一 marker 区分',
  ),
  ScanCase(
    name: 'php-8.1-backdoor',
    image: 'vulhub/php:8.1-backdoor',
    port: 18135,
    containerPort: 80,
    mount: 'php/8.1-backdoor/index.php:/var/www/html/index.php:ro',
    expectedHits: {'php-backdoor'},
    note: 'PHP 后门：php-cgi 不应被误报',
  ),
];

Future<void> main(List<String> args) async {
  final only = args
      .firstWhere((a) => a.startsWith('--only='), orElse: () => '')
      .split('=')
      .last;
  final jobsArg =
      args.firstWhere((a) => a.startsWith('--jobs='), orElse: () => '');
  final jobs = jobsArg.isEmpty
      ? 2
      : (int.tryParse(jobsArg.split('=').last) ?? 2).clamp(1, 6);
  final cases = only.isEmpty
      ? _cases
      : _cases.where((c) => only.split(',').contains(c.name)).toList();

  stdout.writeln('[*] ${cases.length} 个靶场，并发 $jobs');

  // 扫描很吵（每个靶场 27 个变体），并发度默认比模块矩阵低。
  final buffers = List<List<String>?>.filled(cases.length, null);
  final queue = List<int>.generate(cases.length, (i) => i).toList();

  Future<void> worker() async {
    while (queue.isNotEmpty) {
      final idx = queue.removeAt(0);
      buffers[idx] = await _runCase(cases[idx]);
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
    } else {
      failures.add(cases[i].name);
    }
  }

  stdout.writeln('\n===== 结果：$pass/${cases.length} 通过 =====');
  for (final f in failures) {
    stdout.writeln('[!] $f');
  }
  exit(failures.isEmpty ? 0 : 1);
}

Future<List<String>> _runCase(ScanCase c) async {
  final out = <String>[];
  final container = 'sm-${c.name}';
  out.add('\n=== ${c.name}  (${c.image}) ===');
  if (c.note.isNotEmpty) out.add('    ${c.note}');

  await _docker(['rm', '-f', container], allowFail: true);
  final vulhub =
      Platform.environment['VULHUB_DIR'] ?? '/Users/illya/Projects/vulhub';
  final code = await _docker([
    'run', '-d', '--rm', '--name', container,
    '-p', '${c.port}:${c.containerPort ?? c.port}',
    if (c.mount.isNotEmpty) ...['-v', '$vulhub/${c.mount}'],
    c.image,
  ], allowFail: true);
  if (code != 0) {
    out.add('[!] 容器启动失败');
    return out;
  }

  final url = 'http://127.0.0.1:${c.port}';
  if (!await _waitHttp(url, const Duration(seconds: 240))) {
    out.add('[!] 端口未就绪');
    await _docker(['rm', '-f', container], allowFail: true);
    return out;
  }

  final runner = ScanRunner(
    maxRequests: 90,
    maxDuration: const Duration(seconds: 90),
    perSecond: 10,
  );
  final hits = <String>[];
  var reason = '';
  var skipped = 0;
  await for (final e in runner.run(url: url, timeoutSeconds: 8)) {
    if (e is ScanHitEvent && e.hit.isHit) hits.add(e.hit.variant.moduleId);
    if (e is ScanFinished) {
      reason = e.reason;
      skipped = e.skipped;
    }
  }
  await _docker(['rm', '-f', container], allowFail: true);

  final got = hits.toSet();
  out.add('    命中：${hits.toList()..sort()}  结束=$reason skipped=$skipped');
  final missing = c.expectedHits.difference(got);
  final extra = got.difference(c.expectedHits);
  if (missing.isEmpty && extra.isEmpty) {
    out.add('[+] PASS');
  } else {
    if (missing.isNotEmpty) out.add('[!] 漏报：$missing');
    if (extra.isNotEmpty) out.add('[!] 误报：$extra');
    out.add('[!] FAIL');
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
      // 未就绪
    }
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  return false;
}
