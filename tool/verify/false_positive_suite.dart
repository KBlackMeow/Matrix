// 假阳性回归套件：用"什么错都不犯的服务器"去撞检测逻辑，断言不该有命中。
//
// 背景（实靶踩出来的）：裸状态码判定让一个「所有路径都回 200 的 SPA」被报成
// WebLogic XMLDecoder RCE；`{"code":200}` 的普通接口被报成 XXL-JOB 未授权执行。
// 这两个都是"目标越正常越容易误报"的类型，必须在 CI 里钉死。
//
// 用法：dart tool/verify/false_positive_suite.dart
// 退出码 0 = 全部不误报，1 = 有回归。

import 'dart:convert';
import 'dart:io';

import '../../lib/exp/core/exp_catalog.dart';
import '../../lib/exp/core/exploit_module.dart';
import '../../lib/exp/core/scan_runner.dart';

class _Case {
  const _Case(this.name, this.body, this.contentType, this.mustNotHit);

  final String name;
  final String body;
  final String contentType;

  /// 这些变体在这种目标上绝不允许命中。
  final List<String> mustNotHit;
}

const _cases = <_Case>[
  _Case(
    'SPA：所有路径都回 200 的 HTML 外壳',
    '<!doctype html><html><body>app shell</body></html>',
    'text/html',
    ['weblogic-10271', 'weblogic-14882', 'nacos-2021-29441', 'tomcat-2017-12615'],
  ),
  _Case(
    '普通 JSON 接口：{"code":200,"data":[]}',
    '{"code":200,"data":[]}',
    'application/json',
    ['xxl-job-unacc'],
  ),
];

Future<int> _blockedCase() async {
  const mustFail = [
    'struts2-s2005',
    'struts2-s2032',
    'struts2-s2045',
    'struts2-s2053',
    'struts2-s2059',
  ];
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    await req.drain<void>();
    req.response
      ..statusCode = 403
      ..headers.contentType = ContentType.html
      ..write('<h1>403 Forbidden</h1><p>Blocked by WAF</p>');
    await req.response.close();
  });
  final url = 'http://127.0.0.1:${server.port}';
  stdout.writeln('[*] 403 拦截目标：必须报"没测通"而不是"没漏洞"  ($url)');

  final targets =
      allVariants.where((e) => mustFail.contains(e.$2.moduleId)).toList();
  final runner = ScanRunner(
    maxRequests: 60,
    maxDuration: const Duration(seconds: 30),
    perSecond: 20,
  );

  final wrong = <String>[];
  await for (final event in runner.run(
    url: url,
    timeoutSeconds: 5,
    targets: targets,
  )) {
    if (event is! ScanHitEvent) continue;
    final c = event.hit.confidence;
    if (c == ScanConfidence.miss) {
      wrong.add('${event.hit.variant.moduleId} 报了 miss');
    }
  }
  await server.close(force: true);

  if (wrong.isEmpty) {
    stdout.writeln('[+] 通过（${targets.length} 个变体都正确报"没测通"）');
    return 0;
  }
  for (final w in wrong) {
    stdout.writeln('[!] 假阴性 $w');
  }
  return wrong.length;
}

/// 目标对一切返回 404 HTML 时，`exec` 不允许把错误页当命令输出。
Future<int> _errorPageCase() async {
  const modules = ['tomcat-2017-12615', 'httpd-2021-41773'];
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    await req.drain<void>();
    req.response
      ..statusCode = 404
      ..headers.contentType = ContentType.html
      ..write('<!DOCTYPE HTML><html><head><title>404 Not Found</title>'
          '</head><body><h1>Not Found</h1></body></html>');
    await req.response.close();
  });
  final url = 'http://127.0.0.1:${server.port}';
  stdout.writeln('[*] 404 错误页不能被当成命令输出  ($url)');

  var wrong = 0;
  for (final id in modules) {
    final module = moduleById(id);
    if (module == null) continue;
    try {
      final out = await module.exec(
        ExploitTarget(url: url, timeout: const Duration(seconds: 5)),
        'id',
      );
      if (out != null && out.toLowerCase().contains('<!doctype')) {
        stdout.writeln('[!] 假输出 $id: exec 返回了 HTML 错误页');
        wrong++;
      }
    } catch (_) {
      // 抛错是正确行为
    }
  }
  await server.close(force: true);
  if (wrong == 0) {
    stdout.writeln('[+] 通过（错误页没有被当成命令输出）');
  }
  return wrong;
}

