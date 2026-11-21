/// Godzilla 变体元数据。
///
/// 只描述“协议长什么样”，不包含任何网络/加解密实现，避免与
/// `godzilla_crypto.dart` 形成循环依赖。
enum GodzillaCipher {
  /// AES/ECB/PKCS5（JSP）
  aesEcb,

  /// AES/CBC/PKCS5，key 同时作为 IV（ASPX）
  aesCbcKeyIv,

  /// XOR，key 为 16 字符 ASCII，索引 `(i + 1) & 15`（PHP/ASP）
  xor,

  /// 不加密（`ASP_BASE64` / `ASP_RAW`）
  none,
}

/// 请求/响应的封装方式。
enum GodzillaWire {
  /// `pass=<urlencode(base64(cipher))>` 与 `<left><base64(cipher)><right>`
  formBase64,

  /// 请求体与响应体都是裸密文（Godzilla 的 `*_RAW` 变体）。
  raw,

  /// `PHP_EVAL_XOR_BASE64` 等 eval 变体：
  /// 每次请求都带一段“装载器源码”，由一句话壳 `eval($_POST[pass])` 执行。
  evalBase64,

  /// `CSHAP_ASMX_AES_BASE64`：请求体是 SOAP XML，不是表单。
  asmxBase64,

  /// `CSHAP_EVAL_AES_BASE64`：先发一段动态 eval 装载器，再发密文参数。
  csharpEval,

  /// `ASP_EVAL_BASE64`：连接密码字段放十六进制 eval 装载器，数据放 secretKey。
  aspEval,
}

enum GodzillaMarkerStyle {
  /// md5[0:16] + md5[16:32]，小写（PHP）
  lower16,

  /// md5[0:16] + md5[16:32]，大写（Java/C#）
  upper16,

  /// md5[0:6] + md5[20:26]，小写（经典 ASP）
  lowerAsp6,
}

