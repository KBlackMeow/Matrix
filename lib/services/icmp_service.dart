import 'dart:io';

/// ICMP 主机存活探测（复刻 fscan）
/// 并发 ping，默认 100 并发（fscan 默认 1000）
class IcmpService {
  final Duration timeout;

  IcmpService({this.timeout = const Duration(seconds: 2)});

  /// 探测单个 IP 是否存活
  Future<bool> ping(String host) async {
    try {
      final result = await Process.run(
        'ping',
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

  /// 批量并发探测，返回存活 IP 列表
  /// [concurrency] 同时并发数（默认 100），对应 fscan -Pn 模式
  Future<List<String>> filterAlive(
    List<String> hosts, {
    required bool Function() isCancelled,
    void Function(int done, int total)? onProgress,
    int concurrency = 100,
  }) async {
    final alive = <String>[];
    var done = 0;

    for (var i = 0; i < hosts.length && !isCancelled(); i += concurrency) {
      final end = (i + concurrency).clamp(0, hosts.length);
      final batch = hosts.sublist(i, end);

      await Future.wait(batch.map((h) async {
        if (isCancelled()) return;
        if (await ping(h)) alive.add(h);
        done++;
        onProgress?.call(done, hosts.length);
      }));

      if (isCancelled()) break;
    }

    return alive;
  }
}
