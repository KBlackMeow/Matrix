import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

typedef HostIdResolver = Future<String> Function(String shellUrl);

/// Serializes MCP write operations targeting the same remote IP and path.
///
/// The coordinator is owned by the MCP server, rather than by one connection's
/// SessionPool, so concurrent HTTP clients share the same locks.
///
/// 该协调器同时被 UI（文件管理器上传/写入/删除）与 MCP 工具复用：两边各持一把
/// 锁时，同一目标文件的并发写仍会互相覆盖，因此统一走 [shared]。
class RemoteWriteLockCoordinator {
  RemoteWriteLockCoordinator({HostIdResolver? resolveHostId})
    : _resolveHostId = resolveHostId ?? _lookupHostId;

  /// 进程内共享实例：UI 与 MCP 共用同一把锁表。
  static final RemoteWriteLockCoordinator shared =
      RemoteWriteLockCoordinator();

  final HostIdResolver _resolveHostId;
  final Map<String, Future<void>> _tails = {};
  final Map<String, Future<String>> _hostIds = {};

  Future<T> synchronize<T>({
    required String shellUrl,
    required String remotePath,
    required Future<T> Function() operation,
  }) async {
    final hostId = await _hostIdFor(shellUrl);
    final key = '$hostId\u0000${_normalizeRemotePath(remotePath)}';
    final previous = _tails[key];
    final release = Completer<void>();
    final tail = (previous ?? Future<void>.value()).then((_) => release.future);
    _tails[key] = tail;

    await previous;
    try {
      return await operation();
    } finally {
      release.complete();
      if (identical(_tails[key], tail)) _tails.remove(key);
    }
  }

  Future<String> _hostIdFor(String shellUrl) {
    return _hostIds.putIfAbsent(shellUrl, () => _resolveHostId(shellUrl));
  }

  static Future<String> _lookupHostId(String shellUrl) async {
    final host = Uri.tryParse(shellUrl)?.host ?? '';
    if (host.isEmpty) return shellUrl.toLowerCase();
    try {
      final addresses = await InternetAddress.lookup(host);
      if (addresses.isEmpty) return host.toLowerCase();
      addresses.sort((a, b) => a.address.compareTo(b.address));
      return addresses.first.address;
    } catch (_) {
      // DNS 解析失败不能阻断写操作：退化为按主机名串行。
      return host.toLowerCase();
    }
  }

  static String _normalizeRemotePath(String path) =>
      p.posix.normalize(path.replaceAll('\\', '/'));
}
