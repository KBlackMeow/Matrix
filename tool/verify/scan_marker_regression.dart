// 运行时回归：唯一 marker 是否真的消除了"一次回显 → 8 条命中"。
//
// 做法：起一个本地 HTTP 服务，对**所有**请求都返回 `54289`（即 s2005 的 marker），
// 然后只对这 8 个 Struts2 变体跑一遍 ScanRunner。
//
// 期望：恰好 1 条命中（s2005）。如果哪天 marker 又被改回共用，这里会变成 8 条。
//
// 用法：dart tool/verify/scan_marker_regression.dart
// 退出码 0 = 符合预期，1 = 回归。

import 'dart:io';

import '../../lib/exp/core/exp_catalog.dart';
import '../../lib/exp/core/scan_runner.dart';

Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    // 吞掉请求体，回一个恒定的 marker。
    await req.drain<void>();
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.html
      ..write('54289');
    await req.response.close();
  });

  final url = 'http://127.0.0.1:${server.port}';
  stdout.writeln('[*] mock target: $url（所有请求都回 54289）');

  final struts2 = allVariants
      .where((entry) => entry.$1.id == 'struts2')
      .toList(growable: false);

  final runner = ScanRunner(
    maxRequests: 90,
    maxDuration: const Duration(seconds: 60),
    perSecond: 20, // 本地回环，不需要限速
  );

  final hits = <ScanHit>[];
  int? skipped;
  String? reason;

  await for (final event in runner.run(
    url: url,
    timeoutSeconds: 5,
    targets: struts2,
  )) {
    if (event is ScanHitEvent) {
      final h = event.hit;
      stdout.writeln(
        '    ${h.variant.moduleId.padRight(16)} ${h.confidence.name}'
        '${h.outcome.detail.isEmpty ? '' : ' — ${h.outcome.detail}'}',
      );
      if (h.isHit) hits.add(h);
    } else if (event is ScanFinished) {
      skipped = event.skipped;
      reason = event.reason;
    }
  }

  await server.close(force: true);

  final ids = hits.map((h) => h.variant.moduleId).toList()..sort();
  stdout.writeln('[*] 命中 ${hits.length} 条：$ids · 跳过 $skipped · 原因 $reason');

  if (ids.length == 1 && ids.single == 'struts2-s2005') {
    stdout.writeln('[+] 通过：只有 s2005 认领了这个回显，marker 未串台');
    exit(0);
  }
  if (ids.length > 1) {
    stdout.writeln('[!] 失败：${ids.length} 个变体同时命中 → marker 又串台了');
  } else {
    stdout.writeln('[!] 失败：期望命中 s2005，实际 $ids');
  }
  exit(1);
}