/// Matrix 支持的首批 Godzilla 变体。
///
/// `connectorType` 与 `lib/connectors/connector_factory.dart` 中的
/// `connector_type` 一一对应。
enum GodzillaVariant {
  phpXorBase64(
    cryptionId: 'PHP_XOR_BASE64',
    connectorType: 'php_godzilla',
    language: 'php',
    label: 'PHP-GZ',
    cipher: GodzillaCipher.xor,
    markerStyle: GodzillaMarkerStyle.lower16,
    gzipRequest: false,
    gunzipResponse: true,
    wire: GodzillaWire.formBase64,
    engineAsset: 'data/godzilla/matrix_godzilla.php.b64',
    readFileMethod: 'readFileContent',
    execMode: GodzillaExecMode.cmdLine,
  ),
  phpXorRaw(
    cryptionId: 'PHP_XOR_RAW',
    connectorType: 'php_godzilla',
    language: 'php',
    label: 'PHP-GZR',
    cipher: GodzillaCipher.xor,
    markerStyle: GodzillaMarkerStyle.lower16,
    gzipRequest: false,
    gunzipResponse: true,
    wire: GodzillaWire.raw,
    engineAsset: 'data/godzilla/matrix_godzilla.php.b64',
    readFileMethod: 'readFileContent',
    execMode: GodzillaExecMode.cmdLine,
  ),
  phpEvalXorBase64(
    cryptionId: 'PHP_EVAL_XOR_BASE64',
    connectorType: 'php_godzilla',
    language: 'php',
    label: 'PHP-GZE',
    cipher: GodzillaCipher.xor,
    markerStyle: GodzillaMarkerStyle.lower16,
    gzipRequest: false,
    gunzipResponse: true,
    wire: GodzillaWire.evalBase64,
    evalLoaderAsset:
        'assets/defaults/payloads/godzilla_shells/php_eval_loader.php.tpl',
    // eval 变体的装载器用固定参数名 `mxdata` 收数据，标记也按它计算。
    markerPassword: 'mxdata',
    engineAsset: 'data/godzilla/matrix_godzilla.php.b64',
    readFileMethod: 'readFileContent',
    execMode: GodzillaExecMode.cmdLine,
  ),
  javaAesBase64(
    cryptionId: 'JAVA_AES_BASE64',
    connectorType: 'jsp_godzilla',
    language: 'jsp',
    label: 'JSP-GZ',
    cipher: GodzillaCipher.aesEcb,
    markerStyle: GodzillaMarkerStyle.upper16,
    gzipRequest: true,
    gunzipResponse: true,
    wire: GodzillaWire.formBase64,
    engineAsset: 'data/godzilla/matrix_godzilla.class.b64',
    readFileMethod: 'readFile',
    execMode: GodzillaExecMode.argArray,
  ),
  javaAesRaw(
    cryptionId: 'JAVA_AES_RAW',
    connectorType: 'jsp_godzilla',
    language: 'jsp',
    label: 'JSP-GZR',
    cipher: GodzillaCipher.aesEcb,
    markerStyle: GodzillaMarkerStyle.upper16,
    gzipRequest: true,
    gunzipResponse: true,
    wire: GodzillaWire.raw,
    engineAsset: 'data/godzilla/matrix_godzilla.class.b64',
    readFileMethod: 'readFile',
    execMode: GodzillaExecMode.argArray,
  ),
  csharpAesBase64(
    cryptionId: 'CSHAP_AES_BASE64',
    connectorType: 'aspx_godzilla',
    language: 'aspx',
    label: 'ASPX-GZ',
    cipher: GodzillaCipher.aesCbcKeyIv,
    markerStyle: GodzillaMarkerStyle.upper16,
    gzipRequest: true,
    gunzipResponse: true,
    wire: GodzillaWire.formBase64,
    engineAsset: 'data/godzilla/matrix_godzilla.dll.b64',
    // C# 引擎（官方与 Matrix 版本）用 readFile。
    readFileMethod: 'readFile',
    execMode: GodzillaExecMode.cmdLine,
  ),
  csharpAesRaw(
    cryptionId: 'CSHAP_AES_RAW',
    connectorType: 'aspx_godzilla',
    language: 'aspx',
    label: 'ASPX-GZR',
    cipher: GodzillaCipher.aesCbcKeyIv,
    markerStyle: GodzillaMarkerStyle.upper16,
    gzipRequest: true,
    gunzipResponse: true,
    wire: GodzillaWire.raw,
    engineAsset: 'data/godzilla/matrix_godzilla.dll.b64',
    readFileMethod: 'readFile',
    execMode: GodzillaExecMode.cmdLine,
  ),
  aspXorBase64(
    cryptionId: 'ASP_XOR_BASE64',
    connectorType: 'asp_godzilla',
    language: 'asp',
    label: 'ASP-GZ',
    cipher: GodzillaCipher.xor,
    markerStyle: GodzillaMarkerStyle.lowerAsp6,
    gzipRequest: false,
    gunzipResponse: false,
    wire: GodzillaWire.formBase64,
    engineAsset: 'data/godzilla/matrix_godzilla.asp.b64',
    readFileMethod: 'readFileContent',
    execMode: GodzillaExecMode.cmdLine,
  ),
  aspBase64(
    cryptionId: 'ASP_BASE64',
    connectorType: 'asp_godzilla',
    language: 'asp',
    label: 'ASP-GZ0',
    cipher: GodzillaCipher.none,
    markerStyle: GodzillaMarkerStyle.lowerAsp6,
    gzipRequest: false,
    gunzipResponse: false,
    wire: GodzillaWire.formBase64,
    engineAsset: 'data/godzilla/matrix_godzilla.asp.b64',
    readFileMethod: 'readFileContent',
    execMode: GodzillaExecMode.cmdLine,
  ),
  aspRaw(
    cryptionId: 'ASP_RAW',
    connectorType: 'asp_godzilla',
    language: 'asp',
    label: 'ASP-GZ0R',
    cipher: GodzillaCipher.none,
    markerStyle: GodzillaMarkerStyle.lowerAsp6,
    gzipRequest: false,
    gunzipResponse: false,
    wire: GodzillaWire.raw,
    engineAsset: 'data/godzilla/matrix_godzilla.asp.b64',
    readFileMethod: 'readFileContent',
    execMode: GodzillaExecMode.cmdLine,
  ),
  aspXorRaw(
    cryptionId: 'ASP_XOR_RAW',
    connectorType: 'asp_godzilla',
    language: 'asp',
    label: 'ASP-GZR',
    cipher: GodzillaCipher.xor,
    markerStyle: GodzillaMarkerStyle.lowerAsp6,
    gzipRequest: false,
    gunzipResponse: false,
    wire: GodzillaWire.raw,
    engineAsset: 'data/godzilla/matrix_godzilla.asp.b64',
    readFileMethod: 'readFileContent',
    execMode: GodzillaExecMode.cmdLine,
  ),
  csharpAsmxAesBase64(
    cryptionId: 'CSHAP_ASMX_AES_BASE64',
    connectorType: 'aspx_godzilla',
    language: 'aspx',
    label: 'ASPX-ASMX',
    cipher: GodzillaCipher.aesCbcKeyIv,
    markerStyle: GodzillaMarkerStyle.upper16,
    gzipRequest: false,
    gunzipResponse: false,
    wire: GodzillaWire.asmxBase64,
    requestTemplateAsset:
        'assets/defaults/payloads/godzilla_shells/asmx_request.xml.tpl',
    engineAsset: 'data/godzilla/matrix_godzilla.dll.b64',
    readFileMethod: 'readFile',
    execMode: GodzillaExecMode.cmdLine,
  ),
  csharpEvalAesBase64(
    cryptionId: 'CSHAP_EVAL_AES_BASE64',
    connectorType: 'aspx_godzilla',
    language: 'aspx',
    label: 'ASPX-EVAL',
    cipher: GodzillaCipher.aesCbcKeyIv,
    markerStyle: GodzillaMarkerStyle.upper16,
    gzipRequest: false,
    gunzipResponse: false,
    wire: GodzillaWire.csharpEval,
    evalLoaderAsset:
        'assets/defaults/payloads/godzilla_shells/csharp_eval_loader.cs.tpl',
    markerUsesSecretKey: true,
    engineAsset: 'data/godzilla/matrix_godzilla.dll.b64',
    readFileMethod: 'readFile',
    execMode: GodzillaExecMode.cmdLine,
  ),
  aspEvalBase64(
    cryptionId: 'ASP_EVAL_BASE64',
    connectorType: 'asp_godzilla',
    language: 'asp',
    label: 'ASP-EVAL',
    cipher: GodzillaCipher.none,
    markerStyle: GodzillaMarkerStyle.lowerAsp6,
    gzipRequest: false,
    gunzipResponse: false,
    wire: GodzillaWire.aspEval,
    aspEvalRequestAsset:
        'assets/defaults/payloads/godzilla_shells/asp_eval_request.vbs.tpl',
    aspEvalLoaderAsset:
        'assets/defaults/payloads/godzilla_shells/asp_eval_loader.asp.tpl',
    markerUsesSecretKey: true,
    markerKeyUsesDoubleHash: true,
    engineAsset: 'data/godzilla/matrix_godzilla.asp.b64',
    readFileMethod: 'readFileContent',
    execMode: GodzillaExecMode.cmdLine,
  );

