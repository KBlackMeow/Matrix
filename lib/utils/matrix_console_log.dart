// 终端日志（`flutter run` 窗口）：带统一时间戳，便于与界面上的简短提示对照排查。

String matrixConsoleTimestamp() {
  final n = DateTime.now();
  String p2(int v) => v.toString().padLeft(2, '0');
  String p3(int v) => v.toString().padLeft(3, '0');
  return '${n.year}-${p2(n.month)}-${p2(n.day)} ${p2(n.hour)}:${p2(n.minute)}:${p2(n.second)}.${p3(n.millisecond)}';
}

/// 任意需要直接打到 stdout 的说明（与 [debugPrint] 分流：无 `[debug]` 前缀）。
void matrixConsoleLog(String message) {
  // ignore: avoid_print
  print('[Matrix][${matrixConsoleTimestamp()}] $message');
}
