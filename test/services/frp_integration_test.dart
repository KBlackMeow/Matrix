import 'package:matrix/services/frp_client_service.dart';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// FRP 真实回环测试（默认跳过）。
///
/// ```bash
/// MATRIX_FRP_SERVER=127.0.0.1 \
/// MATRIX_FRP_PORT=17000 \
/// MATRIX_FRP_TOKEN=matrix-test-token \
/// MATRIX_FRP_REMOTE_PORT=16000 \
/// flutter test test/services/tunnel_integration_test.dart
/// ```
String? _env(String key) {
  final v = Platform.environment[key];
  return v == null || v.trim().isEmpty ? null : v.trim();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('FRP TCP tunnel forwards a real connection', () async {
    final server = _env('MATRIX_FRP_SERVER');
    final port = int.tryParse(_env('MATRIX_FRP_PORT') ?? '');
    final token = _env('MATRIX_FRP_TOKEN') ?? '';
    final remotePort = int.tryParse(_env('MATRIX_FRP_REMOTE_PORT') ?? '');
    if (server == null || port == null || remotePort == null) {
      markTestSkipped('set MATRIX_FRP_SERVER/PORT/REMOTE_PORT');
      return;
    }

    final echo = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(echo.close);
    echo.listen((client) {
      client.listen(client.add);
    });

    final frp = FrpClientService();
    frp.autoReconnect = false;
    addTearDown(frp.stop);
    await frp.start(
      FrpTunnelConfig(
        serverAddr: server,
        serverPort: port,
        token: token,
        proxyName: 'mx-it-${DateTime.now().microsecondsSinceEpoch}',
        remotePort: remotePort,
        localAddr: '127.0.0.1',
        localPort: echo.port,
        version: _env('MATRIX_FRP_VERSION') ?? '0.72.0',
      ),
    );

    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (DateTime.now().isBefore(deadline) &&
        frp.status == FrpTunnelStatus.connecting) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(frp.status, FrpTunnelStatus.running, reason: frp.logs.join('\n'));

    final socket = await Socket.connect(
      server,
      remotePort,
      timeout: const Duration(seconds: 5),
    );
    socket.add('matrix-frp'.codeUnits);
    final reply = await socket.first.timeout(const Duration(seconds: 5));
    expect(String.fromCharCodes(reply), 'matrix-frp');
    await socket.close();
  });
}
