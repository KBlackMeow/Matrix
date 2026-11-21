import 'package:matrix/services/suo5_client_service.dart';
import 'package:matrix/services/suo6_client_service.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// SUO5 / SUO6 真实回环测试（默认跳过）。
///
/// ```bash
/// MATRIX_SUO5_URL=http://127.0.0.1:18098/suo5.php \
/// MATRIX_SUO5_TARGET=127.0.0.1:80 \
/// MATRIX_SUO6_URL=http://127.0.0.1:18097/suo6.jsp \
/// MATRIX_SUO6_TARGET=127.0.0.1:8080 \
/// flutter test test/services/tunnel_integration_test.dart
/// ```
String? _env(String key) {
  final v = Platform.environment[key];
  return v == null || v.trim().isEmpty ? null : v.trim();
}

Future<int> _freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

Future<String> _socksHttpGet({
  required int socksPort,
  required String host,
  required int targetPort,
  String path = '/',
}) async {
  final socket = await Socket.connect(
    '127.0.0.1',
    socksPort,
    timeout: const Duration(seconds: 5),
  );
  final iterator = StreamIterator<List<int>>(socket);
  try {
    socket.add([5, 1, 0]);
    if (!await iterator.moveNext().timeout(const Duration(seconds: 5))) {
      throw StateError('SOCKS greeting EOF');
    }
    final greet = iterator.current;
    if (greet.length < 2 || greet[0] != 5 || greet[1] != 0) {
      throw StateError('SOCKS greeting failed: $greet');
    }

    final octets = host.split('.').map(int.parse).toList();
    socket.add([5, 1, 0, 1, ...octets, targetPort >> 8, targetPort & 0xff]);
    if (!await iterator.moveNext().timeout(const Duration(seconds: 15))) {
      throw StateError('SOCKS connect EOF');
    }
    final reply = iterator.current;
    if (reply.length < 2 || reply[0] != 5 || reply[1] != 0) {
      throw StateError('SOCKS connect failed: $reply');
    }

    await Future<void>.delayed(const Duration(milliseconds: 500));
    socket.add(
      'GET $path HTTP/1.0\r\nHost: $host:$targetPort\r\n'
              'Connection: close\r\n\r\n'
          .codeUnits,
    );
    final out = BytesBuilder();
    try {
      while (await iterator.moveNext().timeout(const Duration(seconds: 30))) {
        out.add(iterator.current);
      }
    } on TimeoutException {
      // full 模式可能保持连接不关闭；已收到的响应仍然有效。
      if (out.isEmpty) rethrow;
    }
    return String.fromCharCodes(out.takeBytes());
  } finally {
    await iterator.cancel();
    await socket.close();
  }
}

Future<List<int>> _socksConnectReply({
  required int socksPort,
  required String host,
  required int targetPort,
}) async {
  final socket = await Socket.connect(
    '127.0.0.1',
    socksPort,
    timeout: const Duration(seconds: 5),
  );
  final iterator = StreamIterator<List<int>>(socket);
  try {
    socket.add([5, 1, 0]);
    if (!await iterator.moveNext().timeout(const Duration(seconds: 5))) {
      throw StateError('SOCKS greeting EOF');
    }
    final octets = host.split('.').map(int.parse).toList();
    socket.add([5, 1, 0, 1, ...octets, targetPort >> 8, targetPort & 0xff]);
    if (!await iterator.moveNext().timeout(const Duration(seconds: 15))) {
      throw StateError('SOCKS connect EOF');
    }
    return iterator.current;
  } finally {
    await iterator.cancel();
    await socket.close();
  }
}

Future<String> _socksHttpGetWithRetry({
  required int socksPort,
  required String host,
  required int targetPort,
  String path = '/',
}) async {
  String last = '';
  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      final response = await _socksHttpGet(
        socksPort: socksPort,
        host: host,
        targetPort: targetPort,
        path: path,
      );
      if (response.contains('HTTP/1.')) return response;
      last = response;
    } catch (e) {
      last = '$e';
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  return last;
}

