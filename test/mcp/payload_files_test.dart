import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/mcp/payload_files.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('matrix_payload_files_');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  group('readPayloadFileBytes', () {
    test('returns text payload bytes unchanged', () async {
      const content = '<?php echo "中文"; ?>';
      final file = File(p.join(tmp.path, 'shell.php'));
      await file.writeAsString(content);

      expect(await readPayloadFileBytes(file.path), utf8.encode(content));
    });

    test('decodes a binary payload stored with the base64 prefix', () async {
      final bytes = <int>[0, 1, 2, 127, 128, 255];
      final file = File(p.join(tmp.path, 'engine.bin'));
      await file.writeAsString('$payloadBinaryPrefix${base64Encode(bytes)}\n');

      expect(await readPayloadFileBytes(file.path), bytes);
    });

    test('rejects an empty payload path', () async {
      await expectLater(
        () => readPayloadFileBytes('  '),
        throwsA(isA<PayloadFileException>()),
      );
    });

    test('rejects a missing payload file', () async {
      await expectLater(
        () => readPayloadFileBytes(p.join(tmp.path, 'missing.bin')),
        throwsA(isA<PayloadFileException>()),
      );
    });

    test('rejects malformed binary payload content', () async {
      final file = File(p.join(tmp.path, 'broken.bin'));
      await file.writeAsString('${payloadBinaryPrefix}not-base64!');

      await expectLater(
        () => readPayloadFileBytes(file.path),
        throwsA(isA<PayloadFileException>()),
      );
    });
  });

  group('defaultPayloadDownloadName', () {
    test('preserves a normal payload name', () {
      expect(
        defaultPayloadDownloadName(id: 1, name: 'php_eval_post.php'),
        'php_eval_post.php',
      );
    });

    test('strips directory components from the payload name', () {
      expect(
        defaultPayloadDownloadName(id: 2, name: 'webshell/php_eval_post.php'),
        'php_eval_post.php',
      );
      expect(
        defaultPayloadDownloadName(id: 2, name: r'C:\payloads\shell.jsp'),
        'shell.jsp',
      );
    });

    test('falls back to the payload id for unusable names', () {
      expect(defaultPayloadDownloadName(id: 7, name: '  '), 'payload_7');
      expect(defaultPayloadDownloadName(id: 7, name: '..'), 'payload_7');
      expect(defaultPayloadDownloadName(id: 7, name: '/'), 'payload_7');
    });
  });
}
