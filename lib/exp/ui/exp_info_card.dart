/// 页面顶部的信息卡（图标 + 标题 + 副标题）。
/// 吸收 `vulhubInfoCard` 及其在 ThinkPHP / Zentao 里的两份手抄副本。
library;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'exp_tokens.dart';

class ExpInfoCard extends StatelessWidget {
  const ExpInfoCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.notes = const [],
  });

  final IconData icon;
  final String title;
  final String subtitle;

  /// 版本范围 / 前提条件等要点，一行一条。
  final List<String> notes;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: ExpSpace.card,
      decoration: BoxDecoration(
        color: ExpColors.surface,
        borderRadius: ExpRadius.cardBorder,
        border: Border.all(color: ExpColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _tile(),
          ExpSpace.hLg,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.heading(
                    size: ExpText.pageTitle,
                    color: ExpColors.text,
                  ),
                ),
                ExpSpace.vXs,
                Text(
                  subtitle,
                  style: AppTextStyles.caption(
                    size: ExpText.caption,
                    color: ExpColors.textSecondary,
                  ),
                ),
                for (final note in notes) ...[
                  ExpSpace.vXs,
                  Text(
                    note,
                    style: AppTextStyles.caption(
                      size: ExpText.caption,
                      color: ExpColors.muted,
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

  Widget _tile() => Container(
    width: 44,
    height: 44,
    decoration: BoxDecoration(
      color: ExpColors.fill(ExpColors.ok, 0.15),
      borderRadius: ExpRadius.cardBorder,
      border: Border.all(color: ExpColors.fill(ExpColors.ok, 0.4)),
    ),
    child: Icon(icon, color: ExpColors.ok, size: 22),
  );
}
