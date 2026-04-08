sealed class AppError {
  const AppError(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

class NetworkError extends AppError {
  const NetworkError(String message, {Object? cause})
      : super(message, cause: cause);
}

class TimeoutError extends AppError {
  const TimeoutError(String message, {Object? cause})
      : super(message, cause: cause);
}

class UnexpectedError extends AppError {
  const UnexpectedError(String message, {Object? cause})
      : super(message, cause: cause);
}

