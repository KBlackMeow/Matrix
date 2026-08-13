import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'priv_esc_risk.dart';

class PrivEscRiskList extends StatelessWidget {
  const PrivEscRiskList({
    super.key,
    required this.risks,
    this.onCopy,
    this.onExecute,
    this.scanIncomplete = false,
    this.hasScanned = true,
  });

  final List<PrivEscRisk> risks;
  final ValueChanged<String>? onCopy;
  final ValueChanged<PrivEscRisk>? onExecute;
  final bool scanIncomplete;
  final bool hasScanned;

  @override
  Widget build(BuildContext context) {
    if (risks.isEmpty) {
      return _RiskEmptyState(
        scanIncomplete: scanIncomplete,
        hasScanned: hasScanned,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final group in groupPrivEscRisks(risks)) ...[
          _RiskSectionHeader(level: group.level),
          const SizedBox(height: 8),
          for (final risk in group.risks)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _PrivEscRiskCard(
                risk: risk,
                onCopy: onCopy,
                onExecute: onExecute,
              ),
            ),
          const SizedBox(height: 8),
        ],
        if (scanIncomplete)
          Text(
            '部分检查未完成；展开风险详情可查看可用的检测结果。',
            style: AppTextStyles.caption(color: AppColors.textMuted),
          ),
      ],
    );
  }
}

class _RiskSectionHeader extends StatelessWidget {
  const _RiskSectionHeader({required this.level});

  final PrivEscRiskLevel level;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (level) {
      PrivEscRiskLevel.confirmed => (
        '已确认风险',
        AppColors.red,
        Icons.error_outline,
      ),
      PrivEscRiskLevel.needsVerification => (
        '待验证风险',
        AppColors.amber,
        Icons.help_outline,
      ),
      PrivEscRiskLevel.informational => (
        '信息线索',
        AppColors.textSecondary,
        Icons.info_outline,
      ),
    };
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(label, style: AppTextStyles.heading(size: 13, color: color)),
        const SizedBox(width: 8),
        Expanded(child: Divider(color: color.withValues(alpha: 0.25))),
      ],
    );
  }
}

class _PrivEscRiskCard extends StatelessWidget {
  const _PrivEscRiskCard({
    required this.risk,
    this.onCopy,
    this.onExecute,
  });

  final PrivEscRisk risk;
  final ValueChanged<String>? onCopy;
  final ValueChanged<PrivEscRisk>? onExecute;

  @override
  Widget build(BuildContext context) {
    final color = switch (risk.level) {
      PrivEscRiskLevel.confirmed => AppColors.red,
      PrivEscRiskLevel.needsVerification => AppColors.amber,
      PrivEscRiskLevel.informational => AppColors.textSecondary,
    };
    final copyableCommands =
        (risk.verificationCommands.isEmpty
                ? risk.commands
                : risk.verificationCommands)
            .where(
              (command) =>
                  command.trim().isNotEmpty &&
                  !command.trimLeft().startsWith('#'),
            )
            .toList(growable: false);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            risk.title,
            style: AppTextStyles.body(
              size: 13,
            ).copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(risk.evidence, style: AppTextStyles.caption(size: 11)),
          if (copyableCommands.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('验证命令', style: AppTextStyles.caption(size: 11, color: color)),
            const SizedBox(height: 5),
            for (final command in copyableCommands)
              _CommandRow(command: command, color: color, onCopy: onCopy),
          ],
          if (risk.rawOutput != null || risk.checkCommand != null) ...[
            const SizedBox(height: 6),
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 4),
                title: Text('查看检测详情', style: AppTextStyles.caption(size: 11)),
                children: [
                  if (risk.checkCommand != null)
                    _DetailBlock(label: '检测命令', value: risk.checkCommand!),
                  if (risk.rawOutput != null)
                    _DetailBlock(label: '检测输出', value: risk.rawOutput!),
                ],
              ),
            ),
          ],
          if (risk.candidate != null &&
              risk.level == PrivEscRiskLevel.confirmed &&
              onExecute != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => onExecute!(risk),
                icon: const Icon(Icons.rocket_launch_outlined, size: 16),
                label: const Text('生成提权命令链并执行'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CommandRow extends StatelessWidget {
  const _CommandRow({required this.command, required this.color, this.onCopy});

  final String command;
  final Color color;
  final ValueChanged<String>? onCopy;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.bgDark,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: SelectableText(
              command,
              style: AppTextStyles.terminal(size: 11, color: AppColors.cyan),
            ),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          onPressed: onCopy == null ? null : () => onCopy!(command),
          icon: const Icon(Icons.copy_outlined, size: 16),
          tooltip: '复制验证命令',
          visualDensity: VisualDensity.compact,
          color: AppColors.textSecondary,
        ),
      ],
    ),
  );
}

class _DetailBlock extends StatelessWidget {
  const _DetailBlock({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.caption(size: 10, color: AppColors.textMuted),
        ),
        const SizedBox(height: 3),
        SelectableText(
          value,
          style: AppTextStyles.terminal(
            size: 10.5,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    ),
  );
}

class _RiskEmptyState extends StatelessWidget {
  const _RiskEmptyState({
    required this.scanIncomplete,
    required this.hasScanned,
  });

  final bool scanIncomplete;
  final bool hasScanned;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 48),
    child: Center(
      child: Text(
        !hasScanned
            ? '开始扫描后将在这里显示已识别风险。'
            : (scanIncomplete ? '扫描未完整完成，暂未生成可识别风险。' : '扫描完成，未发现已识别风险。'),
        style: AppTextStyles.body(size: 13, color: AppColors.textSecondary),
      ),
    ),
  );
}