void main() {
  HttpOverrides.global = null;

  test('SUO5 SOCKS tunnel reaches the target', () async {
    final url = _env('MATRIX_SUO5_URL');
    final target = _env('MATRIX_SUO5_TARGET');
    if (url == null || target == null) {
      markTestSkipped('set MATRIX_SUO5_URL/MATRIX_SUO5_TARGET');
      return;
    }
    final parts = target.split(':');
    final targetHost = parts.first;
    final targetPort = int.parse(parts.last);
    final path = _env('MATRIX_SUO5_PATH') ?? '/';
    final listenPort = await _freePort();

    final session = Suo5Session(label: 'integration');
    addTearDown(session.stop);
    await session.start(Suo5Config(targetUrl: url, listenPort: listenPort));

    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (DateTime.now().isBefore(deadline) &&
        session.status == Suo5Status.connecting) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(session.status, Suo5Status.running, reason: session.logs.join('\n'));

    final response = await _socksHttpGetWithRetry(
      socksPort: listenPort,
      host: targetHost,
      targetPort: targetPort,
      path: path,
    );
    expect(response, contains('HTTP/1.'), reason: session.logs.join('\n'));
    expect(response, contains('200'), reason: session.logs.join('\n'));
  });

  test(
    'SUO5 JSP SOCKS tunnel reaches the target',
    timeout: const Timeout(Duration(minutes: 2)),
    () async {
      final url = _env('MATRIX_SUO5_JSP_URL');
      final target = _env('MATRIX_SUO5_JSP_TARGET');
      if (url == null || target == null) {
        markTestSkipped('set MATRIX_SUO5_JSP_URL/MATRIX_SUO5_JSP_TARGET');
        return;
      }
      final parts = target.split(':');
      final targetHost = parts.first;
      final targetPort = int.parse(parts.last);
      final path = _env('MATRIX_SUO5_JSP_PATH') ?? '/';
      final listenPort = await _freePort();

      final session = Suo5Session(label: 'integration-jsp');
      addTearDown(session.stop);
      await session.start(Suo5Config(targetUrl: url, listenPort: listenPort));

      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (DateTime.now().isBefore(deadline) &&
          session.status == Suo5Status.connecting) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(
        session.status,
        Suo5Status.running,
        reason: session.logs.join('\n'),
      );

      final response = await _socksHttpGetWithRetry(
        socksPort: listenPort,
        host: targetHost,
        targetPort: targetPort,
        path: path,
      );
      expect(response, contains('HTTP/1.'), reason: session.logs.join('\n'));
      expect(response, contains('200'), reason: session.logs.join('\n'));
    },
  );

  test('SUO5 probe does not bind a SOCKS listener', () async {
    final url = _env('MATRIX_SUO5_URL');
    if (url == null) {
      markTestSkipped('set MATRIX_SUO5_URL');
      return;
    }
    final session = Suo5Session(label: 'probe');
    addTearDown(session.stop);
    await session.probe(Suo5Config(targetUrl: url, listenPort: 0));
    expect(session.status, Suo5Status.idle);
  });

  test('SUO5 refused target returns SOCKS failure reply', () async {
    final url = _env('MATRIX_SUO5_URL');
    final target = _env('MATRIX_SUO5_TARGET');
    if (url == null || target == null) {
      markTestSkipped('set MATRIX_SUO5_URL/MATRIX_SUO5_TARGET');
      return;
    }
    final targetHost = target.split(':').first;
    final listenPort = await _freePort();
    final session = Suo5Session(label: 'refused');
    addTearDown(session.stop);
    await session.start(Suo5Config(targetUrl: url, listenPort: listenPort));
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (DateTime.now().isBefore(deadline) &&
        session.status == Suo5Status.connecting) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(session.status, Suo5Status.running, reason: session.logs.join('\n'));

    final reply = await _socksConnectReply(
      socksPort: listenPort,
      host: targetHost,
      targetPort: 9, // discard port, expected closed
    );
    expect(reply[0], 5);
    expect(reply[1], isNot(0), reason: 'closed target must not yield success');
  });

  test('SUO6 SOCKS tunnel reaches the target', () async {
    final url = _env('MATRIX_SUO6_URL');
    final target = _env('MATRIX_SUO6_TARGET');
    if (url == null || target == null) {
      markTestSkipped('set MATRIX_SUO6_URL/MATRIX_SUO6_TARGET');
      return;
    }
    final parts = target.split(':');
    final targetHost = parts.first;
    final targetPort = int.parse(parts.last);
    final path = _env('MATRIX_SUO6_PATH') ?? '/';
    final listenPort = await _freePort();

    final session = Suo6Session(label: 'integration');
    addTearDown(session.stop);
    await session.start(Suo6Config(targetUrl: url, listenPort: listenPort));

    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (DateTime.now().isBefore(deadline) &&
        session.status == Suo6Status.connecting) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(session.status, Suo6Status.running, reason: session.logs.join('\n'));

    final response = await _socksHttpGetWithRetry(
      socksPort: listenPort,
      host: targetHost,
      targetPort: targetPort,
      path: path,
    );
    expect(response, contains('HTTP/1.'), reason: session.logs.join('\n'));
    expect(response, contains('200'), reason: session.logs.join('\n'));
  });
}
