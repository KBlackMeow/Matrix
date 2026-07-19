import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/scheduler.dart';
import 'package:xterm/xterm.dart';

/// 轻量级 I/O 管线：原始 TCP socket 字节流 → 批量/分块/带背压写入 xterm Terminal。
///
/// 解决了 raw socket 直接写入 [Terminal.write] 时的三个核心问题：
/// - **批处理**：16ms microtask 定时器累积小块数据，避免渲染抖动
/// - **分块** ：单次写入 > 64KB 时拆分为多个 frame 保持 UI 响应
/// - **背压** ：高水位暂停 socket 订阅、低水位恢复，防止内存溢出
///
/// 同时提供字节级 LF→CRLF 转换（避免破坏 ANSI 序列）和可选的会话日志。
class TerminalOutputPipe {
  TerminalOutputPipe({
    required this.terminal,
    IOSink? logSink,
  }) : _logSink = logSink;

  /// 目标终端模拟器实例。
  final Terminal terminal;
  final IOSink? _logSink;

  /// 当缓冲超过高水位时调用，外部应暂停上游流。
  void Function()? onPause;

  /// 当缓冲降至低水位以下时调用，外部应恢复上游流。
  void Function()? onResume;

  static const _highWatermark = 512 * 1024; // 512 KB
  static const _lowWatermark = 128 * 1024; // 128 KB
  static const _maxWriteSize = 64 * 1024; // 单次写入上限 64 KB
  static const _flushInterval = Duration(milliseconds: 16); // ~60fps

  final _buffer = BytesBuilder(copy: false);
  int _buffered = 0;
  int _prevByte = -1; // 上一个被处理/输出的字节，用于跨 chunk LF→CRLF
  bool _paused = false;
  bool _flushScheduled = false;
  Timer? _timer;
  bool _disposed = false;

  // ── 公开 API ──────────────────────────────────────────────────────────────────

  /// 将原始字节数据送入管线。
  ///
  /// 数据会在 16ms 后（或下一个 [flush] 调用时）经 LF→CRLF 转换后写入终端。
  /// 当 [onPause] 已被调用且尚未恢复时，调用方应暂停上游流——不过即使在此
  /// 状态下继续调用 [add]，数据仍会安全缓冲。
  void add(List<int> chunk) {
    if (_disposed || chunk.isEmpty) return;

    _buffer.add(chunk);
    _buffered += chunk.length;
    _logSink?.add(chunk);

    _checkBackpressure();

    if (!_flushScheduled) {
      _flushScheduled = true;
      _timer = Timer(_flushInterval, _doFlush);
    }
  }

  /// 立即刷新所有待处理数据（不等待 16ms 定时器）。
  void flush() {
    _timer?.cancel();
    _timer = null;
    _doFlush();
  }

  /// 刷新剩余数据并关闭日志 Sink。
  ///
  /// 调用后管线不可再用。
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;

    // 刷新最后的残留数据
    _doFlush();

    await _logSink?.flush();
    await _logSink?.close();
  }

  // ── 内部 ──────────────────────────────────────────────────────────────────────

  void _doFlush() {
    _flushScheduled = false;
    _timer = null;
    if (_buffered == 0) return;

    final data = _buffer.takeBytes();
    _buffered = 0;

    final processed = _fixLineEndings(data);
    if (processed.isEmpty) return;

    _writeChunked(processed);
  }

  /// 字节级 LF→CRLF：仅将裸 `0x0A` 扩展为 `0x0D 0x0A`。
  ///
  /// 与字符串级 `replaceAll('\n', '\r\n')` 不同，此方法不会破坏含 `0x0A`
  /// 字节的 ANSI 序列。跨 chunk 状态通过 [_prevByte] 追踪。
  Uint8List _fixLineEndings(Uint8List data) {
    // 快速路径：数据中若无 0x0A，无需处理
    final lfCount = _countLf(data);
    if (lfCount == 0) {
      _prevByte = data.isNotEmpty ? data.last : _prevByte;
      return data;
    }

    final out = Uint8List(data.length + lfCount);
    var w = 0;

    for (var r = 0; r < data.length; r++) {
      final b = data[r];
      if (b == 0x0A && (r == 0 ? _prevByte : data[r - 1]) != 0x0D) {
        out[w++] = 0x0D; // 插入 CR
        out[w++] = 0x0A;
      } else {
        out[w++] = b;
      }
    }

    _prevByte = data.last;
    return Uint8List.sublistView(out, 0, w);
  }

  int _countLf(Uint8List data) {
    var count = 0;
    for (var i = 0; i < data.length; i++) {
      final prev = i == 0 ? _prevByte : data[i - 1];
      if (data[i] == 0x0A && prev != 0x0D) {
        count++;
      }
    }
    return count;
  }

  /// 将大数据写入拆分为多个 frame，每个 frame 最多 [_maxWriteSize] 字节。
  void _writeChunked(Uint8List data) {
    if (data.length <= _maxWriteSize) {
      final text = _decodeSafe(data);
      terminal.write(text);
      return;
    }

    var offset = 0;
    void writeNext(_) {
      if (_disposed) return;
      final end = (offset + _maxWriteSize).clamp(0, data.length);
      final chunk = Uint8List.sublistView(data, offset, end);
      final text = _decodeSafe(chunk);
      terminal.write(text);
      offset = end;
      if (offset < data.length) {
        SchedulerBinding.instance.addPostFrameCallback(writeNext);
      }
    }

    writeNext(null);
  }

  /// 以 UTF-8 解码，遇非法序列时替换为 U+FFFD（不抛异常）。
  static String _decodeSafe(Uint8List bytes) =>
      // allowMalformed: 非法字节替换为 U+FFFD，不中断输出
      // ignore: unintended_html_in_doc_comment
      utf8.decode(bytes, allowMalformed: true);

  void _checkBackpressure() {
    if (_paused) {
      // 检查是否已降至低水位以下
      if (_buffered <= _lowWatermark) {
        _paused = false;
        onResume?.call();
      }
    } else {
      if (_buffered >= _highWatermark) {
        _paused = true;
        onPause?.call();
      }
    }
  }
}
