import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/connectors/aspx_behinder_connector.dart';
import 'package:matrix/core/crypto/behinder_crypto.dart';
import 'package:matrix/models/webshell.dart';

/// 进程内 ASPX Behinder 端点：只验证 readFile 对 FileOperation download
/// 返回的 base64 做了解码。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test('readFile decodes FileOperation download base64', () async {
    const password = 'mAtrix_911';
    final key = BehinderCrypto.deriveKey(password);
    final keyBytes = Uint8List.fromList(utf8.encode(key));
    final aes = enc.Encrypter(
      enc.AES(enc.Key(keyBytes), mode: enc.AESMode.cbc),
    );
    final iv = enc.IV(keyBytes);

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      final body = await request.fold<List<int>>(
        <int>[],
        (a, b) => a..addAll(b),
      );
      // 确认客户端发来的是加密 body；返回 base64("hello") 的 AES 密文。
      expect(body, isNotEmpty);
      final plain = aes.decryptBytes(
        enc.Encrypted(Uint8List.fromList(body)),
        iv: iv,
      );
      expect(plain, isNotEmpty);
      final payload = base64.encode(utf8.encode('hello'));
      final out = aes.encryptBytes(utf8.encode(payload), iv: iv).bytes;
      request.response.add(out);
      await request.response.close();
    });

    final ws = Webshell(
      id: 0,
      projectId: 0,
      name: 'aspx-it',
      url: 'http://${server.address.host}:${server.port}/shell.aspx',
      password: password,
      type: 'aspx',
      connectorType: 'aspx_behinder',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    final connector = AspxBehinderConnector(ws);

    expect(await connector.readFile('C:/tmp/hello.txt'), 'hello');
  });
}
