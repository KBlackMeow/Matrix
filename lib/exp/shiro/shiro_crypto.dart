import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:pointycastle/export.dart' as pc;

enum ShiroEncryptionMode { cbc, gcm }

/// Shiro rememberMe 加解密相关的工具。
class ShiroCrypto {
  const ShiroCrypto();

  /// 使用指定的 Base64 key 对序列化 payload 进行加密，生成 rememberMe 值。
  Future<String> encryptRememberMe({
    required String keyBase64,
    required Uint8List serializedPayload,
    ShiroEncryptionMode mode = ShiroEncryptionMode.cbc,
  }) async {
    final keyBytes = enc.Key.fromBase64(keyBase64);

    if (mode == ShiroEncryptionMode.cbc) {
      // 终极修复：完全对齐 shiro_check (Go) 的逻辑
      // 1. 使用 Key 的前 16 字节作为 IV
      // 2. 输出格式为 Base64(IV + Ciphertext)
      final ivBytes = Uint8List.fromList(keyBytes.bytes.sublist(0, 16));
      final iv = enc.IV(ivBytes);

      final aes = enc.Encrypter(
        enc.AES(
          keyBytes,
          mode: enc.AESMode.cbc,
          padding: 'PKCS7',
        ),
      );
      final encrypted = aes.encryptBytes(serializedPayload, iv: iv);

      final combined = Uint8List(ivBytes.length + encrypted.bytes.length)
        ..setRange(0, ivBytes.length, ivBytes)
        ..setRange(
            ivBytes.length, ivBytes.length + encrypted.bytes.length, encrypted.bytes);

      return enc.Encrypted(combined).base64;
    } else {
      // Shiro 1.4.2+ GCM 模式：使用标准 AES-GCM（PointyCastle），输出 Nonce(16) + Ciphertext + Tag(16)
      final ivBytes = Uint8List(16);
      final rnd = pc.SecureRandom('Fortuna')
        ..seed(pc.KeyParameter(Uint8List.fromList(DateTime.now()
            .microsecondsSinceEpoch
            .toRadixString(16)
            .codeUnits)));
      for (var i = 0; i < ivBytes.length; i++) {
        ivBytes[i] = rnd.nextUint8();
      }

      final cipher = pc.GCMBlockCipher(pc.AESEngine());
      cipher.init(
        true,
        pc.AEADParameters(
          pc.KeyParameter(keyBytes.bytes),
          128, // macSize 128 bit = 16 bytes
          ivBytes,
          Uint8List(0), // associated data
        ),
      );

      final encryptedBytes = cipher.process(serializedPayload);

      final combined = Uint8List(ivBytes.length + encryptedBytes.length)
        ..setRange(0, ivBytes.length, ivBytes)
        ..setRange(
            ivBytes.length, ivBytes.length + encryptedBytes.length, encryptedBytes);

      return enc.Encrypted(combined).base64;
    }
  }
}
