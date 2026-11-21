import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/connectors/jsp_behinder_connector_v2.dart';
import 'package:matrix/core/crypto/behinder_crypto.dart';
import 'package:matrix/models/webshell.dart';

/// 进程内 JSP Behinder v2 端点：验证 buildCat 返回的 base64(file)
/// 会被 readFile 解码，而不是原样显示。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test('readFile decodes buildCat base64', () async {
    const password = 'mAtrix_911';
    final key = BehinderCrypto.deriveKey(password);
    final aes = enc.Encrypter(
      enc.AES(
        enc.Key(Uint8List.fromList(utf8.encode(key))),
        mode: enc.AESMode.ecb,
      ),
    );

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      final body = await request.fold<List<int>>(
        <int>[],
        (a, b) => a..addAll(b),
      );
      if (request.method == 'GET') {
        request.response.statusCode = 200;
        await request.response.close();
        return;
      }
      // v2 body = base64(AES/ECB(class bytes))；先确认可解密。
      final plain = aes.decryptBytes(
        enc.Encrypted(Uint8List.fromList(base64.decode(utf8.decode(body)))),
      );
      expect(plain, isNotEmpty);
      // buildCat 的返回值：base64("hello")，外层再 AES/ECB，服务器再 base64。
      final fileB64 = base64.encode(utf8.encode('hello'));
      final encrypted = aes.encryptBytes(utf8.encode(fileB64)).bytes;
      request.response.write(base64.encode(encrypted));
      await request.response.close();
    });

    final ws = Webshell(
      id: 0,
      projectId: 0,
      name: 'jsp-v2-it',
      url: 'http://${server.address.host}:${server.port}/shell.jsp',
      password: password,
      type: 'jsp',
      connectorType: 'jsp_behinder_v2',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    final connector = JspBehinderConnectorV2(ws);

    expect(await connector.readFile('/tmp/hello.txt'), 'hello');
  });
}
