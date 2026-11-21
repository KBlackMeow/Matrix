import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/connectors/connector_factory.dart';
import 'package:matrix/models/webshell.dart';

/// 真实冰蝎目标集成测试（默认跳过）。
///
/// ```bash
/// MATRIX_BEHINDER_PHP_URL=http://127.0.0.1:18085/php_behinder.php \
/// MATRIX_BEHINDER_PHP_MAGIC_URL=http://127.0.0.1:18085/php_behinder_magic.php \
/// MATRIX_BEHINDER_JSP_URL=http://127.0.0.1:18084/jsp_behinder.jsp \
/// MATRIX_BEHINDER_JSPX_URL=http://127.0.0.1:18084/jsp_behinder.jspx \
/// flutter test test/connectors/behinder_integration_test.dart
/// ```
Webshell _shell({
  required String url,
  required String connectorType,
  required String type,
}) {
  final now = DateTime.now();
  return Webshell(
    id: 0,
    projectId: 0,
    name: 'behinder-it',
    url: url,
    password: Platform.environment['MATRIX_BEHINDER_PASS'] ?? 'mAtrix_911',
    type: type,
    method: 'POST',
    connectorType: connectorType,
    createdAt: now,
    updatedAt: now,
  );
}

void _exercise(String label, String connectorType, String type, String url) {
  final connector = ConnectorFactory.create(
    _shell(url: url, connectorType: connectorType, type: type),
  );

  test('$label: ping', () async {
    expect(
      await connector.ping(),
      isTrue,
      reason: connector.lastPingDiagnostic,
    );
  });

  test('$label: executeCommand', () async {
    expect(
      await connector.executeCommand('echo MATRIX_BEHINDER_OK'),
      contains('MATRIX_BEHINDER_OK'),
    );
  });

  test('$label: binary write/read round-trip', () async {
    final path = '/tmp/matrix_behinder_$label.bin';
    final payload = Uint8List.fromList([0, 1, 2, 255, 254, 0x68, 0x69]);
    expect(await connector.writeFileBinary(path, payload), isTrue);
    final read = await connector.readFileBinary(path);
    expect(base64.encode(read), base64.encode(payload));
    expect(await connector.deleteFile(path), isTrue);
  });

  test('$label: empty file round-trip', () async {
    final path = '/tmp/matrix_behinder_${label}_empty.bin';
    expect(await connector.writeFileBinary(path, Uint8List(0)), isTrue);
    expect(await connector.readFileBinary(path), isEmpty);
    expect(await connector.deleteFile(path), isTrue);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  void groupFor(
    String envKey,
    String label,
    String connectorType,
    String type,
  ) {
    final url = Platform.environment[envKey];
    group(label, () {
      if (url == null || url.isEmpty) {
        test('skipped: set $envKey', () {}, skip: true);
        return;
      }
      _exercise(label, connectorType, type, url);
    });
  }

  groupFor('MATRIX_BEHINDER_PHP_URL', 'php', 'php_behinder', 'php');
  groupFor('MATRIX_BEHINDER_PHP_MAGIC_URL', 'php-magic', 'php_behinder', 'php');
  groupFor('MATRIX_BEHINDER_JSP_URL', 'jsp', 'jsp_behinder', 'jsp');
  groupFor('MATRIX_BEHINDER_JSP_V2_URL', 'jsp-v2', 'jsp_behinder_v2', 'jsp');
  groupFor('MATRIX_BEHINDER_JSPX_URL', 'jspx', 'jsp_behinder', 'jsp');
  groupFor(
    'MATRIX_BEHINDER_JSP_CLASSLOADER_URL',
    'jsp-classloader',
    'jsp_classloader',
    'jsp',
  );
  groupFor(
    'MATRIX_BEHINDER_JSP_RUNTIME_URL',
    'jsp-runtime',
    'jsp_runtime',
    'jsp',
  );
}
