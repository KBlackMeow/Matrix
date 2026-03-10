export '../models/file_entry.dart';

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

  Future<String> executeCommand(String cmd, {String workingDir = ''}) =>
      _connector.executeCommand(cmd, workingDir: workingDir);

  Future<String> getCurrentDir() => _connector.getCurrentDir();

  Future<List<FileEntry>> listDirectory(String path) =>
      _connector.listDirectory(path);

  Future<String> readFile(String path) => _connector.readFile(path);

  Future<bool> writeFile(String path, String content) =>
      _connector.writeFile(path, content);

  Future<bool> deleteFile(String path) => _connector.deleteFile(path);

  Future<Map<String, String>> getSystemInfo() => _connector.getSystemInfo();

  Future<List<({String name, bool isDir})>> listNamesForCompletion(
          String path) =>
      _connector.listNamesForCompletion(path);

  Future<String> getHomeDir() => _connector.getHomeDir();

  Future<List<String>> listEnvVarNames() => _connector.listEnvVarNames();
}
