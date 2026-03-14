import 'dart:io';

/// ICMP 主机存活探测（复刻 fscan）
/// 使用 ping 命令实现跨平台
class IcmpService {
  final Duration timeout;

  IcmpService({this.timeout = const Duration(seconds: 2)});

  /// 探测单个 IP 是否存活
  Future<bool> ping(String host) async {
    try {
      final result = await Process.run(
        Platform.isWindows ? 'ping' : 'ping',
        Platform.isWindows
            ? ['-n', '1', '-w', '${timeout.inMilliseconds}', host]
            : ['-c', '1', '-W', '${timeout.inSeconds.clamp(1, 10)}', host],
        runInShell: true,
      ).timeout(timeout + const Duration(seconds: 1));
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// 批量探测，返回存活 IP 列表
  Future<List<String>> filterAlive(
    List<String> hosts, {
    required bool Function() isCancelled,
    void Function(int done, int total)? onProgress,
  }) async {
    final alive = <String>[];
    var done = 0;
    for (final h in hosts) {
      if (isCancelled()) break;
      if (await ping(h)) alive.add(h);
      done++;
      onProgress?.call(done, hosts.length);
    }
    return alive;
  }
}
