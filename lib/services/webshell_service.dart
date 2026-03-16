export '../models/file_entry.dart';

import 'dart:typed_data';

import '../connectors/connector_factory.dart';
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
}
