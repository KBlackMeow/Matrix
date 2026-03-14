import 'dart:async';
import 'dart:io';

import 'service_probe_service.dart';

/// 纯 Dart 实现的端口扫描（复刻 fscan 端口扫描功能）
/// 支持：单 IP、CIDR、IP 段、逗号分隔；端口逗号或范围
class PortScanService {
  final Duration timeout;
  final int threads;
  final bool enableServiceProbe;

  PortScanService({
    this.timeout = const Duration(seconds: 3),
    this.threads = 200,
    this.enableServiceProbe = true,
  });

  /// 解析目标，返回 IP 列表
  static Future<List<String>> parseTargets(String input) async {
    final t = input.trim();
    if (t.isEmpty) return [];

    final parts = t.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty);
    final result = <String>{};

    for (final p in parts) {
      // CIDR: 192.168.1.0/24
      final cidrMatch = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})/(\d{1,2})$').firstMatch(p);
      if (cidrMatch != null) {
        final a = int.parse(cidrMatch.group(1)!);
        final b = int.parse(cidrMatch.group(2)!);
        final c = int.parse(cidrMatch.group(3)!);
        final d = int.parse(cidrMatch.group(4)!);
        final prefix = int.parse(cidrMatch.group(5)!).clamp(0, 32);
        result.addAll(_expandCidr(a, b, c, d, prefix));
        continue;
      }

      // IP 段: 192.168.1.1-255 或 192.168.1.1-192.168.1.100
      final rangeMatch = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})-(\d{1,3}(?:\.\d{1,3}){0,3})$').firstMatch(p);
      if (rangeMatch != null) {
        final a = int.parse(rangeMatch.group(1)!);
        final b = int.parse(rangeMatch.group(2)!);
        final c = int.parse(rangeMatch.group(3)!);
        final dStart = int.parse(rangeMatch.group(4)!);
        final endPart = rangeMatch.group(5)!;
        if (endPart.contains('.')) {
          final endParts = endPart.split('.');
          if (endParts.length == 4) {
            final a2 = int.parse(endParts[0]);
            final b2 = int.parse(endParts[1]);
            final c2 = int.parse(endParts[2]);
            final d2 = int.parse(endParts[3]);
            result.addAll(_expandIpRange(a, b, c, dStart, a2, b2, c2, d2));
          }
        } else {
          final dEnd = int.parse(endPart).clamp(0, 255);
          for (var i = dStart; i <= dEnd; i++) {
            result.add('$a.$b.$c.$i');
          }
        }
        continue;
      }

      // 单 IP 或域名
      if (RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(p)) {
        result.add(p);
      } else {
        try {
          final addrs = await InternetAddress.lookup(p);
          for (final addr in addrs) {
            if (addr.type == InternetAddressType.IPv4) result.add(addr.address);
          }
        } catch (_) {}
      }
    }

    return result.toList()..sort();
  }

  static List<String> _expandCidr(int a, int b, int c, int d, int prefix) {
    if (prefix >= 32) return ['$a.$b.$c.$d'];
    final hostBits = 32 - prefix;
    if (hostBits > 20) return []; // /12 及以上过大，限制约 4k IP
    final count = 1 << hostBits;
    final base = (a << 24) | (b << 16) | (c << 8) | d;
    final mask = 0xFFFFFFFF << hostBits;
    final network = base & mask;
    final results = <String>[];
    final maxHost = count - 1;
    for (var i = 1; i < maxHost && results.length < 4096; i++) {
      final ip = network | i;
      results.add('${(ip >> 24) & 0xFF}.${(ip >> 16) & 0xFF}.${(ip >> 8) & 0xFF}.${ip & 0xFF}');
    }
    return results;
  }

  static List<String> _expandIpRange(int a1, int b1, int c1, int d1, int a2, int b2, int c2, int d2) {
    final start = (a1 << 24) | (b1 << 16) | (c1 << 8) | d1;
    final end = (a2 << 24) | (b2 << 16) | (c2 << 8) | d2;
    final results = <String>[];
    for (var ip = start; ip <= end && results.length < 4096; ip++) {
      results.add('${(ip >> 24) & 0xFF}.${(ip >> 16) & 0xFF}.${(ip >> 8) & 0xFF}.${ip & 0xFF}');
    }
    return results;
  }

  /// 解析端口，返回端口列表
  static List<int> parsePorts(String input) {
    final t = input.trim();
    if (t.isEmpty) {
      return List.generate(10000, (i) => i + 1);
    }

    final result = <int>{};
    for (final part in t.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty)) {
      final rangeMatch = RegExp(r'^(\d+)-(\d+)$').firstMatch(part);
      if (rangeMatch != null) {
        final start = int.tryParse(rangeMatch.group(1)!) ?? 0;
        final end = int.tryParse(rangeMatch.group(2)!) ?? 0;
        for (var p = start.clamp(1, 65535); p <= end.clamp(1, 65535) && result.length < 10000; p++) {
          result.add(p);
        }
      } else {
        final p = int.tryParse(part);
        if (p != null && p >= 1 && p <= 65535) result.add(p);
      }
    }
    return result.toList()..sort();
  }

  /// 检查端口是否开放
  Future<bool> _isPortOpen(String host, int port) async {
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      await socket.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 执行扫描，发现开放端口时调用 onOpen，服务探测完成后调用 onProbe
  Future<void> scan({
    required List<String> hosts,
    required List<int> ports,
    required bool Function() isCancelled,
    void Function(String)? onLog,
    void Function(String host, int port)? onOpen,
    void Function(String host, int port, dynamic probeResult)? onProbe,
  }) async {
    final semaphore = _Semaphore(threads);
    final futures = <Future<void>>[];

    for (final host in hosts) {
      if (isCancelled()) break;
      for (final port in ports) {
        if (isCancelled()) break;
        final h = host;
        final p = port;
        futures.add((() async {
          if (isCancelled()) return;
          await semaphore.acquire();
          try {
            if (isCancelled()) return;
            final open = await _isPortOpen(h, p);
            if (open && !isCancelled()) {
              onOpen?.call(h, p);
              onLog?.call('[SUCCESS] 端口开放 $h:$p');
              if (onProbe != null && enableServiceProbe) {
                final probe = ServiceProbeService(timeout: Duration(seconds: timeout.inSeconds.clamp(2, 10)));
                final r = await probe.probe(h, p);
                if (!isCancelled()) onProbe(h, p, r);
              }
            }
          } finally {
            semaphore.release();
          }
        })());
      }
    }

    await Future.wait(futures);
  }
}

class _Semaphore {
  int _count;
  final List<void Function()> _waiters = [];

  _Semaphore(this._count);

  int get active => _count;

  Future<void> acquire() async {
    if (_count > 0) {
      _count--;
      return;
    }
    final c = Completer<void>();
    _waiters.add(() => c.complete());
    await c.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0)();
    } else {
      _count++;
    }
  }
}
