import 'package:flutter/material.dart';

import '../services/reverse_shell_service.dart';
import '../theme/app_theme.dart';
import 'reverse_shell_terminal_page.dart';

/// 反弹 Shell 会话管理页面（主菜单「完整终端」）
class ReverseShellDashboardPage extends StatefulWidget {
  const ReverseShellDashboardPage({super.key});

  @override
  State<ReverseShellDashboardPage> createState() =>
      _ReverseShellDashboardPageState();
}

class _ReverseShellDashboardPageState
    extends State<ReverseShellDashboardPage> {
  final _service = ReverseShellService();

  @override
  void initState() {
    super.initState();
    // 新会话建立时自动打开终端页，并刷新列表
    _service.onSession = (session) {
      setState(() {});
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ReverseShellTerminalPage(session: session),
        ),
      );
    };
  }

  @override
  Widget build(BuildContext context) {
    final sessions = _service.sessions.values.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              const Icon(Icons.computer,
                  color: AppColors.primary, size: 32),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '完整终端 · 反弹 Shell 会话',
                      style: AppTextStyles.heading(
                          size: 18, color: AppColors.primary),
                    ),
                    Text(
                      sessions.isEmpty
                          ? '当前没有活跃的反弹 Shell 会话'
                          : '活跃会话数：${sessions.length}',
                      style: AppTextStyles.caption(
                        size: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Expanded(
          child: sessions.isEmpty
              ? Center(
                  child: Text(
                    '> 暂无会话，可在 Webshell 终端中点击「完整终端」发起反弹 Shell。',
                    style: AppTextStyles.terminal(
                        size: 14, color: AppColors.textMuted),
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.separated(
                  itemCount: sessions.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final s = sessions[index];
                    return Material(
                      color: AppColors.bgCard,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  ReverseShellTerminalPage(session: s),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              const Icon(Icons.terminal,
                                  color: AppColors.primary, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  s.id,
                                  style: AppTextStyles.body(
                                      size: 14,
                                      color: AppColors.textPrimary),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const Icon(Icons.chevron_right,
                                  color: AppColors.textSecondary, size: 18),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

