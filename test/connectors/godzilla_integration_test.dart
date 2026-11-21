import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/connectors/connector_factory.dart';
import 'package:matrix/models/webshell.dart';

/// 真实目标集成测试（默认跳过）。
///
/// ```bash
/// MATRIX_GODZILLA_JSP_URL=http://127.0.0.1:8082/godzilla.jsp \
/// MATRIX_GODZILLA_PHP_URL=http://127.0.0.1:8091/shell.php \
/// MATRIX_GODZILLA_PASS=mAtrix_911 \
/// MATRIX_GODZILLA_KEY=key \
/// flutter test test/connectors/godzilla_integration_test.dart
/// ```
Webshell _shell({required String url, required String connectorType}) {
  final now = DateTime.now();
  return Webshell(
    id: 0,
    projectId: 0,
    name: 'godzilla-it',
    url: url,
    password: Platform.environment['MATRIX_GODZILLA_PASS'] ?? 'mAtrix_911',
    secretKey: Platform.environment['MATRIX_GODZILLA_KEY'] ?? 'key',
    type: ConnectorFactory.typeLabel(connectorType),
    connectorType: connectorType,
    createdAt: now,
    updatedAt: now,
  );
}

void _exercise(String connectorType, String url) {
  final connector = ConnectorFactory.create(
    _shell(url: url, connectorType: connectorType),
  );

  test('$connectorType: ping', () async {
    expect(
      await connector.ping(),
      isTrue,
      reason: connector.lastPingDiagnostic,
    );
  });

  test('$connectorType: executeCommand', () async {
    final out = await connector.executeCommand('echo MATRIX_GZ_OK');
    expect(out, contains('MATRIX_GZ_OK'));
  });

  test('$connectorType: listDirectory', () async {
    final dir = await connector.getCurrentDir();
    final entries = await connector.listDirectory(dir);
    expect(entries, isNotEmpty, reason: 'directory: $dir');
  });

  test('$connectorType: native file operations', () async {
    final dir =
        '/tmp/matrix_gz_ops_${connectorType}_${DateTime.now().millisecondsSinceEpoch}';
    final a = '$dir/a.txt';
    final b = '$dir/b.txt';
    final c = '$dir/c.txt';

    expect(await connector.createDirectory(dir), isTrue);
    expect(await connector.createFile(a), isTrue);
    expect(await connector.writeFile(a, 'matrix-ops'), isTrue);
    expect(await connector.fileSize(a), 10);
    expect(utf8.decode(await connector.readFileRange(a, length: 6)), 'matrix');
    expect(await connector.copyFile(a, b), isTrue);
    expect(await connector.readFile(b), 'matrix-ops');
    expect(await connector.moveFile(b, c), isTrue);
    expect(await connector.readFile(c), 'matrix-ops');
    expect(await connector.deleteFile(a), isTrue);
    expect(await connector.deleteFile(c), isTrue);
    expect(await connector.listDirectory(dir), isEmpty);
  });

  test('$connectorType: binary write/read round-trip', () async {
    final path = '/tmp/matrix_gz_it_$connectorType.bin';
    final payload = Uint8List.fromList([0, 1, 2, 255, 254, 0x68, 0x69]);
    expect(await connector.writeFileBinary(path, payload), isTrue);
    final read = await connector.readFileBinary(path);
    expect(base64.encode(read), base64.encode(payload));
    expect(await connector.deleteFile(path), isTrue);
  });

  test('$connectorType: getSystemInfo', () async {
    final info = await connector.getSystemInfo();
    expect(info['OS'], isNotNull);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  final jspUrl = Platform.environment['MATRIX_GODZILLA_JSP_URL'];
  final phpUrl = Platform.environment['MATRIX_GODZILLA_PHP_URL'];

  group('JSP Godzilla (standard shell)', () {
    if (jspUrl == null || jspUrl.isEmpty) {
      test('skipped: set MATRIX_GODZILLA_JSP_URL', () {}, skip: true);
      return;
    }
    _exercise('jsp_godzilla', jspUrl);
  });

  group('PHP Godzilla (standard shell)', () {
    if (phpUrl == null || phpUrl.isEmpty) {
      test('skipped: set MATRIX_GODZILLA_PHP_URL', () {}, skip: true);
      return;
    }
    _exercise('php_godzilla', phpUrl);
  });
}
