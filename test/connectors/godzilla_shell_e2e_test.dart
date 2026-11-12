import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/connectors/connector_factory.dart';
import 'package:matrix/connectors/godzilla/godzilla_shell_generator.dart';
import 'package:matrix/models/webshell.dart';

/// 生成 → 部署 → 连接 的闭环测试（默认跳过）。
///
/// 需要本机有 PHP CLI：
///
/// ```bash
/// MATRIX_GODZILLA_SHELL_E2E=1 flutter test test/connectors/godzilla_shell_e2e_test.dart
/// ```
///
/// 这是唯一能证明“生成的壳真的能被连接器连上”的自动化测试；
/// 没有 PHP 的环境会自动跳过，不影响常规 `flutter test`。
Future<int> _freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

Future<bool> _waitForHttp(int port, {Duration timeout = const Duration(seconds: 10)}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(milliseconds: 300),
      );
      socket.destroy();
      return true;
    } catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
  }
  return false;
}

Future<void> _deployAndConnect({
  required GodzillaCryption cryption,
}) async {
  final connectorType = cryption.connectorType;
  final dir = await Directory.systemTemp.createTemp('matrix_gz_e2e_');
  final port = await _freePort();
  Process? process;
  try {
    final shell = await GodzillaShellGenerator.generate(
      cryption: cryption,
      password: _password,
      secretKey: _secretKey,
    );
    await File('${dir.path}/${shell.fileName}').writeAsString(shell.content);

    process = await Process.start(
      'php',
      ['-S', '127.0.0.1:$port', '-t', dir.path],
      workingDirectory: dir.path,
    );
    process.stdout.drain<void>();
    process.stderr.drain<void>();
    expect(await _waitForHttp(port), isTrue,
        reason: 'php -S did not start on port $port');

    final connector = ConnectorFactory.create(
      Webshell(
        id: 0,
        projectId: 0,
        name: 'e2e',
        url: 'http://127.0.0.1:$port/${shell.fileName}',
        password: _password,
        secretKey: _secretKey,
        cryption: cryption.id,
        type: 'php',
        connectorType: connectorType,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    expect(await connector.ping(), isTrue,
        reason: connector.lastPingDiagnostic);
    expect(await connector.executeCommand('echo MATRIX_GEN_E2E'),
        contains('MATRIX_GEN_E2E'));

    final path = '${dir.path}/written.txt';
    expect(await connector.writeFile(path, 'generated-shell-ok'), isTrue);
    expect(await connector.readFile(path), 'generated-shell-ok');
    expect(await connector.deleteFile(path), isTrue);
  } finally {
    process?.kill();
    await process?.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () => -1,
    );
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}

const _password = 'matrix_gen_e2e';
const _secretKey = 'matrix-key';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter_test 默认把 HttpClient 换成永远返回 400 的假实现；
  // 这里需要真实回环请求，所以清掉它。
  HttpOverrides.global = null;
  final enabled = Platform.environment['MATRIX_GODZILLA_SHELL_E2E'] == '1';

  group('生成的 PHP 壳可被连接器连接', () {
    if (!enabled) {
      test('skipped: set MATRIX_GODZILLA_SHELL_E2E=1 (needs php CLI)', () {},
          skip: true);
      return;
    }

    test('PHP_XOR_BASE64', () async {
      await _deployAndConnect(cryption: GodzillaCryption.phpXorBase64);
    });

    test('PHP_XOR_RAW', () async {
      await _deployAndConnect(cryption: GodzillaCryption.phpXorRaw);
    });

    test('PHP_EVAL_XOR_BASE64', () async {
      await _deployAndConnect(cryption: GodzillaCryption.phpEvalXorBase64);
    });
  });
}