/// 服务器把请求行、所有头、请求体原样回显。
/// 任何"marker 字面量写在请求里"的检测都会在这里误报——这正是
/// PHP 后门（UA 里的标记）和 Struts2（URL 里的 marker）踩过的坑。
Future<int> _echoReflectionCase() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    final bodyBytes = await req.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
    final buf = StringBuffer()
      ..writeln('${req.method} ${req.uri}')
      ..writeln('content-type: ${req.headers.contentType}');
    req.headers.forEach((name, values) {
      buf.writeln('$name: ${values.join(',')}');
    });
    buf.writeln(String.fromCharCodes(bodyBytes));
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.html
      ..write(buf.toString());
    await req.response.close();
  });
  final url = 'http://127.0.0.1:${server.port}';
  stdout.writeln('[*] 回显一切的服务器：payload 字面量不许算命中  ($url)');

  final runner = ScanRunner(
    maxRequests: 200,
    maxDuration: const Duration(seconds: 120),
    perSecond: 30,
  );
  final hits = <String>[];
  await for (final e in runner.run(url: url, timeoutSeconds: 3)) {
    if (e is ScanHitEvent && e.hit.isHit) {
      hits.add('${e.hit.variant.moduleId}: ${e.hit.outcome.detail}');
    }
  }
  await server.close(force: true);

  if (hits.isEmpty) {
    stdout.writeln('[+] 通过（27 个变体全部未把回显当命中）');
    return 0;
  }
  for (final h in hits) {
    stdout.writeln('[!] 回显误报 $h');
  }
  return hits.length;
}

Future<void> main() async {
  var failures = 0;
  for (final c in _cases) {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      await req.drain<void>();
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.parse(c.contentType)
        ..write(c.body);
      await req.response.close();
    });
    final url = 'http://127.0.0.1:${server.port}';
    stdout.writeln('[*] ${c.name}  ($url)');

    final targets = allVariants
        .where((e) => c.mustNotHit.contains(e.$2.moduleId))
        .toList();
    final runner = ScanRunner(
      maxRequests: 60,
      maxDuration: const Duration(seconds: 30),
      perSecond: 20,
    );

    final hits = <String>[];
    await for (final event in runner.run(
      url: url,
      timeoutSeconds: 5,
      targets: targets,
    )) {
      if (event is ScanHitEvent && event.hit.isHit) {
        hits.add(event.hit.variant.moduleId);
        stdout.writeln(
          '[!] 误报 ${event.hit.variant.moduleId}: ${event.hit.outcome.detail}',
        );
      }
    }
    await server.close(force: true);

    if (hits.isEmpty) {
      stdout.writeln('[+] 通过（${targets.length} 个变体全部未误报）');
    } else {
      failures += hits.length;
    }
  }

  // ── 被 WAF 拦截时必须报"没测通"，不能报"没有漏洞" ──
  final blocked = await _blockedCase();
  failures += blocked;

  // ── 404 错误页不能被当成命令输出 ──
  final errorPage = await _errorPageCase();
  failures += errorPage;

  // ── 回显一切的服务器：payload 里的字面量不能被当成"命中" ──
  final echo = await _echoReflectionCase();
  failures += echo;

  if (failures == 0) {
    stdout.writeln('[+] 假阳性套件通过');
    exit(0);
  }
  stdout.writeln('[!] 假阳性套件失败：$failures 处误报');
  exit(1);
}
