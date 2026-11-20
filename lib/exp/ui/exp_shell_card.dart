/// 统一的 WebShell 结果卡：URL / 密码 / 类型 + 复制 + 打开。
/// 替代 universal 页的 `_shellCard` 与各页面"只往日志里打一行 URL"的两种做法。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../core/exploit_module.dart';
import '../../theme/app_theme.dart';
import 'exp_tokens.dart';

class ExpShellCard extends StatelessWidget {
  const ExpShellCard({
    super.key,
    required this.session,
    this.onOpen,
    this.onCopyOnly,
  });

  final ShellSession session;

  /// 入库并进入工作区；由 `ShellHandoff` 提供，未注入时隐藏按钮。
  final VoidCallback? onOpen;
  final VoidCallback? onCopyOnly;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: session.url));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: ExpSpace.control,
      decoration: BoxDecoration(
        color: ExpColors.fill(ExpColors.ok, 0.08),
        borderRadius: ExpRadius.controlBorder,
        border: Border.all(color: ExpColors.fill(ExpColors.ok, 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.terminal, size: 16, color: ExpColors.ok),
              ExpSpace.hSm,
              Text(
                'WebShell · ${session.kind}',
                style: AppTextStyles.heading(
                  size: ExpText.body,
                  color: ExpColors.ok,
                ),
              ),
            ],
          ),
          ExpSpace.vSm,
          SelectableText(
            session.url,
            style: AppTextStyles.caption(
              size: ExpText.caption,
              color: ExpColors.text,
            ),
          ),
          if (session.note != null && session.note!.isNotEmpty) ...[
            ExpSpace.vXs,
            Text(
              session.note!,
              style: AppTextStyles.caption(
                size: ExpText.caption,
                color: ExpColors.textSecondary,
              ),
            ),
          ],
          ExpSpace.vMd,
          Wrap(
            spacing: ExpSpace.sm,
            runSpacing: ExpSpace.sm,
            children: [
              if (onOpen != null)
                FilledButton(
                  onPressed: onOpen,
                  style: ExpButton.primary(),
                  child: const Text('打开 WebShell'),
                ),
              OutlinedButton(
                onPressed: onCopyOnly ??
                    () async {
                      await _copy();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('URL copied'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                style: ExpButton.secondary(),
                child: const Text('复制'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
