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
    // 首次进入时从数据库加载监听配置
    _service.loadConfig().then((_) {
      if (mounted) setState(() {});
    });
    // 新会话建立 / 结束时刷新列表
    _service.onSession = (session) {
      setState(() {});
    };
    _service.onSessionClosed = (session) {
      if (mounted) {
        setState(() {});
      }
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
                              final text = listening && bindAddr != null && bindPort != null
                                  ? '监听中：$bindAddr:$bindPort'
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
                                : Icons.play_arrow,
                            size: 16,
                          ),
                          label: Text(_service.isListening ? '关闭监听' : '启动监听'),
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
                                  s.label != null && s.label!.isNotEmpty
                                      ? '${s.label} (${s.id})'
                                      : s.id,
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

