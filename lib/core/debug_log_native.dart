import 'dart:io';

/// 纯 Dart VM / 非 Web 环境始终为 false。
const bool kIsWeb = false;

/// 纯 Dart VM 环境：输出到 stderr，避免污染 stdout（MCP 协议走 stdout）。
void debugLog(String message, {bool wrap = true}) {
  stderr.writeln(message);
}
