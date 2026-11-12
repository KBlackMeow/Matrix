import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:encrypt/encrypt.dart' as enc;

import '../../connectors/godzilla/godzilla_variant.dart';
import 'godzilla_codec.dart';

/// Godzilla 客户端加解密。
///
/// 协议摘要（已对真实 `godzilla.jsp` 验证）：
///
/// ```text
/// key16          = lower(hex(MD5(secretKey)))[0:16]     // 16 个 ASCII 字符
/// password       = HTTP 参数名
/// request body   = <password>=<URLEncode(Base64(cipher(params)))>
/// response body  = <LEFT><Base64(cipher(result))><RIGHT>
/// md5            = lower(hex(MD5(password + key16)))
/// LEFT/RIGHT     = md5[0:16]/md5[16:32]（PHP 小写、Java/C# 大写）
///                  md5[0:6]/md5[20:26]（经典 ASP）
/// ```
class GodzillaCrypto {
  GodzillaCrypto._();

  static String md5Hex(String input) =>
      crypto.md5.convert(utf8.encode(input)).toString();

  /// `secretKey` 为空时回退到 Godzilla 的常见默认值 `key`。
  static String deriveKey16(String secretKey) {
    final trimmed = secretKey.trim();
    final effective = trimmed.isEmpty ? 'key' : trimmed;
    return md5Hex(effective).substring(0, 16);
  }

  static ({String left, String right}) markers({
    required String password,
    required String key16,
    required GodzillaMarkerStyle style,
  }) {
    final md5 = md5Hex('$password$key16');
    if (style == GodzillaMarkerStyle.lowerAsp6) {
      return (left: md5.substring(0, 6), right: md5.substring(20, 26));
    }
    final left = md5.substring(0, 16);
    final right = md5.substring(16);
    if (style == GodzillaMarkerStyle.upper16) {
      return (left: left.toUpperCase(), right: right.toUpperCase());
    }
    return (left: left, right: right);
  }

  /// 响应标记的所有候选。
  ///
  /// Java 生成的 shell 使用
  /// `new BigInteger(1, digest).toString(16).toUpperCase()`，
  /// 当摘要首 nibble 为 0 时会丢掉前导零，实际发出的标记是
  /// `md5[1:17]` + `md5[17:32]`。这里同时给出两种切分，解析时逐个尝试。
  static List<({String left, String right})> markerCandidates({
    required String password,
    required String key16,
    required GodzillaMarkerStyle style,
  }) {
    final md5 = md5Hex('$password$key16');
    final out = <({String left, String right})>[];

    void add(String left, String right) {
      if (left.isEmpty || right.isEmpty) return;
      if (out.any((e) => e.left == left && e.right == right)) return;
      out.add((left: left, right: right));
    }

    if (style == GodzillaMarkerStyle.lowerAsp6) {
      add(md5.substring(0, 6), md5.substring(20, 26));
      return out;
    }

    final upper = style == GodzillaMarkerStyle.upper16;
    String f(String s) => upper ? s.toUpperCase() : s;

    add(f(md5.substring(0, 16)), f(md5.substring(16)));
    add(f(md5.substring(1, 17)), f(md5.substring(17)));
    return out;
  }

  // ── AES ────────────────────────────────────────────────────────────────

  static Uint8List aesEcbEncrypt(Uint8List data, String key16) {
    final encrypter = enc.Encrypter(
      enc.AES(
        enc.Key(Uint8List.fromList(utf8.encode(key16))),
        mode: enc.AESMode.ecb,
      ),
    );
    return Uint8List.fromList(encrypter.encryptBytes(data).bytes);
  }

  static Uint8List aesEcbDecrypt(Uint8List data, String key16) {
    final encrypter = enc.Encrypter(
      enc.AES(
        enc.Key(Uint8List.fromList(utf8.encode(key16))),
        mode: enc.AESMode.ecb,
      ),
    );
    return Uint8List.fromList(
      encrypter.decryptBytes(enc.Encrypted(data)),
    );
  }

  static Uint8List aesCbcEncrypt(Uint8List data, String key16) {
    final keyBytes = Uint8List.fromList(utf8.encode(key16));
    final encrypter = enc.Encrypter(
      enc.AES(enc.Key(keyBytes), mode: enc.AESMode.cbc),
    );
    return Uint8List.fromList(
      encrypter.encryptBytes(data, iv: enc.IV(keyBytes)).bytes,
    );
  }

