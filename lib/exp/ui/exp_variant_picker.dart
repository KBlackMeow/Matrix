/// 变体选择器：一个家族里有多个 CVE 时用。
///
/// 旧页面各写了一遍 `DropdownButton<枚举>`（struts2 / spring / weblogic / thinkphp），
/// 且枚举散落在 service 文件里。
library;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../core/exp_spec.dart';
import 'exp_fields.dart';
import 'exp_tokens.dart';

class ExpVariantPicker extends StatelessWidget {
  const ExpVariantPicker({
    super.key,
    required this.spec,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });

  final ExpSpec spec;
  final ExpVariant selected;
  final ValueChanged<ExpVariant> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: selected.id,
          // 变体标签很长（"S2-045 · Content-Type OGNL · CVE-2017-5638"），
          // 不展开会把按钮内部的 Row 撑破（RenderFlex overflow）。
          isExpanded: true,
          isDense: true,
          dropdownColor: ExpColors.surfaceRaised,
          style: AppTextStyles.body(size: ExpText.body, color: ExpColors.text),
          decoration: expInputDecoration('漏洞 / 变体', '选择具体 CVE'),
          items: [
            for (final v in spec.variants)
              DropdownMenuItem(
                value: v.id,
                child: Text(
                  v.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body(
                    size: ExpText.body,
                    color: ExpColors.text,
                  ),
                ),
              ),
          ],
          onChanged: enabled
              ? (id) {
                  final v = spec.variantById(id ?? '');
                  if (v != null) onChanged(v);
                }
              : null,
        ),
        if (selected.hint.isNotEmpty) ...[
          ExpSpace.vXs,
          Text(
            selected.hint,
            style: AppTextStyles.caption(
              size: ExpText.caption,
              color: ExpColors.warn,
            ),
          ),
        ],
      ],
    );
  }
}
