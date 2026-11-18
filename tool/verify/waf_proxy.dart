// ignore_for_file: avoid_print

/// 测试用 WAF 代理：把请求转发到靶场，命中规则则返回 403。
///
/// 目的不是做一个真 WAF，而是给 exp 模块制造"有防御"的环境，暴露
/// "只会打默认靶场"的短板。
///
/// 用法：
///   dart tool/verify/waf_proxy.dart <upstreamBase> <listenPort> [--rules=a,b]
///
/// 默认规则集（大小写不敏感，检查 URL + 所有 header + body）：
///   %{  ${  ognl  runtime  processbuilder  getruntime
///   _method=__construct  filter[]=phpinfo  eval(  base64_decode
///   system(  assert(  spring.cloud.function.routing-expression  user-agentt
/// 另外拦截 PUT 方法（模拟"禁用 PUT"）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// strict：连特征语法一起拦（模拟"全拦"的 WAF）。
const strictSignatures = <String>[
  '%{',
  r'${',
  'ognl',
  'runtime',
  'processbuilder',
  'getruntime',
  '_method=__construct',
  'filter[]=phpinfo',
  'eval(',
  'base64_decode',
  'system(',
  'assert(',
  'spring.cloud.function.routing-expression',
  'user-agentt',
];

/// keywords：只拦危险函数/类名（更接近商业 WAF 的通用规则集）。
const keywordSignatures = <String>[
  'getruntime',
  'processbuilder',
  'base64_decode',
  'system(',
  'shell_exec',
  'eval(',
  'assert(',
];

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    print('usage: waf_proxy <upstreamBase> <listenPort> [--rules=a,b]');
    exitCode = 64;
    return;
  }
  final upstream = Uri.parse(args[0]);
  final port = int.parse(args[1]);
  var signatures = strictSignatures;
  final presetArg = args.firstWhere(
    (a) => a.startsWith('--preset='),
    orElse: () => '',
  );
  if (presetArg.endsWith('keywords')) {
    signatures = keywordSignatures;
  }
  final rulesArg = args.firstWhere(
    (a) => a.startsWith('--rules='),
    orElse: () => '',
  );
  if (rulesArg.isNotEmpty) {
    signatures = rulesArg
        .substring('--rules='.length)
        .split(',')
        .where((s) => s.isNotEmpty)
        .toList();
  }

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  final client = HttpClient()..autoUncompress = false;
  print('WAF on :$port -> $upstream  (${signatures.length} rules)');

  await for (final req in server) {
    try {
      final body = await _collect(req);
      final headerText = StringBuffer();
      req.headers.forEach((name, values) {
        headerText.write('$name:${values.join(',')}\n');
      });
      // 真实 WAF 会先解码再匹配；这里额外做一次解码，覆盖 %25%7b 这类编码。
      final rawBody = utf8.decode(body, allowMalformed: true);
      String decoded = rawBody;
      String decodedQuery = req.uri.query;
      try {
        decoded = Uri.decodeComponent(rawBody.replaceAll('+', ' '));
        decodedQuery = Uri.decodeComponent(req.uri.query);
      } catch (_) {}
      final haystack = <String>[
        req.method,
        req.uri.toString(),
        headerText.toString(),
        rawBody,
        decoded,
        decodedQuery,
      ].join('\n').toLowerCase();

      final hit = _match(haystack, signatures);
      if (hit != null) {
        req.response.statusCode = 403;
        req.response.headers.contentType = ContentType.html;
        req.response.write('<!doctype html><h1>403 Forbidden</h1>'
            '<p>Blocked by WAF (rule: ${_escape(hit)})</p>');
        await req.response.close();
        print('BLOCK ${req.method} ${req.uri.path} rule=${hit}');
        continue;
      }

      await _forward(client, req, upstream, body);
    } catch (e) {
      try {
        req.response.statusCode = 502;
        req.response.write('proxy error: $e');
        await req.response.close();
      } catch (_) {}
    }
  }
}

String? _match(String haystack, List<String> signatures) {
  for (final s in signatures) {
    if (haystack.contains(s.toLowerCase())) return s;
  }
  return null;
}

Future<void> _forward(
  HttpClient client,
  HttpRequest req,
  Uri upstream,
  List<int> body,
) async {
  final target = Uri(
    scheme: upstream.scheme,
    host: upstream.host,
    port: upstream.port,
    path: req.uri.path,
    query: req.uri.query,
  );
  final out = await client.openUrl(req.method, target);
  req.headers.forEach((name, values) {
    final lower = name.toLowerCase();
    if (lower == 'host' ||
        lower == 'content-length' ||
        lower == 'connection' ||
        lower == 'transfer-encoding') {
      return;
    }
    for (final v in values) {
      out.headers.add(name, v);
    }
  });
  out.headers.set(HttpHeaders.connectionHeader, 'close');
  out.headers.set(HttpHeaders.contentLengthHeader, '${body.length}');
  out.add(body);

  final res = await out.close();
  req.response.statusCode = res.statusCode;
  res.headers.forEach((name, values) {
    final lower = name.toLowerCase();
    if (lower == 'transfer-encoding' ||
        lower == 'content-length' ||
        lower == 'connection') {
      return;
    }
    for (final v in values) {
      req.response.headers.add(name, v);
    }
  });
  await req.response.addStream(res);
  await req.response.close();
}

Future<List<int>> _collect(HttpRequest req) async {
  final chunks = <int>[];
  await for (final c in req) {
    chunks.addAll(c);
  }
  return chunks;
}

String _escape(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