  const GodzillaVariant({
    required this.cryptionId,
    required this.connectorType,
    required this.language,
    required this.label,
    required this.cipher,
    required this.markerStyle,
    required this.gzipRequest,
    required this.gunzipResponse,
    required this.wire,
    this.evalLoaderAsset,
    this.requestTemplateAsset,
    this.aspEvalRequestAsset,
    this.aspEvalLoaderAsset,
    this.markerPassword,
    this.markerUsesSecretKey = false,
    this.markerKeyUsesDoubleHash = false,
    required this.engineAsset,
    required this.readFileMethod,
    required this.execMode,
  });

  /// 上游加密器 ID（`PHP_XOR_BASE64` 等），也是 UI “加密器”下拉的值。
  final String cryptionId;

  /// 所属连接器（架构 + 协议），只有 4 个。
  final String connectorType;
  final String language;
  final String label;
  final GodzillaCipher cipher;
  final GodzillaMarkerStyle markerStyle;

  /// 请求参数是否需要先 gzip（Java/C# 必须，PHP 可省略，ASP 不支持）。
  final bool gzipRequest;

  /// 响应明文是否可能是 gzip（Java/C# 是，PHP 视 `gzencode`，ASP 否）。
  final bool gunzipResponse;

  /// 请求/响应封装方式（BASE64 表单 / 裸密文 / eval 装载器）。
  final GodzillaWire wire;

