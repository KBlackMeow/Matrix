/// 条件导出：Flutter 环境使用 debugPrint，纯 Dart 环境使用 stderr。
///
/// 使用 [dart.library.ui] 区分 Flutter 和纯 Dart VM。
export 'debug_log_native.dart'
    if (dart.library.ui) 'debug_log_flutter.dart';
