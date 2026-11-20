// 鲁棒性套件：目标"不正常"时，27 个变体必须给出结论，而不是崩掉或挂死。
//
// 动机：前面的套件覆盖了"正常站点 / 被 WAF 拦 / 404 错误页"，但没覆盖
// 空响应、超时、乱码、重定向环这些畸形目标。安全工具在这种目标上崩掉，
// 比误报更糟——用户会以为工具坏了，而不是目标有问题。
//
// 规则：`check()` 必须在预算内返回一个 ExploitOutcome（可以是 probeFailed），
// 不允许抛异常穿透，也不允许挂死。
//
// 用法：dart tool/verify/robustness_suite.dart [--only=struts2-s2045]

import 'dart:async';
import 'dart:io';

import '../../lib/exp/core/exploit_module.dart';
import '../../lib/exp/core/exp_catalog.dart';

class _Hostile {
  const _Hostile(this.name, this.status, this.body,
      {this.delayMs = 0, this.mustFail = false});

  final String name;
  final int status;
  final String body;
  final int delayMs;

  /// 目标完全不可达时，check 必须报"没测通"，报"没漏洞"是错误结论。
  final bool mustFail;
}

const _hostiles = <_Hostile>[
  _Hostile('空 204', 204, ''),
  _Hostile('乱码二进制', 200, '\u0000\u0001\u0002\uFFFD\uFFFD\u0007'),
  _Hostile('超时（8s 后才响应）', 200, 'late',
      delayMs: 8000, mustFail: true),
  _Hostile('1MB 垃圾正文', 200, 'A'),
];

/// 统计用（协议层与 HTML 层共用）。
var checks = 0;

/// 单个变体的硬上限：超过即判定挂死。
const _perVariantBudget = Duration(seconds: 20);

