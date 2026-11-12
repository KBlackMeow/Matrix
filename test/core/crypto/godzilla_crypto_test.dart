import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/connectors/godzilla/godzilla_variant.dart';
import 'package:matrix/core/crypto/godzilla_codec.dart';
import 'package:matrix/core/crypto/godzilla_crypto.dart';

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  // 真实 Godzilla 目标的权威向量：
  // password = mAtrix_911, secretKey = key
  const password = 'mAtrix_911';
  const secretKey = 'key';
  final key16 = GodzillaCrypto.deriveKey16(secretKey);

  group('密钥与标记', () {
    test('key16 = md5(secretKey)[0:16]', () {
      expect(key16, '3c6e0b8a9c15224a');
    });

    test('空 secretKey 回退到 key', () {
      expect(GodzillaCrypto.deriveKey16(''), '3c6e0b8a9c15224a');
    });

    test('Java/C# 标记为大写 16/16', () {
      final m = GodzillaCrypto.markers(
        password: password,
        key16: key16,
        style: GodzillaMarkerStyle.upper16,
      );
      expect(m.left, '371BE1CA27DE980E');
      expect(m.right, '4CFD279AB200099A');
    });

    test('PHP 标记为小写 16/16', () {
      final m = GodzillaCrypto.markers(
        password: password,
        key16: key16,
        style: GodzillaMarkerStyle.lower16,
      );
      expect(m.left, '371be1ca27de980e');
      expect(m.right, '4cfd279ab200099a');
    });

    test('ASP 标记为小写 6/6（[0:6] / [20:26]）', () {
      final m = GodzillaCrypto.markers(
        password: password,
        key16: key16,
        style: GodzillaMarkerStyle.lowerAsp6,
      );
      expect(m.left, '371be1');
      expect(m.right, '279ab2');
    });

    test('标记候选包含 Java 前导零丢失后的切分', () {
      final candidates = GodzillaCrypto.markerCandidates(
        password: password,
        key16: key16,
        style: GodzillaMarkerStyle.upper16,
      );
      expect(candidates.length, 2);
      expect(candidates[0].left, '371BE1CA27DE980E');
      expect(candidates[1].left, '71BE1CA27DE980E4');
    });
  });

  group('参数序列化', () {
    test('长度字段是小端序', () {
      final encoded = GodzillaCodec.encodeParams({
        'cmdLine': utf8.encode('id'),
      });
      expect(_hex(encoded), '636d644c696e6502020000006964');
    });

    test('methodName=execCommand 的权威向量', () {
      final encoded = GodzillaCodec.encodeParams({
        'methodName': utf8.encode('execCommand'),
      });
      expect(
        _hex(encoded),
        '6d6574686f644e616d65020b00000065786563436f6d6d616e64',
      );
    });

    test('组合参数与 Java HashMap 输出逐字节一致', () {
      final encoded = GodzillaCodec.encodeParams({
        'cmdLine': utf8.encode('id'),
        'methodName': utf8.encode('execCommand'),
      });
      expect(
        _hex(encoded),
        '636d644c696e65020200000069646d6574686f644e616d65020b00000065786563436f6d6d616e64',
      );
    });

    test('二进制/中文/空值往返', () {
      final params = <String, List<int>>{
        'bin': [0x00, 0x01, 0x02, 0xff, 0xfe],
        'cn': utf8.encode('中文路径/文件.txt'),
        'empty': <int>[],
      };
      final decoded = GodzillaCodec.decodeParams(
        GodzillaCodec.encodeParams(params),
      );
      expect(decoded['bin'], equals(params['bin']));
      expect(utf8.decode(decoded['cn']!), '中文路径/文件.txt');
      expect(decoded['empty'], isEmpty);
    });
  });

  group('加解密', () {
    test('XOR 往返', () {
      final data = Uint8List.fromList(utf8.encode('methodName=test'));
      final encrypted = GodzillaCrypto.xor(data, key16);
      final decrypted = GodzillaCrypto.xor(encrypted, key16);
      expect(decrypted, equals(data));
    });

    test('AES/ECB 往返', () {
      final data = Uint8List.fromList(utf8.encode('{"a":1}'));
      final encrypted = GodzillaCrypto.aesEcbEncrypt(data, key16);
      expect(GodzillaCrypto.aesEcbDecrypt(encrypted, key16), equals(data));
    });

    test('AES/CBC(key=IV) 往返', () {
      final data = Uint8List.fromList(utf8.encode('{"a":1}'));
      final encrypted = GodzillaCrypto.aesCbcEncrypt(data, key16);
      expect(GodzillaCrypto.aesCbcDecrypt(encrypted, key16), equals(data));
    });
  });

  group('响应提取', () {
    final params = GodzillaCodec.encodeParams({
      'methodName': utf8.encode('execCommand'),
      'arg-0': utf8.encode('id'),
    });

    Uint8List body(String left, Uint8List cipher, String right) =>
        Uint8List.fromList(utf8.encode('$left${base64.encode(cipher)}$right'));

    test('Java：标记 + AES/ECB + gzip', () {
      final markers = GodzillaCrypto.markers(
        password: password,
        key16: key16,
        style: GodzillaMarkerStyle.upper16,
      );
      final cipher = GodzillaCrypto.aesEcbEncrypt(
        GodzillaCodec.gzip(params),
        key16,
      );
      final out = GodzillaCrypto.extractResponse(
        rawBody: body(markers.left, cipher, markers.right),
        password: password,
        key16: key16,
        variant: GodzillaVariant.javaAesBase64,
      );
      expect(out, isNotNull);
      expect(_hex(out!), _hex(params));
    });

    test('C#：标记 + AES/CBC + gzip', () {
      final markers = GodzillaCrypto.markers(
        password: password,
        key16: key16,
        style: GodzillaMarkerStyle.upper16,
      );
      final cipher = GodzillaCrypto.aesCbcEncrypt(
        GodzillaCodec.gzip(params),
        key16,
      );
      final out = GodzillaCrypto.extractResponse(
        rawBody: body(markers.left, cipher, markers.right),
        password: password,
        key16: key16,
        variant: GodzillaVariant.csharpAesBase64,
      );
      expect(out, isNotNull);
      expect(_hex(out!), _hex(params));
    });

    test('PHP：小写标记 + XOR', () {
      final markers = GodzillaCrypto.markers(
        password: password,
        key16: key16,
        style: GodzillaMarkerStyle.lower16,
      );
      final cipher = GodzillaCrypto.xor(params, key16);
      final out = GodzillaCrypto.extractResponse(
        rawBody: body(markers.left, cipher, markers.right),
        password: password,
        key16: key16,
        variant: GodzillaVariant.phpXorBase64,
      );
      expect(out, isNotNull);
      expect(_hex(out!), _hex(params));
    });

    test('ASP：6 字符标记 + XOR', () {
      final markers = GodzillaCrypto.markers(
        password: password,
        key16: key16,
        style: GodzillaMarkerStyle.lowerAsp6,
      );
      final cipher = GodzillaCrypto.xor(params, key16);
      final out = GodzillaCrypto.extractResponse(
        rawBody: body(markers.left, cipher, markers.right),
        password: password,
        key16: key16,
        variant: GodzillaVariant.aspXorBase64,
      );
      expect(out, isNotNull);
      expect(_hex(out!), _hex(params));
    });

    test('Java 前导零丢失（服务端 31 字符标记）仍可解析', () {
      // md5('p10' + key16) = 0c6f5a45d8e1b080c4361031c00e9fc5
      const p10 = 'p10';
      final m = GodzillaCrypto.md5Hex('$p10$key16');
      expect(m.startsWith('0'), isTrue);
      final cipher = GodzillaCrypto.aesEcbEncrypt(
        GodzillaCodec.gzip(params),
        key16,
      );
      final out = GodzillaCrypto.extractResponse(
        rawBody: body(
          m.substring(1, 17).toUpperCase(),
          cipher,
          m.substring(17).toUpperCase(),
        ),
        password: p10,
        key16: key16,
        variant: GodzillaVariant.javaAesBase64,
      );
      expect(out, isNotNull);
      expect(_hex(out!), _hex(params));
    });

    test('标记缺失返回 null', () {
      final out = GodzillaCrypto.extractResponse(
        rawBody: Uint8List.fromList(utf8.encode('<html>error</html>')),
        password: password,
        key16: key16,
        variant: GodzillaVariant.javaAesBase64,
      );
      expect(out, isNull);
    });

    test('RAW：整段密文解密', () {
      final cipher = GodzillaCrypto.aesEcbEncrypt(
        GodzillaCodec.gzip(params),
        key16,
      );
      final out = GodzillaCrypto.extractRawResponse(
        rawBody: cipher,
        key16: key16,
        variant: GodzillaVariant.javaAesRaw,
      );
      expect(out, isNotNull);
      expect(_hex(out!), _hex(params));
    });

    test('RAW：AES 长度非法返回 null', () {
      final out = GodzillaCrypto.extractRawResponse(
        rawBody: Uint8List.fromList([1, 2, 3]),
        key16: key16,
        variant: GodzillaVariant.javaAesRaw,
      );
      expect(out, isNull);
    });

    test('base64 长度非法返回 null', () {
      final markers = GodzillaCrypto.markers(
        password: password,
        key16: key16,
        style: GodzillaMarkerStyle.upper16,
      );
      final out = GodzillaCrypto.extractResponse(
        rawBody: Uint8List.fromList(
          utf8.encode('${markers.left}AAAA${markers.right}'),
        ),
        password: password,
        key16: key16,
        variant: GodzillaVariant.javaAesBase64,
      );
      // 3 字节密文会被 AES 拒绝，解析应安全返回 null。
      expect(out, isNull);
    });
  });
}
