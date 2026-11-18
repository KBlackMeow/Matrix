import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

/// WebShell 口令 / Godzilla 密钥 / FRP token 的静态加密。
///
/// 设计：
/// - AES-256-CBC（随机 IV）+ HMAC-SHA256（encrypt-then-MAC）；
/// - 密文带 `enc:v1:` 前缀，历史明文记录可原样读取，实现平滑迁移；
/// - 主密钥 32 字节，优先存 macOS Keychain（`security` CLI），不可用时退回
///   `~/.matrix/credentials.key`（0600）。
///
/// 边界（不要误认为它是保险箱）：
/// - 只能防"数据库文件被单独拷走/误上传"这类泄漏；若攻击者能读整个用户目录，
///   仍可能拿到密钥文件。真正更强的方案是 sqlcipher + Keychain 会话密钥。
/// - 初始化失败时整体降级为直通（不加密），避免把库写坏；此时 [isReady] 为 false。
class CredentialCipher {
  CredentialCipher.withKey(List<int> key)
    : assert(key.length == 32, 'master key 必须是 32 字节'),
      _key = Uint8List.fromList(key),
      _macKey = Hmac(sha256, key)
          .convert(utf8.encode('matrix-credential-mac-v1'))
          .bytes;

  static const String prefix = 'enc:v1:';

  static const String _keychainService = 'Matrix.Credentials';
  static const String _keychainAccount = 'matrix';

  final Uint8List _key;
  final List<int> _macKey;

  static CredentialCipher? _instance;

  /// 加密器是否就绪；未就绪时所有加解密方法直通。
  static bool get isReady => _instance != null;

  static CredentialCipher? get instance => _instance;

  /// 读取/生成主密钥并启用加密。
  ///
  /// [keyFilePath] 用于测试或自定义部署；默认 `~/.matrix/credentials.key`。
  /// [useKeychain] 关闭后只使用密钥文件。
  static Future<CredentialCipher?> initialize({
    String? keyFilePath,
    bool useKeychain = true,
  }) async {
    try {
      final path = keyFilePath ?? await _defaultKeyFilePath();
      var key = useKeychain && Platform.isMacOS
          ? await _readKeychainKey()
          : null;

      if (key == null) {
        key = await _readKeyFile(path);
        if (key != null && useKeychain && Platform.isMacOS) {
          await _writeKeychainKey(key); // 补写 Keychain，便于下次优先读
        }
      }

      if (key == null) {
        key = _randomKey();
        await _writeKeyFile(path, key);
        if (useKeychain && Platform.isMacOS) {
          await _writeKeychainKey(key);
        }
      }

      if (key.length != 32) return null;
      return _instance = CredentialCipher.withKey(key);
    } catch (_) {
      return null;
    }
  }

  /// 测试/降级用：直接设置实例。
  static void setInstance(CredentialCipher? cipher) => _instance = cipher;

  static bool isEncrypted(String? value) =>
      value != null && value.startsWith(prefix);

  /// 未初始化时原样返回，保证旧版本数据与降级路径可用。
  static String? encryptIfReady(String? plain) {
    if (plain == null || plain.isEmpty) return plain;
    final cipher = _instance;
    if (cipher == null) return plain;
    if (isEncrypted(plain)) return plain; // 幂等：已是密文不再二次加密
    return cipher.encrypt(plain);
  }

  static String? decryptIfReady(String? stored) {
    if (stored == null || stored.isEmpty) return stored;
    final cipher = _instance;
    if (cipher == null) return stored;
    return cipher.decrypt(stored);
  }

  String encrypt(String plain) {
    final iv = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(enc.AES(enc.Key(_key), mode: enc.AESMode.cbc));
    final body = encrypter.encryptBytes(utf8.encode(plain), iv: iv).bytes;
    final mac = Hmac(sha256, _macKey).convert(<int>[...iv.bytes, ...body]).bytes;
    return '$prefix${base64.encode(<int>[...iv.bytes, ...body, ...mac])}';
  }

  /// 解密失败（密钥不匹配/数据损坏）时返回原值，避免静默丢数据。
  String decrypt(String stored) {
    if (!isEncrypted(stored)) return stored;
    try {
      final raw = base64.decode(stored.substring(prefix.length));
      if (raw.length < 16 + 32) return stored;
      final iv = raw.sublist(0, 16);
      final body = raw.sublist(16, raw.length - 32);
      final mac = raw.sublist(raw.length - 32);
      final expected = Hmac(sha256, _macKey).convert(<int>[...iv, ...body]).bytes;
      if (!_constantTimeEquals(mac, expected)) return stored;
      final encrypter = enc.Encrypter(
        enc.AES(enc.Key(_key), mode: enc.AESMode.cbc),
      );
      return utf8.decode(
        encrypter.decryptBytes(enc.Encrypted(Uint8List.fromList(body)),
            iv: enc.IV(Uint8List.fromList(iv))),
      );
    } catch (_) {
      return stored;
    }
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  static List<int> _randomKey() {
    final rng = Random.secure();
    return List<int>.generate(32, (_) => rng.nextInt(256));
  }

  static Future<String> _defaultKeyFilePath() async {
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      return '$home${Platform.pathSeparator}.matrix'
          '${Platform.pathSeparator}credentials.key';
    }
    return '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'matrix_credentials.key';
  }

  static Future<List<int>?> _readKeyFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final text = (await file.readAsString()).trim();
      if (text.isEmpty) return null;
      final key = base64.decode(text);
      return key.length == 32 ? key : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeKeyFile(String path, List<int> key) async {
    try {
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsString(base64.encode(key), flush: true);
      if (Platform.isMacOS || Platform.isLinux) {
        await Process.run('chmod', <String>['600', path]);
      }
    } catch (_) {
      // 写不了密钥文件时仍可继续：Keychain 可能已保存。
    }
  }

  static Future<List<int>?> _readKeychainKey() async {
    try {
      // 超时保护：钥匙串被锁时 `security` 可能弹窗等待，不能卡住启动。
      final result = await Process.run('security', <String>[
        'find-generic-password',
        '-s',
        _keychainService,
        '-a',
        _keychainAccount,
        '-w',
      ]).timeout(const Duration(seconds: 3));
      if (result.exitCode != 0) return null;
      final text = '${result.stdout}'.trim();
      if (text.isEmpty) return null;
      final key = base64.decode(text);
      return key.length == 32 ? key : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeKeychainKey(List<int> key) async {
    try {
      await Process.run('security', <String>[
        'add-generic-password',
        '-U',
        '-s',
        _keychainService,
        '-a',
        _keychainAccount,
        '-w',
        base64.encode(key),
      ]).timeout(const Duration(seconds: 3));
    } catch (_) {
      // Keychain 不可用时退回密钥文件。
    }
  }
}
