import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/connectors/godzilla/godzilla_transport.dart';
import 'package:matrix/connectors/godzilla/godzilla_variant.dart';
import 'package:matrix/core/crypto/godzilla_crypto.dart';

/// 进程内 wire 兼容测试：不执行 .NET/ASP，只验证请求形状与响应解密。
class _WireServer {
  _WireServer._(this._server, this.variant, this.password, this.secretKey)
    : key16 = GodzillaCrypto.deriveKey16(secretKey);

  final HttpServer _server;
  final GodzillaVariant variant;
  final String password;
  final String secretKey;
  final String key16;
  final List<HttpRequest> requests = [];
  final List<String> bodies = [];
  final List<Uint8List> bodyBytes = [];

  String get url => 'http://${_server.address.host}:${_server.port}/shell';

  static Future<_WireServer> start(GodzillaVariant variant) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _WireServer._(server, variant, 'mAtrix_911', 'key');
    server.listen(fake._handle);
    return fake;
  }

  Future<void> close() => _server.close(force: true);

  String _markerPassword() =>
      variant.markerUsesSecretKey ? secretKey : password;

  String get _markerKey16 => variant.markerKeyUsesDoubleHash
      ? GodzillaCrypto.md5Hex(key16).substring(0, 16)
      : key16;

  Future<void> _handle(HttpRequest request) async {
    final body = await request.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
    requests.add(request);
    bodies.add(utf8.decode(body, allowMalformed: true));
    bodyBytes.add(Uint8List.fromList(body));
    final response = request.response;

    // 第一次是播种；返回 200 空体即可。
    if (bodies.length == 1) {
      response.statusCode = 200;
      await response.close();
      return;
    }

    final markers = GodzillaCrypto.markers(
      password: _markerPassword(),
      key16: _markerKey16,
      style: variant.markerStyle,
    );
    final plain = Uint8List.fromList(utf8.encode('wire-ok'));
    final cipher = GodzillaCrypto.encrypt(plain, key16, variant.cipher);
    final encoded = base64.encode(cipher);
    final text = switch (variant.wire) {
      GodzillaWire.asmxBase64 =>
        '<?xml version="1.0"?><soap:Envelope><soap:Body>'
            '${markers.left}$encoded${markers.right}</soap:Body></soap:Envelope>',
      _ => '${markers.left}$encoded${markers.right}',
    };
    response.headers.contentType = ContentType.text;
    response.write(text);
    await response.close();
  }
}

Future<void> _expectWire(
  GodzillaVariant variant,
  String expectedRequestSha256,
  void Function(_WireServer) check,
) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  final fake = await _WireServer.start(variant);
  addTearDown(fake.close);
  final transport = GodzillaTransport(
    url: fake.url,
    password: 'mAtrix_911',
    secretKey: 'key',
    variant: variant,
    engineLoader: () async => Uint8List.fromList([1, 2, 3]),
  );

  final result = await transport.call({'methodName': utf8.encode('test')});
  expect(utf8.decode(result), 'wire-ok');
  expect(fake.bodies, hasLength(2));
  expect(
    sha256.convert(fake.bodyBytes.last).toString(),
    expectedRequestSha256,
    reason: 'Dart request bytes must match the upstream Java client',
  );
  check(fake);
}

void main() {
  test('CSHAP_ASMX_AES_BASE64 uses SOAP XML and SOAPAction', () async {
    await _expectWire(
      GodzillaVariant.csharpAsmxAesBase64,
      '6f979c94d5a6fbdc5082988251ab7b0eefdcde44c7f4a9cd9de304c56ceedf38',
      (fake) {
        expect(fake.requests.last.headers.contentType?.mimeType, 'text/xml');
        expect(
          fake.requests.last.headers.value('soapaction'),
          '"http://tempuri.org/mAtrix_911"',
        );
        expect(fake.bodies.last, contains('<mAtrix_911'));
        expect(fake.bodies.last, contains('<mAtrix_911>'));
      },
    );
  });

  test('CSHAP_EVAL_AES_BASE64 sends eval loader and secretKey data', () async {
    await _expectWire(
      GodzillaVariant.csharpEvalAesBase64,
      'e0099210a36c7a6e66a6cd52505edccd1e16ada1c4615d03d25ab87e88bb89af',
      (fake) {
        expect(fake.bodies.last, startsWith('mAtrix_911=eval'));
        expect(fake.bodies.last, contains('&key='));
        expect(fake.bodies.last, contains('eval%28'));
      },
    );
  });

  test('ASP_EVAL_BASE64 sends hex chopper and secretKey data', () async {
    await _expectWire(
      GodzillaVariant.aspEvalBase64,
      '58e51c0272199f7b0e7bde6e6adab04cadf9dec16f484fc08df59e3f0de7060f',
      (fake) {
        expect(fake.bodies.last, startsWith('mAtrix_911=eval'));
        expect(fake.bodies.last, contains('&key='));
        expect(fake.bodies.last, contains('eval%28'));
        // 无加密：secretKey 参数是 decode 后的参数密文（这里只校验格式）。
        final query = Uri.splitQueryString(fake.bodies.last);
        expect(query['key'], isNotEmpty);
      },
    );
  });
}
