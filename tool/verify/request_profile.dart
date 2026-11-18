// ignore_for_file: avoid_print

/// WebShell 请求画像工具：统计「打开工作区 / 每条命令 / 每次 Tab」实际发出的
/// HTTP 请求数与上下行字节数。
///
/// 用法：
///   dart tool/verify/request_profile.dart <connectorType> <url> <password> [method]
///
/// 示例：
///   dart tool/verify/request_profile.dart php_eval http://127.0.0.1:18080/shell.php mAtrix_911 POST
///   dart tool/verify/request_profile.dart jsp_runtime http://127.0.0.1:18081/mx/shell.jsp mAtrix_911 GET
///
/// 内部会启动一个计数代理，连接器指向代理，代理转发到真实目标并统计。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../lib/connectors/connector_factory.dart';
import '../../lib/core/async/ttl_cache.dart';
import '../../lib/models/webshell.dart';
import '../../lib/services/webshell_service.dart';

Future<void> main(List<String> args) async {
  if (args.length < 3) {
    print('usage: request_profile <connectorType> <url> <password> [method]');
    exitCode = 64;
    return;
  }
  final connectorType = args[0];
  final target = Uri.parse(args[1]);
  final password = args[2];
  final method = args.length > 3 ? args[3] : 'POST';
  final mode = args.length > 4 ? args[4] : 'legacy';

  final proxy = CountingProxy(target);
  await proxy.start();
  final proxyUrl = 'http://127.0.0.1:${proxy.port}${target.path}';

  final ws = Webshell(
    id: 1,
    projectId: 1,
    name: 'profile',
    url: proxyUrl,
    password: password,
    method: method,
    connectorType: connectorType,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
  final service = WebshellService(ws);
  final connector = ConnectorFactory.create(ws);
  print('connector=$connectorType  target=$target  via=$proxyUrl');

  const pathScanUnix =
      r'IFS=:; for d in $PATH; do [ -d "$d" ] || continue; for f in "$d"/*; do [ -f "$f" ] && [ -x "$f" ] && echo "${f##*/}"; done; done';

  String cwd = '/';
  final dirCache = TtlCache<String, List<({String name, bool isDir})>>(
    const Duration(seconds: 30),
  );
  final cmdCache = TtlCache<String, List<String>>(const Duration(minutes: 10));

  Future<List<String>> scanCommands() async {
    final out = await service.executeCommand(pathScanUnix);
    return out
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
  }

  final legacy = <(String, Future<void> Function())>[
    ('open: ping', () async => connector.ping()),
    (
      'open: scriptDir',
      () async {
        cwd = await service.getInitialWorkingDirectory();
        print('      ↳ cwd=$cwd');
      },
    ),
    ('open: env', () async => service.listEnvVarNames()),
    ('open: home', () async => service.getHomeDir()),
    ('open: commands', () async => service.executeCommand(pathScanUnix)),
    ('command #1', () async => service.executeCommand('echo hi')),
    ('command #2', () async => service.executeCommand('echo hi')),
    ('command #3', () async => service.executeCommand('echo hi')),
    ('tab: dir', () async => service.listNamesForCompletion(cwd)),
    ('tab: commands', () async => service.executeCommand(pathScanUnix)),
    ('tab: dir (2nd)', () async => service.listNamesForCompletion(cwd)),
  ];

  final optimized = <(String, Future<void> Function())>[
    ('open: ping', () async => connector.ping()),
    (
      'open: scriptDir',
      () async {
        cwd = await service.getInitialWorkingDirectory();
        print('      ↳ cwd=$cwd');
      },
    ),
    ('open: warmup', () async => service.warmUpEnvironment()),
    ('command #1', () async => service.executeCommand('echo hi')),
    ('command #2', () async => service.executeCommand('echo hi')),
    ('command #3', () async => service.executeCommand('echo hi')),
    (
      'tab: dir',
      () async => dirCache.fetch(
        cwd,
        () => service.listNamesForCompletion(cwd),
      ),
    ),
    (
      'tab: commands',
      () async => cmdCache.fetch(cwd, scanCommands),
    ),
    (
      'tab: dir (2nd)',
      () async => dirCache.fetch(
        cwd,
        () => service.listNamesForCompletion(cwd),
      ),
    ),
    (
      'tab: commands (2nd)',
      () async => cmdCache.fetch(cwd, scanCommands),
    ),
  ];

  final steps = mode == 'new' ? optimized : legacy;
  print('mode=$mode');
  final rows = <(String, int, int)>[];
  for (final (name, step) in steps) {
    proxy.reset();
    try {
      await step();
    } catch (e) {
      print('  !! $name failed: $e');
    }
    rows.add((name, proxy.requests, proxy.bytesUp));
    print(
      '  ${name.padRight(20)} requests=${proxy.requests}  up=${proxy.bytesUp} B',
    );
  }

  final total = rows.fold<int>(0, (s, r) => s + r.$2);
  final up = rows.fold<int>(0, (s, r) => s + r.$3);
  print('\nTOTAL requests=$total  uplink=$up B');

  await proxy.stop();
}

class CountingProxy {
  CountingProxy(this.target);

  final Uri target;
  HttpServer? _server;
  final HttpClient _client = HttpClient();
  int requests = 0;
  int bytesUp = 0;

  int get port => _server!.port;

  void reset() {
    requests = 0;
    bytesUp = 0;
  }

  Future<void> start() async {
    // 透传压缩响应：关闭自动解压，否则转发已解压 body 却保留 content-encoding，
    // 连接器一侧会因二次解压报 "Filter error, bad data"。
    _client.autoUncompress = false;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((req) async {
      try {
        final body = await _collect(req);
        requests++;
        bytesUp += req.uri.toString().length + body.length;
        final upstream = await _client.openUrl(req.method, _rewrite(req.uri));
        final skip = <String>{
          'host',
          'content-length',
          'connection',
          'keep-alive',
          'transfer-encoding',
        };
        req.headers.forEach((name, values) {
          if (skip.contains(name.toLowerCase())) return;
          for (final v in values) {
            upstream.headers.add(name, v);
          }
        });
        // 上游强制短连接，避免代理层复用陈旧 keep-alive 造成假故障。
        upstream.headers.set(HttpHeaders.connectionHeader, 'close');
        upstream.headers.set(HttpHeaders.contentLengthHeader, '${body.length}');
        upstream.add(body);
        final response = await upstream.close();
        req.response.statusCode = response.statusCode;
        final skipResp = <String>{
          'transfer-encoding',
          'content-length',
          'connection',
          'keep-alive',
        };
        response.headers.forEach((name, values) {
          if (skipResp.contains(name.toLowerCase())) return;
          for (final v in values) {
            req.response.headers.add(name, v);
          }
        });
        await req.response.addStream(response);
        await req.response.close();
      } catch (e) {
        try {
          req.response.statusCode = 502;
          req.response.write('proxy error: $e');
          await req.response.close();
        } catch (_) {}
      }
    });
  }

  Uri _rewrite(Uri incoming) => Uri(
    scheme: target.scheme,
    host: target.host,
    port: target.port,
    path: incoming.path,
    query: incoming.query,
  );

  Future<List<int>> _collect(HttpRequest req) async {
    final chunks = <int>[];
    await for (final c in req) {
      chunks.addAll(c);
    }
    return chunks;
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _client.close(force: true);
  }
}
