import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/core/asset_loader.dart';

/// 内置默认 Godzilla 马：确保 assets 存在、账号一致、没有残留占位符。
///
/// 这些文件由 `tool/godzilla_engine/render_default_shells.dart` 生成，
/// 经 `SeedService`（sinceVersion 17）写入载荷库。
const _defaults = <String, String>{
  'assets/defaults/payloads/godzilla/godzilla_php_xor_base64.php':
      'PHP_XOR_BASE64',
  'assets/defaults/payloads/godzilla/godzilla_php_xor_raw.php': 'PHP_XOR_RAW',
  'assets/defaults/payloads/godzilla/godzilla_php_eval_xor_base64.php':
      'PHP_EVAL_XOR_BASE64',
  'assets/defaults/payloads/godzilla/godzilla_jsp_aes_base64.jsp':
      'JAVA_AES_BASE64',
  'assets/defaults/payloads/godzilla/godzilla_jsp_aes_raw.jsp': 'JAVA_AES_RAW',
  'assets/defaults/payloads/godzilla/godzilla_aspx_aes_base64.aspx':
      'CSHAP_AES_BASE64',
  'assets/defaults/payloads/godzilla/godzilla_asp_xor_base64.asp':
      'ASP_XOR_BASE64',
  'assets/defaults/payloads/godzilla/godzilla_asp_raw.asp': 'ASP_RAW',
  'assets/defaults/payloads/godzilla/godzilla_csharp_asmx_aes_base64.asmx':
      'CSHAP_ASMX_AES_BASE64',
  'assets/defaults/payloads/godzilla/godzilla_csharp_eval_aes_base64.aspx':
      'CSHAP_EVAL_AES_BASE64',
  'assets/defaults/payloads/godzilla/godzilla_asp_eval_base64.asp':
      'ASP_EVAL_BASE64',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('内置默认 Godzilla 马', () {
    test('覆盖 4 种架构、11 个常用加密器', () {
      expect(_defaults, hasLength(11));
      final extensions = _defaults.keys.map((p) => p.split('.').last).toSet();
      expect(extensions, {'php', 'jsp', 'aspx', 'asmx', 'asp'});
    });

    for (final entry in _defaults.entries) {
      test('${entry.key.split('/').last} 使用默认账号且无占位符', () async {
        final content = await loadAssetString(entry.key);
        expect(content.trim(), isNotEmpty);
        // 每类壳实际包含的默认值不同，显式列出，避免“猜”出来的断言。
        final expectsKey16 = entry.value == 'ASP_RAW'
            ? false
            : !entry.value.contains('EVAL');
        final expectsPassword = !entry.value.endsWith('_RAW');
        if (expectsKey16) {
          expect(
            content,
            contains('3c6e0b8a9c15224a'),
            reason: '${entry.value} 应内置 key16',
          );
        }
        if (expectsPassword) {
          expect(
            content,
            contains('mAtrix_911'),
            reason: '${entry.value} 应内置默认密码',
          );
        }
        expect(RegExp(r'\{\{[A-Z_]+\}\}').hasMatch(content), isFalse);
        // PHP 壳必须闭合（用户反馈过“看起来没结束”）。
        if (entry.key.endsWith('.php')) {
          expect(
            content.trimRight().endsWith('?>'),
            isTrue,
            reason: '${entry.key} 应以 ?> 闭合',
          );
        }
      });
    }
  });
}
