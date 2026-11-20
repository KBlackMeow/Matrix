/// EXP 专属设计 token。
///
/// 唯一的"语义层"：exp 组件与页面**只能**引用这里的角色名，
/// 不允许出现 `Colors.xxx` / `Color(0x…)` / `fontSize:` 字面量。
/// 约束由 `tool/verify/ui_guard.dart` 机械检查。
///
/// 这里不新增任何色值，全部映射到 `AppColors`，
/// 保证与 app 其他部分同源（见 docs/exp-unified-architecture.md §7）。
library;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 语义色。左列是"用途"，右列才是具体颜色。
abstract final class ExpColors {
  ExpColors._();

  /// 成功 / 命中 / 可执行。
  static const Color ok = AppColors.primary;

  /// 失败 / 错误 / 危险动作。
  static const Color danger = AppColors.red;

  /// 弱警告 / 需要用户注意但不致命。
  static const Color warn = AppColors.amber;

  /// 进行中 / 提示 / 链接。
  static const Color info = AppColors.cyan;

  /// 未命中 / 禁用 / 空态。
  static const Color muted = AppColors.textMuted;

  /// 正文。
  static const Color text = AppColors.textPrimary;
  static const Color textSecondary = AppColors.textSecondary;

  /// 表面。
  static const Color surface = AppColors.bgCard;
  static const Color surfaceSunken = AppColors.bgDark;
  static const Color surfaceRaised = AppColors.bgElevated;

  static const Color border = AppColors.border;
  static const Color borderStrong = AppColors.borderGlow;

  /// 把某个语义色用它自己的透明度做成"底纹"，替代散落的 alpha 字面量。
  static Color fill(Color role, [double alpha = 0.12]) =>
      role.withValues(alpha: alpha);
}

/// 圆角阶梯。10 = 卡片，8 = 控件/面板，6 = 徽章。
abstract final class ExpRadius {
  ExpRadius._();

  static const double card = 10;
  static const double panel = 8;
  static const double control = 8;
  static const double chip = 6;

  static BorderRadius get cardBorder => BorderRadius.circular(card);
  static BorderRadius get panelBorder => BorderRadius.circular(panel);
  static BorderRadius get controlBorder => BorderRadius.circular(control);
  static BorderRadius get chipBorder => BorderRadius.circular(chip);
}

/// 间距阶梯。禁止再出现 `SizedBox(height: 13)` 这种一次性的数。
abstract final class ExpSpace {
  ExpSpace._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;

  static const SizedBox hXs = SizedBox(width: xs);
  static const SizedBox hSm = SizedBox(width: sm);
  static const SizedBox hMd = SizedBox(width: md);
  static const SizedBox hLg = SizedBox(width: lg);

  static const SizedBox vXs = SizedBox(height: xs);
  static const SizedBox vSm = SizedBox(height: sm);
  static const SizedBox vMd = SizedBox(height: md);
  static const SizedBox vLg = SizedBox(height: lg);

  static const EdgeInsets page = EdgeInsets.all(xl);
  static const EdgeInsets card = EdgeInsets.symmetric(
    horizontal: 20,
    vertical: 16,
  );
  static const EdgeInsets panel = EdgeInsets.all(md);
  static const EdgeInsets control = EdgeInsets.symmetric(
    horizontal: md,
    vertical: 10,
  );
}

/// 字号阶梯（配合 `AppTextStyles.*(size: …)` 使用）。
///
/// 最小 11：10 及以下在等宽字体 + 中文回退下已经不可读。
abstract final class ExpText {
  ExpText._();

  static const double pageTitle = 14;
  static const double section = 12;
  static const double body = 12;
  static const double label = 11;
  static const double caption = 11;
  static const double log = 12;
  static const double badge = 11;
}

/// 统一按钮词表：主/次/幽灵三档，尺寸固定 32。
///
/// 替代散落的 `vBtn` / `FilledButton.icon` / `FilledButton.styleFrom`。
abstract final class ExpButton {
  ExpButton._();

  static const double height = 32;
  static const EdgeInsets padding = EdgeInsets.symmetric(horizontal: 12);

  /// 按钮文案样式。统一在这里派生，避免各处写 `TextStyle(fontSize: …)`。
  static TextStyle get labelStyle => AppTextStyles.body(
    size: ExpText.label,
    color: ExpColors.text,
  ).copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.2);

  static ButtonStyle primary() => FilledButton.styleFrom(
    backgroundColor: ExpColors.ok,
    foregroundColor: ExpColors.surfaceSunken,
    disabledBackgroundColor: ExpColors.fill(ExpColors.ok, 0.15),
    disabledForegroundColor: ExpColors.muted,
    textStyle: labelStyle,
    padding: padding,
    minimumSize: const Size(0, height),
    shape: RoundedRectangleBorder(borderRadius: ExpRadius.controlBorder),
  );

  static ButtonStyle secondary() => OutlinedButton.styleFrom(
    foregroundColor: ExpColors.textSecondary,
    side: const BorderSide(color: ExpColors.border),
    textStyle: labelStyle,
    padding: padding,
    minimumSize: const Size(0, height),
    shape: RoundedRectangleBorder(borderRadius: ExpRadius.controlBorder),
  );

  static ButtonStyle ghost() => TextButton.styleFrom(
    foregroundColor: ExpColors.textSecondary,
    textStyle: labelStyle,
    padding: padding,
    minimumSize: const Size(0, height),
  );
}
