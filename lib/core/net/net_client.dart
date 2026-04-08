import 'dart:async';
import 'dart:io';

class SocketConnection {
  SocketConnection(this._socket, {required this.readTimeout});

  final Socket _socket;
  final Duration readTimeout;
  Socket get rawSocket => _socket;

  Future<void> write(List<int> bytes) async {
    _socket.add(bytes);
    await _socket.flush();
  }

  Future<List<int>> read({int maxBytes = 4096}) async {
    final completer = Completer<List<int>>();
    final buffer = <int>[];

    late StreamSubscription<List<int>> sub;
    sub = _socket.listen(
      (chunk) {
        buffer.addAll(chunk);
        if (buffer.length >= maxBytes) {
          sub.cancel();
          completer.complete(buffer.sublist(0, maxBytes));
        }
      },
      onError: (e, _) {
        if (!completer.isCompleted) completer.completeError(e);
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete(buffer);
      },
      cancelOnError: true,
    );

    return completer.future.timeout(
      readTimeout,
      onTimeout: () {
        sub.cancel();
        return buffer;
      },
    );
  }

  Future<void> close() => _socket.close();
}

class NetClient {
  NetClient({
    this.connectTimeout = const Duration(seconds: 5),
    this.readTimeout = const Duration(seconds: 5),
    this.allowBadCertificate = false,
  });

  final Duration connectTimeout;
  final Duration readTimeout;
  final bool allowBadCertificate;

  Future<SocketConnection?> connectTcp(String host, int port) async {
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: connectTimeout,
      );
      socket.setOption(SocketOption.tcpNoDelay, true);
      return SocketConnection(socket, readTimeout: readTimeout);
    } catch (_) {
      return null;
    }
  }

  Future<SocketConnection?> connectTls(String host, int port) async {
    try {
      final socket = await SecureSocket.connect(
        host,
        port,
        timeout: connectTimeout,
        onBadCertificate: allowBadCertificate ? (_) => true : null,
      );
      socket.setOption(SocketOption.tcpNoDelay, true);
      return SocketConnection(socket, readTimeout: readTimeout);
    } catch (_) {
      return null;
    }
  }
}

