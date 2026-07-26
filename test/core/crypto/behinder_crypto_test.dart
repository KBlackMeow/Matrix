import 'dart:convert';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/core/crypto/behinder_crypto.dart';

void main() {
  const testKey = '42b842fc69195c9d';

  enc.Key aesKey(String k) => enc.Key(Uint8List.fromList(utf8.encode(k)));

  /// Simulate PHP openssl_encrypt($data, "AES128", $key) = AES-128-CBC + zero IV + base64
  String phpEncrypt(String plain) {
    final e = enc.Encrypter(enc.AES(aesKey(testKey), mode: enc.AESMode.cbc));
    return e.encryptBytes(utf8.encode(plain), iv: enc.IV(Uint8List(16))).base64;
  }

  /// Simulate JSP standard agent Encrypt: AES/ECB → base64
  String jspEncrypt(String plain) {
    final e = enc.Encrypter(enc.AES(aesKey(testKey), mode: enc.AESMode.ecb));
    return e.encryptBytes(utf8.encode(plain)).base64;
  }

  /// Simulate JSP aes_with_magic Encrypt: base64(AES/ECB) + random tail
  Uint8List jspMagicEncrypt(String plain) {
    final b64 = jspEncrypt(plain);
    final magicNum = int.parse(testKey.substring(0, 2), radix: 16) % 16;
    final raw = Uint8List(b64.length + magicNum);
    raw.setAll(0, utf8.encode(b64));
    for (var i = 0; i < magicNum; i++) {
      raw[b64.length + i] = i;
    }
    return raw;
  }

  /// Simulate PHP XOR fallback: raw bytes
  Uint8List xorEncrypt(List<int> data) {
    final keyBytes = utf8.encode(testKey);
    final result = Uint8List(data.length);
    for (var i = 0; i < data.length; i++) {
      result[i] = data[i] ^ keyBytes[(i + 1) & 15];
    }
    return result;
  }

  group('BehinderCrypto', () {
    group('deriveKey', () {
      test('MD5 first 16 chars', () {
        expect(BehinderCrypto.deriveKey('mAtrix_911'), '42b842fc69195c9d');
      });
      test('lowercase hex unchanged', () {
        expect(BehinderCrypto.deriveKey('e45e329feb5d925b'), 'e45e329feb5d925b');
      });
      test('uppercase hex normalized', () {
        expect(BehinderCrypto.deriveKey('E45E329FEB5D925B'), 'e45e329feb5d925b');
      });
      test('empty uses default', () {
        expect(BehinderCrypto.deriveKey('').length, 16);
      });
    });

    group('tryDecryptPhp (AES/CBC/zeroIV)', () {
      test('roundtrip', () {
        const plain = '{"status":"c3VjY2Vzcw==","msg":"dGVzdA=="}';
        expect(BehinderCrypto.tryDecryptPhp(phpEncrypt(plain), testKey), plain);
      });
      test('unicode', () {
        const plain = '你好世界\nこんにちは';
        expect(BehinderCrypto.tryDecryptPhp(phpEncrypt(plain), testKey), plain);
      });
      test('non-base64 → null', () {
        expect(BehinderCrypto.tryDecryptPhp('not base64!!!', testKey), isNull);
      });
      test('wrong key → null', () {
        expect(BehinderCrypto.tryDecryptPhp(phpEncrypt('hello'), '0000000000000000'), isNull);
      });
      test('empty → empty', () {
        expect(BehinderCrypto.tryDecryptPhp('', testKey), '');
      });
    });

    group('tryDecryptPhpXor', () {
      test('roundtrip', () {
        const plain = '{"status":"c3VjY2Vzcw=="}';
        expect(BehinderCrypto.tryDecryptPhpXor(xorEncrypt(utf8.encode(plain)), testKey), plain);
      });
      test('empty → null', () {
        expect(BehinderCrypto.tryDecryptPhpXor(Uint8List(0), testKey), isNull);
      });
    });

    group('tryDecryptJsp (base64 → AES/ECB)', () {
      test('roundtrip', () {
        const plain = '{"status":"c3VjY2Vzcw==","msg":"dGVzdA=="}';
        expect(BehinderCrypto.tryDecryptJsp(jspEncrypt(plain), testKey), plain);
      });
      test('unicode', () {
        const plain = '你好\ntotal 48';
        expect(BehinderCrypto.tryDecryptJsp(jspEncrypt(plain), testKey), plain);
      });
      test('non-base64 → null', () {
        expect(BehinderCrypto.tryDecryptJsp('plain text', testKey), isNull);
      });
      test('empty → empty', () {
        expect(BehinderCrypto.tryDecryptJsp('', testKey), '');
      });
    });

    group('tryDecryptJspWithMagic', () {
      test('roundtrip', () {
        const plain = '{"status":"c3VjY2Vzcw==","msg":"dGVzdA=="}';
        expect(BehinderCrypto.tryDecryptJspWithMagic(jspMagicEncrypt(plain), testKey), plain);
      });
      test('empty → null', () {
        expect(BehinderCrypto.tryDecryptJspWithMagic(Uint8List(0), testKey), isNull);
      });
    });

    group('tryDecryptLegacyMatrix (base64 → AES/ECB plain output)', () {
      test('roundtrip', () {
        const plain = 'MATRIX_JSP_PING';
        expect(BehinderCrypto.tryDecryptLegacyMatrix(phpEncrypt(plain), testKey), plain);
      });
      test('plaintext → null', () {
        expect(BehinderCrypto.tryDecryptLegacyMatrix('hello', testKey), isNull);
      });
    });

    group('extractResponse', () {
      test('extracts msg', () {
        const output = 'total 48\ndrwxr-xr-x';
        final json = '{"status":"c3VjY2Vzcw==","msg":"${base64Encode(utf8.encode(output))}"}';
        expect(BehinderCrypto.extractResponse(json), output);
      });
      test('extracts status when msg missing', () {
        final json = '{"status":"${base64Encode(utf8.encode("failed"))}"}';
        expect(BehinderCrypto.extractResponse(json), 'failed');
      });
      test('plaintext returned as-is', () {
        expect(BehinderCrypto.extractResponse('MATRIX_JSP_PING'), 'MATRIX_JSP_PING');
      });
      test('empty → empty', () {
        expect(BehinderCrypto.extractResponse(''), '');
      });
    });

    group('end-to-end', () {
      test('PHP: phpEncrypt → tryDecryptPhp → extractResponse', () {
        const output = '/var/www/html\nuser=www-data';
        final json = '{"status":"c3VjY2Vzcw==","msg":"${base64Encode(utf8.encode(output))}"}';
        final decrypted = BehinderCrypto.tryDecryptPhp(phpEncrypt(json), testKey);
        expect(BehinderCrypto.extractResponse(decrypted!), output);
      });
      test('JSP: jspEncrypt → tryDecryptJsp → extractResponse', () {
        const output = '/opt/tomcat\nuser=tomcat';
        final json = '{"status":"c3VjY2Vzcw==","msg":"${base64Encode(utf8.encode(output))}"}';
        final decrypted = BehinderCrypto.tryDecryptJsp(jspEncrypt(json), testKey);
        expect(BehinderCrypto.extractResponse(decrypted!), output);
      });
      test('JSP magic: jspMagicEncrypt → tryDecryptJspWithMagic → extractResponse', () {
        const output = 'magic response';
        final json = '{"status":"c3VjY2Vzcw==","msg":"${base64Encode(utf8.encode(output))}"}';
        final decrypted = BehinderCrypto.tryDecryptJspWithMagic(jspMagicEncrypt(json), testKey);
        expect(BehinderCrypto.extractResponse(decrypted!), output);
      });
    });
  });
}
