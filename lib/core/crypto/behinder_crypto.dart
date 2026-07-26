import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:encrypt/encrypt.dart' as enc;

import '../../app/constants.dart';

class BehinderCrypto {
  static String deriveKey(String? rawPassword) {
    final pass = rawPassword?.trim().isNotEmpty == true
        ? rawPassword!.trim()
        : AppConstants.defaultShellPassword;
    if (_isHex(pass, 16)) return pass.toLowerCase();
    final md5 = crypto.md5.convert(utf8.encode(pass)).toString();
    return md5.substring(0, 16);
  }

  static bool _isHex(String s, int expectedLength) {
    if (s.length != expectedLength) return false;
    for (var i = 0; i < expectedLength; i++) {
      final c = s.codeUnitAt(i);
      if (!((c >= 0x30 && c <= 0x39) ||
          (c >= 0x61 && c <= 0x66) ||
          (c >= 0x41 && c <= 0x46))) {
        return false;
      }
    }
    return true;
  }

  // ── 请求加密（客户端 → 服务端，兼容 Matrix 定制 Agent） ──────────────────

  /// AES-128-ECB 加密，返回 Base64 字符串。
  /// 用于 JSP/PHP 请求体加密。
  static String encryptEcb(String plaintext, String key) {
    if (plaintext.isEmpty) return '';
    final keyBytes = enc.Key(Uint8List.fromList(utf8.encode(key)));
    final encrypter = enc.Encrypter(enc.AES(keyBytes, mode: enc.AESMode.ecb));
    final encrypted = encrypter.encryptBytes(utf8.encode(plaintext));
    return base64.encode(encrypted.bytes);
  }

  // ── PHP 响应解密 ──────────────────────────────────────────────────────────

