import '../errors/app_error.dart';

class HttpResult {
  const HttpResult({
    this.statusCode,
    this.body,
    this.headers = const {},
    this.error,
  });

  final int? statusCode;
  final String? body;
  final Map<String, String> headers;
  final AppError? error;

  bool get isOk => error == null && statusCode != null;

  bool get hasBody => body != null && body!.isNotEmpty;
}

