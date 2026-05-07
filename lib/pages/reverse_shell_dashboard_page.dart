import 'package:flutter/material.dart';
import 'dart:async';

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
  StreamSubscription<void>? _changesSub;

  @override
  void initState() {
    super.initState();
    // 首次进入时从数据库加载监听配置
    _service.loadConfig().then((_) {
      _service.refreshListeningState(port: _service.lport);
      if (mounted) setState(() {});
    });
    // 统一订阅服务状态变化，避免与其他页面抢占 onSession 回调
    _changesSub = _service.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _changesSub?.cancel();
    super.dispose();
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
                    const SizedBox(height: 4),
                    Text(
                      sessions.isEmpty
                          ? '当前没有活跃的反弹 Shell 会话'
                          : '活跃会话数：${sessions.length}',
                      style: AppTextStyles.caption(
                        size: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Builder(
                            builder: (context) {
                              final bindAddr = _service.bindAddress;
                              final bindPort = _service.bindPort;
                              final listening = _service.isListening;
                              final occupied = _service.isPortOccupied;
                              final text = listening && bindAddr != null && bindPort != null
                                  ? '监听中：$bindAddr:$bindPort'
                                  : occupied && bindAddr != null && bindPort != null
                                  ? '端口占用：$bindAddr:$bindPort（可能已有监听）'
                                  : '未监听（配置：${_service.lhost}:${_service.lport}）';
                              return Text(
                                text,
                                style: AppTextStyles.caption(
                                  size: 12,
                                  color: AppColors.textMuted,
                                ),
                              );
                            },
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final ipController =
                                TextEditingController(text: _service.lhost);
                            final portController =
                                TextEditingController(
                                    text: _service.lport.toString());
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (context) {
                                return AlertDialog(
                                  title: const Text('监听配置'),
                                  content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      TextField(
                                        controller: ipController,
                                        decoration: const InputDecoration(
                                          labelText: '监听 IP（LHOST）',
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      TextField(
                                        controller: portController,
                                        decoration: const InputDecoration(
                                          labelText: '监听端口（LPORT）',
                                        ),
                                        keyboardType: TextInputType.number,
                                      ),
                                    ],
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(false),
                                      child: const Text('取消'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(true),
                                      child: const Text('确定'),
                                    ),
                                  ],
                                );
                              },
                            );
                            if (ok == true) {
                              final ip = ipController.text.trim();
                              final port =
                                  int.tryParse(portController.text.trim());
                              if (ip.isNotEmpty && port != null) {
                                setState(() {
                                  _service.lhost = ip;
                                  _service.lport = port;
                                });
                                // 持久化保存监听配置（无需等待）
                                _service.saveConfig();
                              }
                            }
                          },
                          icon: const Icon(Icons.settings, size: 16),
                          label: const Text('监听配置'),
                          style: TextButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: const Size(0, 32),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: () async {
                            if (_service.isListening) {
                              // 关闭监听
                              await _service.stopListening();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('已关闭监听'),
                                  ),
                                );
                              }
                              setState(() {});
                              return;
                            }
                            if (_service.isPortOccupied) {
                              await _service.refreshListeningState(port: _service.lport);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('端口处于占用状态，请先释放后再启动监听'),
                                  ),
                                );
                              }
                              setState(() {});
                              return;
                            }
                            // 启动监听
                            try {
                              await _service.startListening(
                                  port: _service.lport);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        '已在 :${_service.lport} 启动监听（LHOST=${_service.lhost}）'),
                                  ),
                                );
                              }
                              setState(() {});
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('启动监听失败：$e'),
                                  ),
                                );
                              }
                            }
                          },
                          icon: Icon(
                            _service.isListening
                                ? Icons.stop
                                : (_service.isPortOccupied
                                    ? Icons.sync_problem
                                    : Icons.play_arrow),
                            size: 16,
                          ),
                          label: Text(
                            _service.isListening
                                ? '关闭监听'
                                : (_service.isPortOccupied ? '端口占用' : '启动监听'),
                          ),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 32),
                          ),
                        ),
                      ],
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
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final s = sessions[index];
                    return _SessionCard(session: s);
                  },
                ),
        ),
      ],
    );
  }
}

class _SessionCard extends StatefulWidget {
  final dynamic session;
  const _SessionCard({required this.session});

  @override
  State<_SessionCard> createState() => _SessionCardState();
}

class _SessionCardState extends State<_SessionCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: () {
            if (!s.isAlive) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('该会话已断开，无法打开终端'),
                  duration: Duration(seconds: 2),
                ),
              );
              return;
            }
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ReverseShellTerminalPage(session: s),
              ),
            );
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _hovered ? AppColors.bgElevated : AppColors.bgCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _hovered ? AppColors.primary.withValues(alpha: 0.55) : AppColors.border,
                width: _hovered ? 1.2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: _hovered ? 0.14 : 0.0),
                  blurRadius: 14,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: s.isAlive ? AppColors.primary : AppColors.textMuted,
                    boxShadow: s.isAlive
                        ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.6), blurRadius: 6)]
                        : null,
                  ),
                ),
                const Icon(Icons.terminal, color: AppColors.primary, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.label != null && s.label!.isNotEmpty ? '${s.label} (${s.id})' : s.id,
                        style: AppTextStyles.body(
                          size: 14,
                          color: s.isAlive ? AppColors.textPrimary : AppColors.textMuted,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (!s.isAlive)
                        Text('已断开', style: AppTextStyles.caption(size: 11, color: AppColors.red)),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: s.isAlive ? AppColors.textSecondary : AppColors.textMuted,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

