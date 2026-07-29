import 'package:flutter/foundation.dart';

/// Flutter 环境：使用 debugPrint（自动节流输出）。
void debugLog(String message, {bool wrap = true}) {
  debugPrint(message, wrapWidth: wrap ? null : 99999);
}
