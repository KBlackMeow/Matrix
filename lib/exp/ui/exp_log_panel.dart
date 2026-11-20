/// 唯一的日志面板。替代 `_VulhubLogPanel`、ThinkPHP/Zentao 的手抄副本，
/// 以及 universal 页里那块用了裸色值的降级版本。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../core/log_line.dart';
import '../../theme/app_theme.dart';
import 'exp_tokens.dart';
import 'log_line_style.dart';

class ExpLogPanel extends StatefulWidget {
  const ExpLogPanel({
    super.key,
    required this.lines,
    this.running = false,
    this.onClear,
    this.emptyText = '> Awaiting action',
    this.statusLabel,
  });

  final List<LogLine> lines;
  final bool running;
  final VoidCallback? onClear;

  /// 空态文案。统一以 `> ` 开头，保持终端感。
  final String emptyText;

  /// 覆盖右上角状态文案（默认 Running / Idle）。
  final String? statusLabel;

  @override
  State<ExpLogPanel> createState() => _ExpLogPanelState();
}

class _ExpLogPanelState extends State<ExpLogPanel> {
  final ScrollController _scroll = ScrollController();

  @override
  void didUpdateWidget(covariant ExpLogPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.lines.length != oldWidget.lines.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _stickToBottom());
    }
  }

  void _stickToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
    );
  }

  String get _plain => widget.lines.map((l) => l.plainText).join('\n');

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _plain));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasContent = widget.lines.isNotEmpty;
    return Container(
      padding: ExpSpace.panel,
      decoration: BoxDecoration(
        color: ExpColors.surfaceSunken,
        borderRadius: ExpRadius.panelBorder,
        border: Border.all(color: ExpColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(hasContent),
          const Divider(height: 1, color: ExpColors.border),
          ExpSpace.vXs,
          Expanded(
            child: hasContent
                ? SingleChildScrollView(
                    controller: _scroll,
                    child: SelectableText.rich(_richText()),
                  )
                : Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      widget.emptyText,
                      style: AppTextStyles.terminal(
                        size: ExpText.log,
                        color: ExpColors.muted,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  TextSpan _richText() {
    final children = <TextSpan>[];
    for (var i = 0; i < widget.lines.length; i++) {
      final line = widget.lines[i];
      for (final span in line.spans) {
        children.add(
          TextSpan(
            text: span.text,
            style: line.style,
          ),
        );
      }
      if (i < widget.lines.length - 1) {
        children.add(TextSpan(text: '\n', style: widget.lines[i].style));
      }
    }
    return TextSpan(children: children);
  }

  Widget _header(bool hasContent) {
    final status = widget.statusLabel ?? (widget.running ? 'Running' : 'Idle');
    final dotColor = widget.running ? ExpColors.ok : ExpColors.muted;
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.only(right: 6),
          decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
        ),
        Text(
          status,
          style: AppTextStyles.caption(
            size: ExpText.caption,
            color: widget.running ? ExpColors.ok : ExpColors.textSecondary,
          ),
        ),
        const Spacer(),
        TextButton.icon(
          onPressed: hasContent ? _copy : null,
          icon: const Icon(Icons.copy, size: 14),
          label: const Text('Copy'),
          style: ExpButton.ghost(),
        ),
        TextButton.icon(
          onPressed: hasContent ? widget.onClear : null,
          icon: const Icon(Icons.clear_all, size: 14),
          label: const Text('Clear'),
          style: ExpButton.ghost(),
        ),
      ],
    );
  }
}
