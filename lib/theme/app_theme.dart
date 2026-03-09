import 'package:flutter/material.dart';

/// 黑客风格主题配色
class AppColors {
  // 主色 - Matrix 绿
  static const Color primary = Color(0xFF00FF41);
  static const Color primaryDim = Color(0xFF39FF14);

  // 背景
  static const Color bgDark = Color(0xFF0A0E14);
  static const Color bgCard = Color(0xFF0F1419);
  static const Color bgElevated = Color(0xFF161B22);

  // 边框
  static const Color border = Color(0xFF21262D);
  static const Color borderGlow = Color(0xFF30363D);

  // 文字
  static const Color textPrimary = Color(0xFFE6EDF3);
  static const Color textSecondary = Color(0xFF8B949E);
  static const Color textMuted = Color(0xFF6E7681);

  // 强调色
  static const Color cyan = Color(0xFF00D9FF);
  static const Color red = Color(0xFFFF5555);
  static const Color amber = Color(0xFFFFB86C);
}

/// 黑客风格文字样式（使用系统等宽字体，避免联网加载）
class AppTextStyles {
  static const String _fontFamily = 'monospace';
  /// 终端专用字体：macOS 优先使用 Monaco，其他平台回退到 Courier New / monospace
  static const String _terminalFont = 'Monaco';
  static const List<String> _terminalFallback = ['Courier New', 'Courier', 'monospace'];

  static const TextStyle _baseMono = TextStyle(fontFamily: _fontFamily);

  static TextStyle title({double size = 20, Color? color}) =>
      _baseMono.copyWith(
        fontSize: size,
        fontWeight: FontWeight.w600,
        color: color ?? AppColors.primary,
        letterSpacing: 1.5,
      );

  static TextStyle heading({double size = 16, Color? color}) =>
      _baseMono.copyWith(
        fontSize: size,
        fontWeight: FontWeight.w600,
        color: color ?? AppColors.primary,
        letterSpacing: 1,
      );

  static TextStyle body({double size = 14, Color? color}) =>
      _baseMono.copyWith(
        fontSize: size,
        color: color ?? AppColors.textPrimary,
        letterSpacing: 0.3,
      );

  static TextStyle caption({double size = 12, Color? color}) =>
      _baseMono.copyWith(
        fontSize: size,
        color: color ?? AppColors.textSecondary,
        letterSpacing: 0.2,
      );

  static TextStyle terminal({double size = 14, Color? color}) =>
      _baseMono.copyWith(
        fontFamily: _terminalFont,
        fontFamilyFallback: _terminalFallback,
        fontSize: size,
        color: color ?? AppColors.primary,
        letterSpacing: 0.5,
      );
}