  /// PHP AES 响应解密：base64 → AES/CBC/zeroIV → 明文。
  ///
  /// PHP `openssl_encrypt($data, "AES128", $key)` =
  ///   AES-128-CBC + 零 IV + PKCS7 padding + base64 输出。
  /// 与 ECB 不同：单块数据 CBC 和 ECB 输出相同，多块数据从 Block 2 开始分叉。
  static String? tryDecryptPhp(String body, String key) {
    if (body.isEmpty) return '';
    try {
      final trimmed = body.replaceAll(RegExp(r'\s'), '');
      if (trimmed.length % 4 != 0) return null;
      final cipherBytes = base64.decode(trimmed);
      if (cipherBytes.isEmpty || cipherBytes.length % 16 != 0) return null;
      final keyBytes = enc.Key(Uint8List.fromList(utf8.encode(key)));
      final iv = enc.IV(Uint8List(16)); // 零 IV
      final encrypter = enc.Encrypter(enc.AES(keyBytes, mode: enc.AESMode.cbc));
      final decrypted = encrypter.decryptBytes(
        enc.Encrypted(cipherBytes),
        iv: iv,
      );
      return utf8.decode(decrypted);
    } on FormatException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// PHP XOR 响应解密：raw bytes → XOR key[i+1&15] → 明文。
  ///
  /// 对标 `Crypt.DecryptForAsp`:
  ///   for (int i = 0; i < bs.length; i++)
  ///     bs[i] ^= key.getBytes()[i + 1 & 15];
  /// 只在解密结果看起来像 JSON 时才返回，避免把明文路径误当 XOR 密文。
  static String? tryDecryptPhpXor(Uint8List raw, String key) {
    if (raw.isEmpty) return null;
    try {
      final keyBytes = utf8.encode(key);
      final result = Uint8List(raw.length);
      for (var i = 0; i < raw.length; i++) {
        result[i] = raw[i] ^ keyBytes[(i + 1) & 15];
      }
      final text = utf8.decode(result);
      // XOR 解密结果应该以 JSON 开头（标准响应）或包含 Behinder 特征
      if (text.startsWith('{') || text.startsWith('["')) return text;
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── JSP 响应解密 ──────────────────────────────────────────────────────────

  /// 对标 `Crypt.getMagicNum`:
  ///   Integer.parseInt(key.substring(0, 2), 16) % 16
  static int _magicNum(String key) {
    return int.parse(key.substring(0, 2), radix: 16) % 16;
  }

  /// JSP 标准 Agent 响应解密：base64 字符串 → base64 decode → AES/ECB → 明文。
  ///
  /// 对标 Agent 内置 Encrypt (Cmd.java / Echo.java):
  ///   Cipher.getInstance("AES/ECB/PKCS5Padding") → base64encode → getBytes()
  /// 响应体为纯 ASCII base64 文本。
  static String? tryDecryptJsp(String base64Body, String key) {
    if (base64Body.isEmpty) return '';
    try {
      final trimmed = base64Body.replaceAll(RegExp(r'\s'), '');
      if (trimmed.length % 4 != 0) return null;
      final cipherBytes = base64.decode(trimmed);
      if (cipherBytes.isEmpty || cipherBytes.length % 16 != 0) return null;
      final keyBytes = enc.Key(Uint8List.fromList(utf8.encode(key)));
      final encrypter = enc.Encrypter(enc.AES(keyBytes, mode: enc.AESMode.ecb));
      return utf8.decode(encrypter.decryptBytes(enc.Encrypted(cipherBytes)));
    } on FormatException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// JSP `aes_with_magic` 协议响应解密：raw bytes → 剥离末尾 magicNum 字节 →
  /// 剩余为 base64 字符串 → base64 decode → AES/ECB → 明文。
  ///
  /// 对标 TransProtocol `aes_with_magic` Encrypt:
  ///   base64(AES/ECB(json)) + random magic tail → output.toByteArray()
  static String? tryDecryptJspWithMagic(Uint8List raw, String key) {
    if (raw.isEmpty) return null;
    try {
      final magic = _magicNum(key);
      if (magic <= 0) return null; // 无 magic → 走 tryDecryptJsp
      final stripped = raw.sublist(0, raw.length - magic);
      // 剩余部分是 ASCII base64 文本
      final b64 = utf8.decode(stripped);
      return tryDecryptJsp(b64, key);
    } catch (_) {
      return null;
    }
  }

  // ── 兼容旧版 Matrix Agent ────────────────────────────────────────────────

  /// Matrix 旧版 Agent 可能返回 base64(AES/ECB)（与请求加密对称）。
  /// 当标准解密失败时尝试此路径。
  /// 解密结果需包含可打印 ASCII 才返回，避免把明文误解密。
  static String? tryDecryptLegacyMatrix(String body, String key) {
    if (body.isEmpty) return '';
    try {
      final trimmed = body.replaceAll(RegExp(r'\s'), '');
      if (trimmed.length % 4 != 0) return null;
      final cipherBytes = base64.decode(trimmed);
      if (cipherBytes.isEmpty || cipherBytes.length % 16 != 0) return null;
      final keyBytes = enc.Key(Uint8List.fromList(utf8.encode(key)));
      final encrypter = enc.Encrypter(enc.AES(keyBytes, mode: enc.AESMode.ecb));
      final decrypted = encrypter.decryptBytes(enc.Encrypted(cipherBytes));
      final text = utf8.decode(decrypted, allowMalformed: true);
      // 结果必须主要是可打印字符（ASCII 32-126 或常见 Unicode）
      final printable = text.codeUnits.where((c) => c >= 32 && c <= 126).length;
      if (printable < text.length * 0.8) return null;
      return text;
    } catch (_) {
      return null;
    }
  }

  // ── 响应提取 ──────────────────────────────────────────────────────────────

  /// 从解密后的响应文本中提取实际输出。
  ///
  /// 标准 Behinder 响应格式：`{"status":"base64", "msg":"base64(输出)"}`
  /// Matrix 旧版 Agent 直接返回纯文本。
  static String extractResponse(String decrypted) {
    if (decrypted.isEmpty) return '';
    try {
      final json = jsonDecode(decrypted);
      if (json is Map<String, dynamic>) {
        final msg = json['msg'];
        if (msg is String && msg.isNotEmpty) {
          try {
            return utf8.decode(base64.decode(msg));
          } catch (_) {
            return msg;
          }
        }
        final status = json['status'];
        if (status is String && status.isNotEmpty) {
          try {
            return utf8.decode(base64.decode(status));
          } catch (_) {
            return status;
          }
        }
      }
    } on FormatException {
      // 不是 JSON → 直接返回
    }
    return decrypted;
  }
}
