// Shared UI helpers for Vulhub EXP pages — not exported as a library.
// Each page file imports this via a part or a direct import.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import '../../app/constants.dart';
import '../../core/log/log_buffer.dart';
import '../../theme/app_theme.dart';

Widget vulhubInfoCard(IconData icon, String title, String subtitle) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(color: AppColors.primary.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 2))
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
                colors: [AppColors.primary.withValues(alpha: 0.2), AppColors.primary.withValues(alpha: 0.08)],
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
            ),
            child: Icon(icon, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: AppTextStyles.heading(size: 14, color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              Text(subtitle, style: AppTextStyles.caption(size: 12, color: AppColors.textSecondary)),
            ]),
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
    return TextSpan(text: '> 等待操作', style: TextStyle(color: AppColors.textMuted, fontFamily: 'Monaco'));
  }
  final lines = log.split('\n');
  final base = AppTextStyles.terminal(size: 12, color: AppColors.textSecondary);
  return TextSpan(children: [
    for (var i = 0; i < lines.length; i++)
      TextSpan(
        text: lines[i] + (i < lines.length - 1 ? '\n' : ''),
        style: base.copyWith(
          color: vulhubLogLineColor(lines[i]),
          fontWeight: lines[i].startsWith('[+]') || lines[i].startsWith('[!]') ? FontWeight.w600 : null,
        ),
      ),
  ]);
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(flex: 1, child: leftPanel),
          const SizedBox(width: 16),
          Flexible(
            flex: 1,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.bgDark,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Container(
                      width: 6, height: 6,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: running ? AppColors.primary : AppColors.textMuted,
                      ),
                    ),
                    Text(
                      running ? '运行中' : '空闲',
                      style: AppTextStyles.caption(
                          size: 11, color: running ? AppColors.primary : AppColors.textSecondary),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: log.isEmpty
                          ? null
                          : () async {
                              await Clipboard.setData(ClipboardData(text: log));
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
                                );
                              }
                            },
                      icon: const Icon(Icons.copy, size: 14),
                      label: const Text('复制'),
                      style: TextButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          textStyle: const TextStyle(fontSize: 11)),
                    ),
                    TextButton.icon(
                      onPressed: log.isEmpty ? null : onClearLog,
                      icon: const Icon(Icons.clear_all, size: 14),
                      label: const Text('清空'),
                      style: TextButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          textStyle: const TextStyle(fontSize: 11)),
                    ),
                  ]),
                  const Divider(height: 1, color: AppColors.border),
                  const SizedBox(height: 4),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: logScroll,
                      child: SelectableText.rich(
                        vulhubRichLog(log),
                        style: AppTextStyles.terminal(size: 12, color: AppColors.textMuted),
                      ),
                    ),
                  ),
                ],
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
      child: Row(children: [
        Container(
          width: 3, height: 14,
          decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 8),
        Text(t, style: AppTextStyles.heading(size: 12, color: AppColors.textSecondary)),
      ]),
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
          borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.6))),
    );

Widget vTf(TextEditingController c, String label, String hint, {TextInputType? type}) => TextField(
      controller: c,
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
            padding: const EdgeInsets.symmetric(horizontal: 12)),
        child: Text(label),
      ),
    );

/// Mixin: log management helpers for Vulhub exp page states.
mixin VulhubLogMixin {
  String get log;
  set log(String v);
  ScrollController get logScroll;
  bool get running;
  set running(bool v);

  void appendLog(String line, {required void Function(void Function()) setState}) {
    setState(() {
      final buffer = LogBuffer(maxLines: AppConstants.logBufferSize);
      if (log.isNotEmpty) {
        for (final existing in log.split('\n')) {
          buffer.append(existing);
        }
      }
      buffer.append(line);
      log = buffer.joined;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (logScroll.hasClients) {
        logScroll.animateTo(logScroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100), curve: Curves.easeOut);
      }
    });
  }
}
