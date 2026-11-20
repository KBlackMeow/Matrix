/// 日志的呈现层：把 [LogLine] 的语义级别翻译成颜色与文本样式。
///
/// 颜色只来自 [ExpColors]（语义角色），不允许出现色值字面量。
library;

import 'package:flutter/material.dart';

import '../core/log_line.dart';
import '../../theme/app_theme.dart';
import 'exp_tokens.dart';

extension LogLineStyle on LogLine {
  Color get color => switch (level) {
    LogLevel.ok => ExpColors.ok,
    LogLevel.error => ExpColors.danger,
    LogLevel.miss => ExpColors.muted,
    LogLevel.action => ExpColors.info,
    LogLevel.note => ExpColors.info,
    LogLevel.plain => ExpColors.textSecondary,
  };

  bool get emphasized => level == LogLevel.ok || level == LogLevel.error;

  TextStyle get style => AppTextStyles.terminal(
    size: ExpText.log,
    color: color,
  ).copyWith(fontWeight: emphasized ? FontWeight.w600 : FontWeight.w400);

  /// 前缀统一补一个空格，避免 `[+]` 与正文贴死。
  List<TextSpan> get spans => [
    if (level != LogLevel.plain) TextSpan(text: '${level.prefix} '),
    TextSpan(text: text),
  ];
}
