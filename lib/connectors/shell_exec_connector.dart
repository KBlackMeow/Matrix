import 'dart:convert';
import 'dart:typed_data';

import '../models/file_entry.dart';
import '../utils/encoding_utils.dart';
import 'shell_connector.dart';

/// 命令执行型连接器的抽象基类（passthru / runtime / wscript）
///
/// 子类只需实现 [sendRawCommand]，所有文件操作和系统信息
/// 均通过 shell 命令模拟实现。
abstract class ShellExecConnector extends ShellConnector {
  ShellExecConnector(super.webshell);

  /// 发送一条 shell 命令并返回裸文本输出（子类负责去除协议包装）
  Future<String> sendRawCommand(String cmd);

  // ── 工具方法 ───────────────────────────────────────────────────────────────

  /// POSIX 单引号转义
  static String sq(String s) => "'${s.replaceAll("'", "'\\''")}'";

  /// 解析 `ls -la` 输出为 FileEntry 列表
  static List<FileEntry> parseLsLa(String raw) {
    final entries = <FileEntry>[];
    for (final line in raw.split('\n')) {
      final l = line.trim();
      if (l.isEmpty || l.startsWith('total')) continue;
      final parts = l.split(RegExp(r'\s+'));
      if (parts.length < 9) continue;
      final perms = parts[0];
      if (!perms.startsWith('-') &&
          !perms.startsWith('d') &&
          !perms.startsWith('l')) {
        continue;
      }
      final size = int.tryParse(parts[4]) ?? 0;
      final dateStr = '${parts[5]} ${parts[6]} ${parts[7]}';
      final name = parts.sublist(8).join(' ');
      if (name == '.') continue;
      final isDir = perms.startsWith('d') || perms.startsWith('l');
      entries.add(
        FileEntry(
          name: name,
          isDirectory: isDir,
          size: size,
          permissions: perms.length > 1 ? perms.substring(1) : perms,
          modified: dateStr,
        ),
      );
    }
    entries.sort((a, b) {
      if (a.name == '..') return -1;
      if (b.name == '..') return 1;
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  /// 解析以 `###KEY###` 分隔的批量命令输出
  static Map<String, String> parseSepOutput(
    String raw,
    String sep,
    Map<String, String> keyMap,
  ) {
    final result = <String, String>{};
    String? currentKey;
    final buffer = StringBuffer();

    for (final line in raw.split('\n')) {
      if (line.contains(sep)) {
        if (currentKey != null && buffer.isNotEmpty) {
          final display = keyMap[currentKey];
          if (display != null) result[display] = buffer.toString().trim();
        }
        buffer.clear();
        final match = RegExp('$sep(\\w+)$sep').firstMatch(line);
        currentKey = match?.group(1);
      } else if (currentKey != null) {
        if (buffer.isNotEmpty) buffer.write('\n');
        buffer.write(line);
      }
    }
    if (currentKey != null && buffer.isNotEmpty) {
      final display = keyMap[currentKey];
      if (display != null) result[display] = buffer.toString().trim();
    }
    return result;
  }

  // ── 默认实现（Linux shell 命令） ──────────────────────────────────────────

  @override
  Future<bool> ping() async {
    try {
      final r = await sendRawCommand(
        'echo MATRIX_PING',
      ).timeout(const Duration(seconds: 8));
      return r.contains('MATRIX_PING');
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String> executeCommand(String cmd, {String workingDir = ''}) async {
    final cd = (workingDir.isNotEmpty && workingDir.startsWith('/'))
        ? 'cd ${sq(workingDir)} && '
        : '';
    return sendRawCommand('$cd$cmd 2>&1');
  }

  @override
  Future<String> getCurrentDir() async {
    final r = (await sendRawCommand('pwd')).trim();
    if (r.isNotEmpty && !r.startsWith('[')) currentDir = r;
    return currentDir;
  }

  @override
  Future<List<FileEntry>> listDirectory(String path) async {
    final raw = await sendRawCommand('ls -la ${sq(path)} 2>&1');
    return parseLsLa(raw);
  }

  @override
  Future<String> readFile(String path) async {
    // base64 传输，避免特殊字符/二进制问题
    final raw = await sendRawCommand(
      'cat ${sq(path)} 2>/dev/null | base64 -w0 2>/dev/null || cat ${sq(path)} 2>/dev/null | base64',
    );
    if (raw.isEmpty || raw.startsWith('[')) return '[文件不存在或无权读取]';
    try {
      return decodeWithFallback(
        base64.decode(raw.trim().replaceAll('\n', '').replaceAll('\r', '')),
      );
    } catch (_) {
      return '[读取失败：编码错误]';
    }
  }

  @override
  Future<bool> writeFile(String path, String content) async {
    final b64 = base64.encode(utf8.encode(content));
    final r = await sendRawCommand(
      'echo ${sq(b64)} | base64 -d > ${sq(path)} && echo 1 || echo 0',
    );
    return r.trim() == '1';
  }

  @override
  Future<Uint8List> readFileBinary(String path) async {
    final raw = await sendRawCommand(
      'cat ${sq(path)} 2>/dev/null | base64 -w0 2>/dev/null || cat ${sq(path)} 2>/dev/null | base64',
    );
    if (raw.isEmpty || raw.startsWith('[')) throw Exception('无法读取文件: $raw');
    final b64 = raw.trim().replaceAll(RegExp(r'\s'), '');
    return base64.decode(b64);
  }

  @override
  Future<bool> writeFileBinary(String path, Uint8List bytes) async {
    // 保留单次写入实现，供不关心进度的场景使用
    final b64 = base64.encode(bytes);
    final r = await sendRawCommand(
      'echo ${sq(b64)} | base64 -d > ${sq(path)} && echo 1 || echo 0',
    );
    return r.trim() == '1';
  }

  static const _kChunkSize = 128 * 1024; // 128 KB per chunk

  @override
  Future<bool> writeFileBinaryWithProgress(
    String path,
    Uint8List bytes,
    void Function(int sent, int total) onProgress,
  ) async {
    final total = bytes.length;
    onProgress(0, total);

    // 通过多次 base64 分块写入，避免超长命令，同时便于进度反馈。
    int offset = 0;
    bool first = true;
    while (offset < total) {
      final end = (offset + _kChunkSize).clamp(0, total);
      final chunk = bytes.sublist(offset, end);
      final b64 = base64.encode(chunk);
      final redirect = first ? '>' : '>>';
      final r = await sendRawCommand(
        'echo ${sq(b64)} | base64 -d $redirect ${sq(path)} && echo 1 || echo 0',
      );
      if (r.trim() != '1') return false;
      offset = end;
      first = false;
      onProgress(offset, total);
    }
    return true;
  }

  @override
  Future<bool> deleteFile(String path) async {
    final r = await sendRawCommand('rm -f ${sq(path)} && echo 1 || echo 0');
    return r.trim() == '1';
  }

  @override
  Future<Map<String, String>> getSystemInfo() async {
    const sep = '###MATRIX_SEP###';
    final cmd = [
      "echo '${sep}OS${sep}'",
      'uname -a 2>/dev/null',
      "echo '${sep}USER${sep}'",
      'whoami 2>/dev/null',
      "echo '${sep}PWD${sep}'",
      'pwd 2>/dev/null',
      "echo '${sep}HOST${sep}'",
      'hostname 2>/dev/null',
      "echo '${sep}ID${sep}'",
      'id 2>/dev/null',
      "echo '${sep}KERNEL${sep}'",
      'uname -r 2>/dev/null',
    ].join('; ');
    const keyMap = {
      'OS': 'OS',
      'USER': '运行用户',
      'PWD': '当前目录',
      'HOST': '主机名',
      'ID': '用户ID',
      'KERNEL': '内核版本',
    };
    return parseSepOutput(await sendRawCommand(cmd), sep, keyMap);
  }

  @override
  Future<List<({String name, bool isDir})>> listNamesForCompletion(
    String path,
  ) async {
    final raw = await sendRawCommand('ls -1aF ${sq(path)} 2>/dev/null');
    if (raw.isEmpty || raw.startsWith('[')) return [];
    const classifiers = {42, 64, 124, 61, 62}; // * @ | = >
    final result = <({String name, bool isDir})>[];
    for (final line in raw.split('\n')) {
      final rawName = line.trim();
      if (rawName.isEmpty) continue;
      final last = rawName.codeUnitAt(rawName.length - 1);
      final isDir = last == 47; // '/'
      String name = (isDir || classifiers.contains(last))
          ? rawName.substring(0, rawName.length - 1)
          : rawName;
      if (name.isEmpty || name == '.') continue;
      result.add((name: name, isDir: isDir));
    }
    result.sort((a, b) => a.name.compareTo(b.name));
    return result;
  }

  @override
  Future<String> getHomeDir() async =>
      (await sendRawCommand(r'echo $HOME')).trim();

  @override
  Future<List<String>> listEnvVarNames() async {
    final raw = await sendRawCommand("env 2>/dev/null | cut -d= -f1");
    if (raw.isEmpty || raw.startsWith('[')) return [];
    return raw.trim().split('\n').where((s) => s.isNotEmpty).toList()..sort();
  }
}
