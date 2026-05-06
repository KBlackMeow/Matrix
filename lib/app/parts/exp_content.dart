import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'exp_registry.dart';

class ExpContent extends StatefulWidget {
  const ExpContent({super.key});

  @override
  State<ExpContent> createState() => _ExpContentState();
}

class _ExpContentState extends State<ExpContent> {
  final Set<ExpMaturity> _selectedMaturities = ExpMaturity.values.toSet();

  void _toggleMaturity(ExpMaturity maturity) {
    setState(() {
      if (_selectedMaturities.contains(maturity)) {
        if (_selectedMaturities.length == 1) return;
        _selectedMaturities.remove(maturity);
      } else {
        _selectedMaturities.add(maturity);
      }
    });
  }

  void _selectAllMaturities() {
    setState(() {
      _selectedMaturities
        ..clear()
        ..addAll(ExpMaturity.values);
    });
  }

  @override
  Widget build(BuildContext context) {
    final entries = visibleExpEntries(maturities: _selectedMaturities);
    final allSelected = _selectedMaturities.length == ExpMaturity.values.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              const Icon(Icons.bug_report, color: AppColors.primary, size: 32),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'EXP 管理',
                      style: AppTextStyles.heading(
                        size: 18,
                        color: AppColors.primary,
                      ),
                    ),
                    Text(
                      '在这里集中管理各类漏洞利用模块，点击条目进入对应利用界面',
                      style: AppTextStyles.caption(
                        size: 14,
                        color: AppColors.cyan,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilterChip(
              label: const Text('全部'),
              selected: allSelected,
              onSelected: (_) => _selectAllMaturities(),
            ),
            for (final maturity in ExpMaturity.values)
              FilterChip(
                label: Text(maturity.label),
                selected: _selectedMaturities.contains(maturity),
                selectedColor: maturity.color.withValues(alpha: 0.18),
                checkmarkColor: maturity.color,
                side: BorderSide(color: maturity.color.withValues(alpha: 0.35)),
                onSelected: (_) => _toggleMaturity(maturity),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: entries.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final e = entries[index];
              return _ExpEntryCard(
                icon: e.icon,
                title: e.title,
                subtitle: e.subtitle,
                tag: e.tag,
                maturity: e.maturity,
                onTap: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => e.page)),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ExpEntryCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String tag;
  final ExpMaturity maturity;
  final VoidCallback? onTap;

  const _ExpEntryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tag,
    required this.maturity,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: enabled
                ? AppColors.bgCard
                : AppColors.bgCard.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.5),
                  ),
                ),
                child: Icon(icon, color: AppColors.primary, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.heading(
                        size: 15,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption(
                        size: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                alignment: WrapAlignment.end,
                children: [
                  _EntryPill(label: maturity.label, color: maturity.color),
                  _EntryPill(label: tag, color: AppColors.textSecondary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EntryPill extends StatelessWidget {
  final String label;
  final Color color;

  const _EntryPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(label, style: AppTextStyles.caption(size: 12, color: color)),
    );
  }
}