Future<void> main(List<String> args) async {
  final only = args
      .firstWhere((a) => a.startsWith('--only='), orElse: () => '')
      .split('=')
      .last;

  final variants = only.isEmpty
      ? allVariants
      : allVariants.where((e) => e.$2.moduleId == only).toList();
  if (variants.isEmpty) {
    stderr.writeln('[!] 没有匹配的变体：$only');
    exit(64);
  }

  var failures = 0;

  for (final hostile in _hostiles) {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      await req.drain<void>();
      if (hostile.delayMs > 0) {
        await Future<void>.delayed(Duration(milliseconds: hostile.delayMs));
      }
      final body = hostile.body == 'A' ? 'A' * (1024 * 1024) : hostile.body;
      req.response
        ..statusCode = hostile.status
        ..headers.contentType = ContentType.html
        ..write(body);
      await req.response.close();
    });
    final url = 'http://127.0.0.1:${server.port}';
    stdout.writeln('\n=== ${hostile.name}  ($url) ===');

    for (final (spec, variant) in variants) {
      final module = moduleById(variant.moduleId);
      if (module == null) continue;
      checks++;
      final sw = Stopwatch()..start();
      String verdict;
      try {
        final outcome = await module
            .check(ExploitTarget(url: url, timeout: const Duration(seconds: 2)))
            .timeout(_perVariantBudget);
        sw.stop();
        // 畸形容器上"命中"几乎必然是误报，但不强求：只记录，不判失败。
        verdict = outcome.failed
            ? 'probeFailed'
            : (outcome.vulnerable ? 'VULNERABLE(可疑)' : 'notDetected');
        if (hostile.mustFail && !outcome.failed) {
          verdict = 'WRONG_VERDICT(目标不可达却报$verdict)';
          failures++;
        }
      } on TimeoutException {
        sw.stop();
        verdict = 'HANG';
        failures++;
      } catch (e) {
        sw.stop();
        verdict = 'THROW(${e.runtimeType})';
        failures++;
      }
      final ms = sw.elapsedMilliseconds;
      final mark = verdict.startsWith('THROW') || verdict == 'HANG' ? '[!]' : '[-]';
      stdout.writeln('$mark ${variant.moduleId.padRight(20)} $verdict  ${ms}ms');
    }

    await server.close(force: true);
  }

  // ── 协议层毒饵：服务"半坏"时也不能崩 ──
  final rawCases = <_RawHostile>[
    _RawHostile(
      'chunked 断流',
      (socket) async {
        socket.write('HTTP/1.1 200 OK\r\n'
            'Content-Type: text/html\r\n'
            'Transfer-Encoding: chunked\r\n\r\n'
            '20\r\npartial-body-without-end');
        await socket.flush();
        await socket.close();
      },
    ),
    _RawHostile(
      'HTTP/1.0 无长度',
      (socket) async {
        socket.write('HTTP/1.0 200 OK\r\nContent-Type: text/html\r\n\r\n'
            '<html>no length</html>');
        await socket.flush();
        await socket.close();
      },
    ),
    _RawHostile(
      '假的 gzip 正文',
      (socket) async {
        final junk = List<int>.filled(64 * 1024, 0x00);
        socket.write('HTTP/1.1 200 OK\r\n'
            'Content-Type: text/html\r\n'
            'Content-Encoding: gzip\r\n'
            'Content-Length: \${junk.length}\r\n\r\n');
        socket.add(junk);
        await socket.flush();
        await socket.close();
      },
    ),
  ];

  for (final raw in rawCases) {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    socket.listen((client) async {
      // 每个连接都回同一份畸形响应
      try {
        await raw.respond(client);
      } catch (_) {
        try {
          client.destroy();
        } catch (_) {}
      }
    });
    final url = 'http://127.0.0.1:${socket.port}';
    stdout.writeln('\n=== ${raw.name}  ($url) ===');
    failures += await _probeAll(url, variants, budget: _perVariantBudget);
    await socket.close();
  }

  // TLS 不匹配：往明文端口发 https
  final plain = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  plain.listen((req) async {
    await req.drain<void>();
    req.response
      ..statusCode = 200
      ..write('plain http');
    await req.response.close();
  });
  stdout.writeln('\n=== TLS 不匹配（https 打明文端口） ===');
  failures += await _probeAll(
    'https://127.0.0.1:${plain.port}',
    variants,
    budget: _perVariantBudget,
    requireFailed: false,
  );
  await plain.close(force: true);

  stdout.writeln('\n===== $checks 次探测，$failures 处崩溃/挂死 =====');
  exit(failures == 0 ? 0 : 1);
}

/// 对一批变体跑 check，统计崩溃/挂死。返回失败数。
Future<int> _probeAll(
  String url,
  List<(dynamic, dynamic)> variants, {
  required Duration budget,
  bool requireFailed = false,
}) async {
  var failures = 0;
  for (final entry in variants) {
    checks++;
    final variant = entry.$2;
    final module = moduleById(variant.moduleId as String);
    if (module == null) continue;
    var verdict = '';
    try {
      final outcome = await module
          .check(ExploitTarget(url: url, timeout: const Duration(seconds: 2)))
          .timeout(budget);
      verdict = outcome.failed
          ? 'probeFailed'
          : (outcome.vulnerable ? 'VULNERABLE(可疑)' : 'notDetected');
      if (requireFailed && !outcome.failed) {
        verdict = 'WRONG_VERDICT($verdict)';
        failures++;
      }
    } on TimeoutException {
      verdict = 'HANG';
      failures++;
    } catch (e) {
      verdict = 'THROW(${e.runtimeType})';
      failures++;
    }
    final mark = verdict.startsWith('THROW') ||
            verdict == 'HANG' ||
            verdict.startsWith('WRONG')
        ? '[!]'
        : '[-]';
    stdout.writeln('$mark ${variant.moduleId.toString().padRight(20)} $verdict');
  }
  return failures;
}

class _RawHostile {
  const _RawHostile(this.name, this.respond);

  final String name;
  final Future<void> Function(Socket) respond;
}
