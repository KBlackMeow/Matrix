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

