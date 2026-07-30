import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

typedef HostIdResolver = Future<String> Function(String shellUrl);

/// Serializes MCP write operations targeting the same remote IP and path.
///
/// The coordinator is owned by the MCP server, rather than by one connection's
/// SessionPool, so concurrent HTTP clients share the same locks.
class RemoteWriteLockCoordinator {
  RemoteWriteLockCoordinator({HostIdResolver? resolveHostId})
    : _resolveHostId = resolveHostId ?? _lookupHostId;

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
    final host = Uri.parse(shellUrl).host;
    if (host.isEmpty) throw FormatException('WebShell URL 缺少主机名: $shellUrl');
    final addresses = await InternetAddress.lookup(host);
    if (addresses.isEmpty) return host.toLowerCase();
    addresses.sort((a, b) => a.address.compareTo(b.address));
    return addresses.first.address;
  }

  static String _normalizeRemotePath(String path) =>
      p.posix.normalize(path.replaceAll('\\', '/'));
}