  static Uint8List aesCbcDecrypt(Uint8List data, String key16) {
    final keyBytes = Uint8List.fromList(utf8.encode(key16));
    final encrypter = enc.Encrypter(
      enc.AES(enc.Key(keyBytes), mode: enc.AESMode.cbc),
    );
    return Uint8List.fromList(
      encrypter.decryptBytes(enc.Encrypted(data), iv: enc.IV(keyBytes)),
    );
  }

  // ── XOR ────────────────────────────────────────────────────────────────

  /// `key16` 是 16 个 ASCII 字符（不是 16 个原始字节）。
  static Uint8List xor(Uint8List data, String key16) {
    final keyBytes = utf8.encode(key16);
    final out = Uint8List(data.length);
    for (var i = 0; i < data.length; i++) {
      out[i] = data[i] ^ keyBytes[(i + 1) & 15];
    }
    return out;
  }

  // ── 加/解密分发 ─────────────────────────────────────────────────────────

  static Uint8List encrypt(
    Uint8List data,
    String key16,
    GodzillaCipher cipher,
  ) {
    switch (cipher) {
      case GodzillaCipher.aesEcb:
        return aesEcbEncrypt(data, key16);
      case GodzillaCipher.aesCbcKeyIv:
        return aesCbcEncrypt(data, key16);
      case GodzillaCipher.xor:
        return xor(data, key16);
      case GodzillaCipher.none:
        return data;
    }
  }

  static Uint8List decrypt(
    Uint8List data,
    String key16,
    GodzillaCipher cipher,
  ) {
    switch (cipher) {
      case GodzillaCipher.aesEcb:
        return aesEcbDecrypt(data, key16);
      case GodzillaCipher.aesCbcKeyIv:
        return aesCbcDecrypt(data, key16);
      case GodzillaCipher.xor:
        return xor(data, key16);
      case GodzillaCipher.none:
        return data;
    }
  }

  // ── 响应提取 ────────────────────────────────────────────────────────────

  /// 从响应体提取明文；失败返回 `null`，不抛异常。
  ///
  /// - `GodzillaWire.formBase64`：定位标记 → base64 解码 → 解密
  /// - `GodzillaWire.raw`：整个响应体就是密文
  static Uint8List? extractResponse({
    required Uint8List rawBody,
    required String password,
    required String key16,
    required GodzillaVariant variant,
  }) {
    if (rawBody.isEmpty) return null;
    if (variant.wire == GodzillaWire.raw) {
      return extractRawResponse(
        rawBody: rawBody,
        key16: key16,
        variant: variant,
      );
    }
    final text = latin1.decode(rawBody, allowInvalid: true);
    final candidates = markerCandidates(
      password: password,
      key16: key16,
      style: variant.markerStyle,
    );

    for (final marker in candidates) {
      final start = text.indexOf(marker.left);
      if (start < 0) continue;
      final end = text.indexOf(marker.right, start + marker.left.length);
      if (end < 0) continue;

      final b64 = text
          .substring(start + marker.left.length, end)
          .replaceAll(RegExp(r'\s'), '');
      if (b64.isEmpty || b64.length % 4 != 0) continue;

      Uint8List cipherBytes;
      try {
        cipherBytes = Uint8List.fromList(base64.decode(b64));
      } catch (_) {
        continue;
      }
      if (cipherBytes.isEmpty || cipherBytes.length % 16 != 0) {
        // XOR 变体不要求 16 字节对齐；AES 变体必须。
        if (variant.cipher != GodzillaCipher.xor) continue;
      }

      Uint8List plain;
      try {
        plain = decrypt(cipherBytes, key16, variant.cipher);
      } catch (_) {
        continue;
      }
      return variant.gunzipResponse ? GodzillaCodec.maybeGunzip(plain) : plain;
    }
    return null;
  }

  /// RAW 变体：响应体是 `cipher(result)`，没有标记也没有 base64。
  static Uint8List? extractRawResponse({
    required Uint8List rawBody,
    required String key16,
    required GodzillaVariant variant,
  }) {
    if (rawBody.isEmpty) return null;
    Uint8List plain;
    try {
      plain = decrypt(rawBody, key16, variant.cipher);
    } catch (_) {
      return null;
    }
    return variant.gunzipResponse ? GodzillaCodec.maybeGunzip(plain) : plain;
  }
}
