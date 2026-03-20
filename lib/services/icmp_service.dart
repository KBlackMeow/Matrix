import 'dart:io';

/// ICMP 主机存活探测（复刻 fscan）
/// 三层策略：ping 命令 → TCP 连接备选（对应 fscan raw-socket → dial → ping 降级）
/// 防火墙屏蔽 ICMP 时自动回落至 TCP，避免漏报存活主机
class IcmpService {
  final Duration timeout;

  /// TCP fallback 尝试的端口（按常见开放率排序）
  static const _tcpFallbackPorts = [80, 443, 22, 445, 8080, 3389, 21, 8443];

  IcmpService({this.timeout = const Duration(seconds: 2)});

  /// 探测单个 IP：ping 优先，失败后尝试 TCP 连接
  Future<bool> ping(String host) async {
    if (await _pingCommand(host)) return true;
    return _tcpFallback(host);
  }

  Future<bool> _pingCommand(String host) async {
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

  /// TCP 连接备选：尝试常见端口，任意一个成功则认为主机存活
  /// 对应 fscan 的 RunIcmp2（dial 模式），处理防火墙屏蔽 ICMP 的场景
  Future<bool> _tcpFallback(String host) async {
    const tcpTimeout = Duration(seconds: 1);
    for (final port in _tcpFallbackPorts) {
      Socket? s;
      try {
        s = await Socket.connect(host, port, timeout: tcpTimeout);
        return true;
      } catch (_) {
      } finally {
        try { s?.destroy(); } catch (_) {}
      }
    }
    return false;
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
