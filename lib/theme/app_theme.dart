import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 黑客风格主题配色
class AppColors {
  // 主色 - 柔和终端绿（比纯 #00FF41 护眼，更接近真实 CRT）
  static const Color primary = Color(0xFF00E676);
  static const Color primaryDim = Color(0xFF69F0AE);

  // 背景
  static const Color bgDark = Color(0xFF0A0E14);
  static const Color bgCard = Color(0xFF0F1419);
  static const Color bgElevated = Color(0xFF161B22);

  // 边框
  static const Color border = Color(0xFF21262D);
  static const Color borderGlow = Color(0xFF30363D);

  // 文字 — 带极淡绿调，沉浸感更强
  static const Color textPrimary = Color(0xFFD0E8D0);
  static const Color textSecondary = Color(0xFF8BA88B);
  static const Color textMuted = Color(0xFF5A705A);

  // 强调色
  static const Color cyan = Color(0xFF00E5FF);
  static const Color red = Color(0xFFFF5370);
  static const Color amber = Color(0xFFFFD740);
}

/// 黑客风格文字样式 — 使用 JetBrains Mono（专为代码设计的等宽字体）
class AppTextStyles {
  static TextStyle title({double size = 20, Color? color}) =>
      GoogleFonts.jetBrainsMono(
        fontSize: size,
        fontWeight: FontWeight.w700,
        color: color ?? AppColors.primary,
        letterSpacing: 1.5,
      );

  static TextStyle heading({double size = 16, Color? color}) =>
      GoogleFonts.jetBrainsMono(
        fontSize: size,
        fontWeight: FontWeight.w600,
        color: color ?? AppColors.primary,
        letterSpacing: 1.0,
      );

  static TextStyle body({double size = 14, Color? color}) =>
      GoogleFonts.jetBrainsMono(
        fontSize: size,
        fontWeight: FontWeight.w400,
        color: color ?? AppColors.textPrimary,
        letterSpacing: 0.3,
      );

  static TextStyle caption({double size = 12, Color? color}) =>
      GoogleFonts.jetBrainsMono(
        fontSize: size,
        fontWeight: FontWeight.w400,
        color: color ?? AppColors.textSecondary,
        letterSpacing: 0.2,
      ).copyWith(overflow: TextOverflow.ellipsis);

  static TextStyle terminal({double size = 14, Color? color}) =>
      GoogleFonts.jetBrainsMono(
        fontSize: size,
        fontWeight: FontWeight.w400,
        color: color ?? AppColors.primary,
        letterSpacing: 0.5,
      );
}
