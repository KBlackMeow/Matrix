// Shared UI helpers for Vulhub EXP pages — not exported as a library.
// Each page file imports this via a part or a direct import.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import '../../app/localization.dart';
import '../../theme/app_theme.dart';

Widget vulhubInfoCard(IconData icon, String title, String subtitle) =>
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.primary.withValues(alpha: 0.2),
                  AppColors.primary.withValues(alpha: 0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.4),
              ),
            ),
            child: Icon(icon, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.heading(
                    size: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: AppTextStyles.caption(
                    size: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

Color vulhubLogLineColor(String line) {
  if (line.startsWith('[+]')) return AppColors.primary;
  if (line.startsWith('[!]')) return AppColors.red;
  if (line.startsWith('[-]')) return AppColors.textMuted;
  if (line.startsWith('[*]')) return AppColors.cyan;
  if (line.startsWith('[i]')) return AppColors.cyan.withValues(alpha: 0.9);
  return AppColors.textSecondary;
}

TextSpan vulhubRichLog(String log) {
  if (log.isEmpty) {
    return TextSpan(
      text: S.expWaiting,
      style: const TextStyle(color: AppColors.textMuted, fontFamily: 'Monaco'),
    );
  }
  final lines = log.split('\n');
  final base = AppTextStyles.terminal(size: 12, color: AppColors.textSecondary);
  return TextSpan(
    children: [
      for (var i = 0; i < lines.length; i++)
        TextSpan(
          text: lines[i] + (i < lines.length - 1 ? '\n' : ''),
          style: base.copyWith(
            color: vulhubLogLineColor(lines[i]),
            fontWeight: lines[i].startsWith('[+]') || lines[i].startsWith('[!]')
                ? FontWeight.w600
                : null,
          ),
        ),
    ],
  );
}

class VulhubExpCardShell extends StatelessWidget {
  final bool running;
  final String log;
  final ScrollController logScroll;
  final VoidCallback onClearLog;
  final Widget leftPanel;

  const VulhubExpCardShell({
    super.key,
    required this.running,
    required this.log,
    required this.logScroll,
    required this.onClearLog,
    required this.leftPanel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 820;
          final logPanel = _VulhubLogPanel(
            running: running,
            log: log,
            logScroll: logScroll,
            onClearLog: onClearLog,
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 3, child: leftPanel),
                const SizedBox(height: 16),
                Expanded(flex: 4, child: logPanel),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(flex: 1, child: leftPanel),
              const SizedBox(width: 16),
              Flexible(flex: 1, child: logPanel),
            ],
          );
        },
      ),
    );
  }
}

class _VulhubLogPanel extends StatelessWidget {
  final bool running;
  final String log;
  final ScrollController logScroll;
  final VoidCallback onClearLog;

  const _VulhubLogPanel({
    required this.running,
    required this.log,
    required this.logScroll,
    required this.onClearLog,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: running ? AppColors.primary : AppColors.textMuted,
                ),
              ),
              Text(
                running ? S.statusRunning : S.statusIdle,
                style: AppTextStyles.caption(
                  size: 11,
                  color: running ? AppColors.primary : AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: log.isEmpty
                    ? null
                    : () async {
                        await Clipboard.setData(ClipboardData(text: log));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(S.snackCopied),
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        }
                      },
                icon: const Icon(Icons.copy, size: 14),
                label: Text(S.actionCopy),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  textStyle: const TextStyle(fontSize: 11),
                ),
              ),
              TextButton.icon(
                onPressed: log.isEmpty ? null : onClearLog,
                icon: const Icon(Icons.clear_all, size: 14),
                label: Text(S.btnClear),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  textStyle: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 4),
          Expanded(
            child: SingleChildScrollView(
              controller: logScroll,
              child: SelectableText.rich(
                vulhubRichLog(log),
                style: AppTextStyles.terminal(
                  size: 12,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget vSecTitle(String t) => Padding(
  padding: const EdgeInsets.only(bottom: 6),
  child: Row(
    children: [
      Container(
        width: 3,
        height: 14,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 8),
      Text(
        t,
        style: AppTextStyles.heading(size: 12, color: AppColors.textSecondary),
      ),
    ],
  ),
);

InputDecoration vInputDec(String label, String hint) => InputDecoration(
  labelText: label,
  hintText: hint,
  hintStyle: AppTextStyles.caption(size: 11, color: AppColors.textMuted),
  floatingLabelBehavior: FloatingLabelBehavior.always,
  isDense: true,
  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: const BorderSide(color: AppColors.border),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.6)),
  ),
);

Widget vTf(
  TextEditingController c,
  String label,
  String hint, {
  TextInputType? type,
  bool enabled = true,
}) => TextField(
  controller: c,
  enabled: enabled,
  style: AppTextStyles.body(size: 12, color: AppColors.textPrimary),
  keyboardType: type,
  decoration: vInputDec(label, hint),
);

Widget vBtn(String label, VoidCallback? onPressed) => SizedBox(
  height: 32,
  child: ElevatedButton(
    onPressed: onPressed,
    style: ElevatedButton.styleFrom(
      textStyle: const TextStyle(fontSize: 11),
      padding: const EdgeInsets.symmetric(horizontal: 12),
    ),
    child: Text(label),
  ),
);

/// Shows the reverse-shell mode picker dialog used by exploit pages.
/// Returns the selected mode string ('script' | 'bash' | 'socat') or null if cancelled.
Future<String?> showReverseShellModeDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      String selected = 'script';
      return StatefulBuilder(
        builder: (ctx2, setInner) => AlertDialog(
          title: Text(S.titleSelectTerminalMode),
          content: RadioGroup<String>(
            groupValue: selected,
            onChanged: (v) {
              if (v != null) setInner(() => selected = v);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<String>(
                  value: 'script',
                  title: Text(S.terminalModeScript),
                  subtitle: Text(
                    S.terminalModeScriptDesc,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                RadioListTile<String>(
                  value: 'bash',
                  title: Text(S.terminalModeBash),
                  subtitle: Text(
                    S.terminalModeBashDesc,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                RadioListTile<String>(
                  value: 'socat',
                  title: Text(S.terminalModeSocat),
                  subtitle: Text(
                    S.terminalModeSocatDesc,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx2),
              child: Text(S.btnCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx2, selected),
              child: Text(S.btnConfirm),
            ),
          ],
        ),
      );
    },
  );
}