  /// eval 变体每次请求要发送的装载器模板（`{{PASS}}` 会被替换成 secretKey）。
  final String? evalLoaderAsset;

  /// ASMX 请求 XML 模板（含 `{pass}` / `{data}` 占位符）。
  final String? requestTemplateAsset;

  /// ASP_EVAL 的十六进制 eval 请求模板（含 `{hexCode}`）。
  final String? aspEvalRequestAsset;

  /// ASP_EVAL 的 ASP 装载器模板（含 `{pass}` / `{secretKey}` / 标记占位符）。
  final String? aspEvalLoaderAsset;

  /// 响应标记是否用 `secretKey` 而不是连接密码计算。
  final bool markerUsesSecretKey;

  /// ASP_EVAL 的标记 key 是 `MD5(MD5(secretKey)[0:16])[0:16]`（上游双重哈希）。
  final bool markerKeyUsesDoubleHash;

  /// 响应标记计算时替代连接密码的固定值。
  ///
  /// `PHP_EVAL_XOR_BASE64` 的装载器用固定参数名 `mxdata` 收数据，
  /// 它的 `md5(pass + key16)` 里 `pass` 就是 `mxdata`。
  final String? markerPassword;

  /// 服务端 payload 引擎的 base64 资产路径。
  final String engineAsset;

  /// 读文件使用的 methodName（Java 用 `readFile`，其余用 `readFileContent`）。
  final String readFileMethod;

  /// 执行命令的传参方式。
  final GodzillaExecMode execMode;

  /// 老的“连接器类型 = 加密器”映射（用于数据库旧值兼容）。
  static GodzillaVariant? fromConnectorType(String connectorType) {
    for (final v in values) {
      if (v.connectorType == connectorType) return v;
    }
    return null;
  }

  static GodzillaVariant? fromCryptionId(String cryptionId) {
    final id = cryptionId.trim().toUpperCase();
    if (id.isEmpty) return null;
    for (final v in values) {
      if (v.cryptionId.toUpperCase() == id) return v;
    }
    return null;
  }

  static bool isGodzillaConnector(String connectorType) =>
      connectorType.contains('godzilla');

  /// 某架构下可选的加密器（UI 下拉）。
  static List<GodzillaVariant> forConnector(String connectorType) =>
      values.where((v) => v.connectorType == connectorType).toList();

  /// 解析实际使用的变体：优先 `cryption`，为空/不匹配时退回默认（BASE64）。
  static GodzillaVariant resolveFor(String connectorType, String? cryption) {
    final byCryption = fromCryptionId(cryption ?? '');
    if (byCryption != null && byCryption.connectorType == connectorType) {
      return byCryption;
    }
    for (final v in values) {
      if (v.connectorType == connectorType) return v;
    }
    return values.first;
  }
}

enum GodzillaExecMode {
  /// Java：`argsCount` + `arg-0` … `arg-N`
  argArray,

  /// PHP / C# / ASP：`cmdLine`
  cmdLine,
}
