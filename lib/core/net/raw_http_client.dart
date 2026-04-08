import 'dart:async';
import 'dart:convert';
import 'dart:io';

class RawHttpRequest {
  RawHttpRequest({
    required this.method,
    required this.rawPath,
    this.headers = const {},
    this.body = '',
  });

  final String method;
  final String rawPath;
  final Map<String, String> headers;
  final String body;
}

class RawHttpResponse {
  RawHttpResponse({
    required this.raw,
    required this.body,
  });

  final String raw;
  final String body;
}

class RawHttpClient {
  const RawHttpClient({
    this.timeout = const Duration(seconds: 10),
    this.allowBadCertificate = true,
  });

  final Duration timeout;
  final bool allowBadCertificate;

  Future<RawHttpResponse?> send({
    required String baseUrl,
    required RawHttpRequest request,
  }) async {
    final base = Uri.parse(baseUrl);
    final host = base.host;
    if (host.isEmpty) return null;
    final isHttps = base.scheme == 'https';
    final port = base.hasPort ? base.port : (isHttps ? 443 : 80);

    final payload = request.body;
    final reqHeaders = <String, String>{
      'Host': base.hasPort ? '$host:$port' : host,
      'Connection': 'close',
      ...request.headers,
    };
    if (payload.isNotEmpty) {
      reqHeaders['Content-Length'] = utf8.encode(payload).length.toString();
    }
    final headerText = reqHeaders.entries
        .map((e) => '${e.key}: ${e.value}')
        .join('\r\n');
    final buf = StringBuffer()
      ..write('${request.method} ${request.rawPath} HTTP/1.1\r\n')
      ..write('$headerText\r\n\r\n')
      ..write(payload);

    Socket? socket;
    try {
      if (isHttps) {
        socket = await SecureSocket.connect(
          host,
          port,
          timeout: timeout,
          onBadCertificate: allowBadCertificate ? (_) => true : null,
        );
      } else {
        socket = await Socket.connect(host, port, timeout: timeout);
      }
      socket.write(buf.toString());
      await socket.flush();

      final bytes = await socket
          .cast<List<int>>()
          .timeout(timeout)
          .expand((chunk) => chunk)
          .toList();
      final text = utf8.decode(bytes, allowMalformed: true);
      final idx = text.indexOf('\r\n\r\n');
      final body = idx >= 0 ? text.substring(idx + 4) : text;
      return RawHttpResponse(raw: text, body: body);
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    } finally {
      try {
        await socket?.close();
      } catch (_) {}
    }
  }
}

