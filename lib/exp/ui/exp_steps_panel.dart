/// 流程面板：把家族的步骤逐条列出来，每步有自己的参数、状态、结果与产物。
///
/// 与旧页面的区别：旧页面是「一堆按钮 + 一个日志」，这里是「一条链」——
/// 哪步做过、哪步失败、缺什么才能做下一步，都在卡片上。
library;

import 'package:flutter/material.dart';

import '../core/exp_spec.dart';
import '../core/exp_step.dart';
import '../core/exploit_session.dart';
import '../core/step_runner.dart';
import '../../theme/app_theme.dart';
import 'exp_fields.dart';
import 'exp_shell_card.dart';
import 'exp_tokens.dart';
import 'shell_handoff.dart';

class ExpStepsPanel extends StatefulWidget {
  const ExpStepsPanel({
    super.key,
    required this.spec,
    required this.session,
  });

  final ExpSpec spec;
  final ExploitSessionController session;

  @override
  State<ExpStepsPanel> createState() => _ExpStepsPanelState();
}

class _ExpStepsPanelState extends State<ExpStepsPanel> {
  late final StepRunner _runner = StepRunner(
    steps: widget.spec.steps,
    targetBuilder: widget.session.buildTarget,
    readField: widget.session.field,
    writeField: widget.session.setField,
    log: (level, text) => widget.session.appendLog(level, text),
    onChanged: () {
      if (mounted) setState(() {});
    },
  );

  @override
  Widget build(BuildContext context) {
    final shell = _runner.lastShell;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final step in widget.spec.steps) ...[
          _StepCard(
            step: step,
            runner: _runner,
            session: widget.session,
            onRun: () => _run(step),
          ),
          ExpSpace.vMd,
        ],
        if (shell != null)
          // 拿到 WebShell 后必须能看见、能进工作区（旧页面的行为）。
          ExpShellCard(
            session: shell,
            onOpen: () => ShellHandoff.open(
              context,
              shell,
              name: '${widget.spec.family} Shell',
            ),
          ),
      ],
    );
  }

  Future<void> _run(ExpStep step) async {
    if (widget.session.running) return;
    final before = _runner.lastShell;
    await widget.session.run(
      label: step.title,
      phase: SessionPhase.executing,
      body: () => _runner.run(step),
    );
    if (!mounted) return;
    setState(() {});
    final shell = _runner.lastShell;
    if (shell != null && !identical(shell, before)) {
      // 产出 WebShell：立刻走「选项目 → 入库 → 打开工作区」，
      // 与迁移前的 GetShell 行为一致（不是只往日志里打一行 URL）。
      await ShellHandoff.open(
        context,
        shell,
        name: '${widget.spec.family} Shell',
      );
    }
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.step,
    required this.runner,
    required this.session,
    required this.onRun,
  });

  final ExpStep step;
  final StepRunner runner;
  final ExploitSessionController session;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    final status = runner.statusOf(step);
    final (color, icon) = switch (status) {
      StepStatus.ok => (ExpColors.ok, Icons.check_circle_outline),
      StepStatus.failed => (ExpColors.danger, Icons.error_outline),
      StepStatus.running => (ExpColors.info, Icons.autorenew),
      StepStatus.blocked => (ExpColors.warn, Icons.block),
      StepStatus.idle => (ExpColors.muted, Icons.radio_button_unchecked),
    };
    final missing = runner.missingFor(step);
    final canRun = !session.running && missing.isEmpty;
    final detail = runner.detailOf(step);
    final error = runner.errorOf(step);

    return Container(
      padding: ExpSpace.control,
      decoration: BoxDecoration(
        color: ExpColors.surface,
        borderRadius: ExpRadius.cardBorder,
        border: Border.all(color: ExpColors.fill(color, 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              ExpSpace.hSm,
              Expanded(
                child: Text(
                  step.title,
                  style: AppTextStyles.heading(
                    size: ExpText.body,
                    color: ExpColors.text,
                  ),
                ),
              ),
              if (step.isProbe)
                Text(
                  '扫描依据',
                  style: AppTextStyles.caption(
                    size: ExpText.caption,
                    color: ExpColors.info,
                  ),
                ),
            ],
          ),
          if (step.description.isNotEmpty) ...[
            ExpSpace.vXs,
            Text(
              step.description,
              style: AppTextStyles.caption(
                size: ExpText.caption,
                color: ExpColors.textSecondary,
              ),
            ),
          ],
          if (missing.isNotEmpty) ...[
            ExpSpace.vXs,
            Text(
              '需要先完成：${missing.join('、')}',
              style: AppTextStyles.caption(
                size: ExpText.caption,
                color: ExpColors.warn,
              ),
            ),
          ],
          if (step.fields.isNotEmpty) ...[
            ExpSpace.vSm,
            ExpFields(
              key: ValueKey(step.id),
              fields: step.fields,
              values: {
                for (final f in step.fields)
                  f.key: session.field('${step.id}.${f.key}') ?? f.defaultValue,
              },
              onChanged: (k, v) => session.setField('${step.id}.$k', v),
            ),
          ],
          if (detail != null && detail.isNotEmpty) ...[
            ExpSpace.vSm,
            Text(
              detail,
              style: AppTextStyles.caption(
                size: ExpText.caption,
                color: ExpColors.ok,
              ),
            ),
          ],
          if (error != null && error.isNotEmpty) ...[
            ExpSpace.vSm,
            Text(
              error,
              style: AppTextStyles.caption(
                size: ExpText.caption,
                color: ExpColors.danger,
              ),
            ),
          ],
          ExpSpace.vSm,
          Row(
            children: [
              FilledButton(
                onPressed: canRun ? onRun : null,
                style: ExpButton.primary(),
                child: Text(
                  status == StepStatus.failed ? '重试' : '执行',
                ),
              ),
              ExpSpace.hSm,
              if (step.produces.isNotEmpty)
                Text(
                  '产物：${step.produces.join('、')}',
                  style: AppTextStyles.caption(
                    size: ExpText.caption,
                    color: ExpColors.muted,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
