/// 统一的检测结果条。替代 universal 页的 `_resultBanner`
/// 与 webshell 页的 `_DetectResultPanel` 两套呈现。
library;

import 'package:flutter/material.dart';

import '../core/exploit_module.dart';
import '../../theme/app_theme.dart';
import 'exp_tokens.dart';

class ExpResultBanner extends StatelessWidget {
  const ExpResultBanner({super.key, required this.outcome});

  final ExploitOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = _presentation();
    return Container(
      padding: ExpSpace.control,
      decoration: BoxDecoration(
        color: ExpColors.fill(color, 0.10),
        borderRadius: ExpRadius.controlBorder,
        border: Border.all(color: ExpColors.fill(color, 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          ExpSpace.hSm,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$label · ${outcome.title}',
                  style: AppTextStyles.heading(
                    size: ExpText.body,
                    color: color,
                  ),
                ),
                if (outcome.detail.trim().isNotEmpty) ...[
                  ExpSpace.vXs,
                  SelectableText(
                    outcome.detail,
                    style: AppTextStyles.caption(
                      size: ExpText.caption,
                      color: ExpColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  (Color, IconData, String) _presentation() {
    if (outcome.failed) {
      return (ExpColors.warn, Icons.error_outline, 'Probe failed');
    }
    if (outcome.vulnerable) {
      return (ExpColors.danger, Icons.warning_amber_rounded, 'Vulnerable');
    }
    return (ExpColors.muted, Icons.shield_outlined, 'Not detected');
  }
}
