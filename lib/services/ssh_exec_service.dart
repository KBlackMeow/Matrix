import 'dart:io';

/// SSH 命令执行（复刻 fscan -c 参数）
class SshExecService {
  /// 执行 SSH 命令（需系统已安装 sshpass + ssh）
  /// 或使用 ssh 密钥认证
  Future<String?> execWithPassword(
    String host,
    int port,
    String user,
    String password,
    String command,
  ) async {
    try {
      final result = await Process.run(
        'sshpass',
        ['-p', password, 'ssh', '-o', 'StrictHostKeyChecking=no', '-o', 'ConnectTimeout=5', '-p', '$port', '$user@$host', command],
        runInShell: true,
      ).timeout(const Duration(seconds: 10));
      return result.stdout.toString();
    } catch (_) {
      return null;
    }
  }

  /// 使用密钥执行（无需 sshpass）
  Future<String?> execWithKey(
    String host,
    int port,
    String user,
    String keyPath,
    String command,
  ) async {
    try {
      final result = await Process.run(
        'ssh',
        ['-i', keyPath, '-o', 'StrictHostKeyChecking=no', '-o', 'ConnectTimeout=5', '-p', '$port', '$user@$host', command],
        runInShell: true,
      ).timeout(const Duration(seconds: 10));
      return result.stdout.toString();
    } catch (_) {
      return null;
    }
  }
}
