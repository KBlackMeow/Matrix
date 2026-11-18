import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../errors/app_error.dart';
import 'http_result.dart';

class MultipartFormFile {
  const MultipartFormFile({
    required this.field,
    required this.filename,
    required this.content,
  });

  final String field;
  final String filename;
  final String content;
}

/// 探测类请求在无法拿到响应时抛出，让调用方把"没测通"与"目标不存在漏洞"区分开。
class HttpProbeException implements Exception {
  HttpProbeException(this.message);
  final String message;
  @override
  String toString() => message;
}

class MatrixHttpClient {
  MatrixHttpClient({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 10),
    this.allowBadCertificate = false,
  });

  final String baseUrl;
  final Duration timeout;
  final bool allowBadCertificate;

  String get _base =>
      baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  Uri _buildUri(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Uri.parse(path);
    }
    if (path.startsWith('/')) {
      return Uri.parse('$_base$path');
    }
    return Uri.parse('$_base/$path');
  }

  http.Client _client() {
    if (!allowBadCertificate) return http.Client();
    final io = HttpClient()
      ..badCertificateCallback = (_, __, ___) => true;
    return IOClient(io);
  }

  /// 与 [get] 相同，但网络层失败（连接拒绝/超时/TLS）时抛出 [HttpProbeException]。
  ///
  /// 注意：HTTP 4xx/5xx 不算失败——它们仍是可判定的响应。
  Future<HttpResult> getOrThrow(
    String path, {
    Map<String, String>? headers,
  }) async {
    final result = await get(path, headers: headers);
    if (!result.isOk) {
      throw HttpProbeException(result.error?.toString() ?? 'no response');
    }
    return result;
  }

  Future<HttpResult> get(
    String path, {
    Map<String, String>? headers,
  }) async {
    final client = _client();
    try {
      final res = await client
          .get(
            _buildUri(path),
            headers: headers,
          )
          .timeout(timeout);
      return HttpResult(
        statusCode: res.statusCode,
        body: res.body,
        headers: res.headers.map(
          (k, v) => MapEntry(k.toLowerCase(), v),
        ),
      );
    } on SocketException catch (e) {
      return HttpResult(
        error: NetworkError('Network error: ${e.message}', cause: e),
      );
    } on HttpException catch (e) {
      return HttpResult(
        error: NetworkError('HTTP error: ${e.message}', cause: e),
      );
    } on HandshakeException catch (e) {
      return HttpResult(
        error: NetworkError('TLS handshake failed', cause: e),
      );
    } on TimeoutException catch (e) {
      return HttpResult(
        error: TimeoutError('Request timed out', cause: e),
      );
    } catch (e) {
      return HttpResult(
        error: UnexpectedError('Unexpected error: $e', cause: e),
      );
    } finally {
      client.close();
    }
  }

  /// 与 [post] 相同，但网络层失败时抛出 [HttpProbeException]。
  Future<HttpResult> postOrThrow(
    String path, {
    Map<String, String>? headers,
    String? body,
    Map<String, String>? form,
  }) async {
    final result = await post(
      path,
      headers: headers,
      body: body,
      form: form,
    );
    if (!result.isOk) {
      throw HttpProbeException(result.error?.toString() ?? 'no response');
    }
    return result;
  }

  Future<HttpResult> post(
    String path, {
    Map<String, String>? headers,
    String? body,
    Map<String, String>? form,
  }) async {
    final client = _client();
    try {
      final uri = _buildUri(path);
      final res = await client
          .post(
            uri,
            headers: headers,
            body: form ?? body,
          )
          .timeout(timeout);
      return HttpResult(
        statusCode: res.statusCode,
        body: res.body,
        headers: res.headers.map(
          (k, v) => MapEntry(k.toLowerCase(), v),
        ),
      );
    } on SocketException catch (e) {
      return HttpResult(
        error: NetworkError('Network error: ${e.message}', cause: e),
      );
    } on HttpException catch (e) {
      return HttpResult(
        error: NetworkError('HTTP error: ${e.message}', cause: e),
      );
    } on HandshakeException catch (e) {
      return HttpResult(
        error: NetworkError('TLS handshake failed', cause: e),
      );
    } on TimeoutException catch (e) {
      return HttpResult(
        error: TimeoutError('Request timed out', cause: e),
      );
    } catch (e) {
      return HttpResult(
        error: UnexpectedError('Unexpected error: $e', cause: e),
      );
    } finally {
      client.close();
    }
  }

  Future<HttpResult> put(
    String path, {
    Map<String, String>? headers,
    String? body,
  }) async {
    final client = _client();
    try {
      final res = await client
          .put(
            _buildUri(path),
            headers: headers,
            body: body,
          )
          .timeout(timeout);
      return HttpResult(
        statusCode: res.statusCode,
        body: res.body,
        headers: res.headers.map(
          (k, v) => MapEntry(k.toLowerCase(), v),
        ),
      );
    } on SocketException catch (e) {
      return HttpResult(
        error: NetworkError('Network error: ${e.message}', cause: e),
      );
    } on HttpException catch (e) {
      return HttpResult(
        error: NetworkError('HTTP error: ${e.message}', cause: e),
      );
    } on HandshakeException catch (e) {
      return HttpResult(
        error: NetworkError('TLS handshake failed', cause: e),
      );
    } on TimeoutException catch (e) {
      return HttpResult(
        error: TimeoutError('Request timed out', cause: e),
      );
    } catch (e) {
      return HttpResult(
        error: UnexpectedError('Unexpected error: $e', cause: e),
      );
    } finally {
      client.close();
    }
  }

  Future<HttpResult> postMultipart(
    String path, {
    Map<String, String>? fields,
    required List<MultipartFormFile> files,
    Map<String, String>? headers,
  }) async {
    final client = _client();
    try {
      final uri = _buildUri(path);
      final request = http.MultipartRequest('POST', uri);

      if (headers != null && headers.isNotEmpty) {
        request.headers.addAll(headers);
      }
      if (fields != null && fields.isNotEmpty) {
        request.fields.addAll(fields);
      }

      for (final f in files) {
        request.files.add(
          http.MultipartFile.fromString(
            f.field,
            f.content,
            filename: f.filename,
          ),
        );
      }

      final streamedResponse = await client.send(request);
      final response = await http.Response.fromStream(streamedResponse);

      return HttpResult(
        statusCode: response.statusCode,
        body: response.body,
        headers: response.headers.map(
          (k, v) => MapEntry(k.toLowerCase(), v),
        ),
      );
    } on SocketException catch (e) {
      return HttpResult(
        error: NetworkError('Network error: ${e.message}', cause: e),
      );
    } on HttpException catch (e) {
      return HttpResult(
        error: NetworkError('HTTP error: ${e.message}', cause: e),
      );
    } on HandshakeException catch (e) {
      return HttpResult(
        error: NetworkError('TLS handshake failed', cause: e),
      );
    } on TimeoutException catch (e) {
      return HttpResult(
        error: TimeoutError('Request timed out', cause: e),
      );
    } catch (e) {
      return HttpResult(
        error: UnexpectedError('Unexpected error: $e', cause: e),
      );
    } finally {
      client.close();
    }
  }
}

