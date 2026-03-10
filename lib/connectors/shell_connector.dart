import '../models/webshell.dart';
import '../models/file_entry.dart';

/// 连接器能力枚举
enum ConnectorCapability {
  codeExec,  // 可执行任意代码（eval 类）
  shellExec, // 可执行 shell/系统命令
  fileRead,  // 可读取远端文件
  fileWrite, // 可写入/删除远端文件
  probeOnly, // 只读探测，无执行能力
}

/// 所有 Webshell 连接器的抽象基类
abstract class ShellConnector {
  final Webshell webshell;
  String currentDir = '/';

  ShellConnector(this.webshell);

  Set<ConnectorCapability> get capabilities;

  bool get supportsCodeExec  => capabilities.contains(ConnectorCapability.codeExec);
  bool get supportsShellExec => capabilities.contains(ConnectorCapability.shellExec);
  bool get supportsFileRead  => capabilities.contains(ConnectorCapability.fileRead);
  bool get supportsFileWrite => capabilities.contains(ConnectorCapability.fileWrite);
  bool get isProbeOnly       => capabilities.contains(ConnectorCapability.probeOnly);

  Future<bool> ping();
  Future<String> executeCommand(String cmd, {String workingDir = ''});
  Future<String> getCurrentDir();
  Future<List<FileEntry>> listDirectory(String path);
  Future<String> readFile(String path);
  Future<bool> writeFile(String path, String content);
  Future<bool> deleteFile(String path);
  Future<Map<String, String>> getSystemInfo();
  Future<List<({String name, bool isDir})>> listNamesForCompletion(String path);
  Future<String> getHomeDir();
  Future<List<String>> listEnvVarNames();
}
