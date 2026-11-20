/// 页面骨架：Scaffold + AppBar + 信息卡 + 左右分栏（左表单 | 右日志）。
///
/// 吸收 `BaseVulhubExpPage` + `VulhubExpCardShell`。模块页与一键扫描页共用它，
/// 保证"一个家族的页面"和"扫描页"不是两套壳。
library;

import 'package:flutter/material.dart';

import '../core/log_line.dart';
import '../../theme/app_theme.dart';
import 'exp_info_card.dart';
import 'exp_log_panel.dart';
import 'exp_tokens.dart';

/// 分栏右侧需要的状态，由调用方在每次 rebuild 时提供。
class ExpWorkspaceState {
  const ExpWorkspaceState({
    required this.lines,
    required this.running,
    this.onClear,
    this.statusLabel,
  });

  final List<LogLine> lines;
  final bool running;
  final VoidCallback? onClear;
  final String? statusLabel;
}

class ExpScaffold extends StatelessWidget {
  const ExpScaffold({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.form,
    required this.listenable,
    required this.state,
    this.notes = const [],
    this.actions,
    this.extraResult,
    this.formFlex = 1,
    this.logFlex = 1,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  /// 左栏：字段表 + 按钮组。
  final Widget form;

  /// 触发重建的对象（通常是 ChangeNotifier）。
  final Listenable listenable;

  /// 每次重建时取当前日志/运行态。
  final ExpWorkspaceState Function() state;

  final List<String> notes;

  /// AppBar 右侧的动作，可空。
  final List<Widget>? actions;

  /// 结果条 / shell 卡等附加区块。
  final Widget? extraResult;

  final int formFlex;
  final int logFlex;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ExpColors.surfaceSunken,
      appBar: AppBar(
        backgroundColor: ExpColors.surfaceRaised,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Row(
          children: [
            Icon(icon, color: ExpColors.ok, size: 18),
            ExpSpace.hSm,
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.heading(
                  size: ExpText.pageTitle,
                  color: ExpColors.ok,
                ),
              ),
            ),
          ],
        ),
        actions: actions,
      ),
      body: Padding(
        padding: ExpSpace.page,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExpInfoCard(
              icon: icon,
              title: title,
              subtitle: subtitle,
              notes: notes,
            ),
            ExpSpace.vLg,
            Expanded(
              child: AnimatedBuilder(
                animation: listenable,
                builder: (context, _) => _workspace(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _workspace(BuildContext context) {
    final current = state();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: ExpColors.surface,
        borderRadius: ExpRadius.cardBorder,
        border: Border.all(color: ExpColors.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 820;
          final logPanel = ExpLogPanel(
            lines: current.lines,
            running: current.running,
            statusLabel: current.statusLabel,
            onClear: current.onClear,
          );
          final formPanel = SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                form,
                if (extraResult != null) ...[
                  ExpSpace.vLg,
                  extraResult!,
                ],
              ],
            ),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 3, child: formPanel),
                ExpSpace.vLg,
                Expanded(flex: 4, child: logPanel),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(flex: formFlex, child: formPanel),
              ExpSpace.hLg,
              Flexible(flex: logFlex, child: logPanel),
            ],
          );
        },
      ),
    );
  }
}
