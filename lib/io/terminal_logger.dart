import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 终端会话日志管理器。
///
/// 日志写入 `~/.matrix/logs/`（通过 [getApplicationSupportDirectory] 解析）。
/// 每个会话的日志文件命名格式：`session_<safeId>_<timestamp>.log`
class TerminalLogger {
  TerminalLogger._(this._file, this._sink);

  final File _file;
  final IOSink _sink;

  /// 会话日志文件完整路径。
  String get path => _file.path;

  /// 创建日志文件并返回 logger 实例。
  ///
  /// [sessionId] 会经安全化处理（去除非文件名字符）后嵌入文件名。
  static Future<TerminalLogger> create(String sessionId) async {
    final appDir = await getApplicationSupportDirectory();
    final logDir = Directory('${appDir.path}${Platform.pathSeparator}logs');
    if (!await logDir.exists()) {
      await logDir.create(recursive: true);
    }

    final now = DateTime.now();
    final ts =
        '${now.year}${_pad2(now.month)}${_pad2(now.day)}'
        '_${_pad2(now.hour)}${_pad2(now.minute)}${_pad2(now.second)}';
    final safeId = sessionId.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final file = File('${logDir.path}${Platform.pathSeparator}session_${safeId}_$ts.log');

    final sink = file.openWrite(mode: FileMode.writeOnlyAppend);
    // 写入日志头
    sink.add(utf8.encode(
      '# Matrix reverse shell session log\n'
      '# Session: $sessionId\n'
      '# Started: $now\n'
      '${'─' * 60}\n',
    ));
    // ignore: always_specify_types — void unawaited fire-and-forget 不阻塞创建
    unawaited(sink.flush());

    return TerminalLogger._(file, sink);
  }

  /// 追加原始字节数据到日志。
  void write(List<int> bytes) {
    _sink.add(bytes);
  }

  /// 追加字符串行（自动添加换行）。
  void writeLine(String line) {
    _sink.add(utf8.encode('$line\n'));
  }

  /// 获取日志存放目录路径（不创建实例，用于 "打开目录" 按钮）。
  static Future<String> logDirectoryPath() async {
    final appDir = await getApplicationSupportDirectory();
    return '${appDir.path}${Platform.pathSeparator}logs';
  }

  /// 刷新并关闭日志文件。
  Future<void> close() async {
    await _sink.flush();
    await _sink.close();
  }

  static String _pad2(int n) => n.toString().padLeft(2, '0');
}
