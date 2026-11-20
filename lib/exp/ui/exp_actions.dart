/// 会话面板：检测 / 命令执行 / 取 shell 三个能力位驱动的动作，
/// 以及结果条与 shell 卡。
///
/// 旧页面里这一块是"能力位 × 动作脚手架 × 结果呈现"三份重复的组合，
/// 共 38 个手写动作方法。
library;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../core/exploit_module.dart';
import '../core/exploit_session.dart';
import 'exp_fields.dart';
import 'exp_result_banner.dart';
import 'exp_shell_card.dart';
import 'exp_tokens.dart';
import 'shell_handoff.dart';

class ExpSessionPanel extends StatefulWidget {
  const ExpSessionPanel({
    super.key,
    required this.session,
    required this.capabilities,
    this.defaultCommand = 'id',
    this.shellName,
  });

  final ExploitSessionController session;
  final Set<ExploitCapability> capabilities;
  final String defaultCommand;

  /// 入库时的名称前缀。
  final String? shellName;

  @override
  State<ExpSessionPanel> createState() => _ExpSessionPanelState();
}

class _ExpSessionPanelState extends State<ExpSessionPanel> {
  late final TextEditingController _cmd = TextEditingController(
    text: widget.defaultCommand,
  );

  @override
  void dispose() {
    _cmd.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        final caps = widget.capabilities;
        final running = session.running;
        final shell = session.shell;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: ExpSpace.sm,
              runSpacing: ExpSpace.sm,
              children: [
                if (caps.contains(ExploitCapability.check))
                  FilledButton(
                    onPressed: running ? null : session.detect,
                    style: ExpButton.primary(),
                    child: const Text('检测'),
                  ),
                if (caps.contains(ExploitCapability.getShell))
                  OutlinedButton(
                    onPressed: running ? null : session.deployShell,
                    style: ExpButton.secondary(),
                    child: const Text('获取 WebShell'),
                  ),
              ],
            ),
            if (caps.contains(ExploitCapability.exec)) ...[
              ExpSpace.vMd,
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _cmd,
                      enabled: !running,
                      style: AppTextStyles.body(
                        size: ExpText.body,
                        color: ExpColors.text,
                      ),
                      decoration: expInputDecoration('命令', 'id'),
                      onSubmitted: (v) => session.execute(v),
                    ),
                  ),
                  ExpSpace.hSm,
                  FilledButton(
                    onPressed: running ? null : () => session.execute(_cmd.text),
                    style: ExpButton.primary(),
                    child: const Text('执行'),
                  ),
                ],
              ),
            ],
            if (session.outcome != null) ...[
              ExpSpace.vMd,
              ExpResultBanner(outcome: session.outcome!),
            ],
            if (shell != null) ...[
              ExpSpace.vMd,
              ExpShellCard(
                session: shell,
                onOpen: () => ShellHandoff.open(
                  context,
                  shell,
                  name: widget.shellName,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
