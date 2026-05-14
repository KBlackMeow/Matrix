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

/// suo5/6 与一键创建隧道等入口的共用图标（侧栏、页头、工具栏一致）。
abstract final class AppTunnelIcons {
  AppTunnelIcons._();

  static const IconData outlined = Icons.route_outlined;
  static const IconData filled = Icons.route;
}

/// FRP 客户端（侧栏、页头）；与 [AppTunnelIcons] 区分。
abstract final class AppFrpIcons {
  AppFrpIcons._();

  static const IconData outlined = Icons.router_outlined;
  static const IconData filled = Icons.router;
}

/// 弹窗与 [ThemeData.dialogTheme] 共用的圆角、描边与遮罩。
abstract final class MatrixDialogStyle {
  MatrixDialogStyle._();

  static const double radius = 14;

  /// 与页面背景同色相的暗色 scrim（略偏绿）。
  static Color get barrier => const Color(0xE6081010);

  static ShapeBorder outlinePrimary([double alpha = 0.28]) =>
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(
          color: AppColors.primary.withValues(alpha: alpha),
          width: 1,
        ),
      );

  static ShapeBorder outlineDanger([double alpha = 0.32]) =>
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(
          color: AppColors.red.withValues(alpha: alpha),
          width: 1,
        ),
      );

  static ShapeBorder outlineMuted() => RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: const BorderSide(color: AppColors.borderGlow, width: 1),
      );

  static ShapeBorder outlineAccent(Color accent, [double alpha = 0.28]) =>
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: accent.withValues(alpha: alpha), width: 1),
      );
}
