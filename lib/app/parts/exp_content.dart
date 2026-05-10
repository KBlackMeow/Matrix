import 'package:flutter/material.dart';

import '../../models/project.dart';
import '../../theme/app_theme.dart';
import '../localization.dart';
import 'exp_registry.dart';

class ExpContent extends StatelessWidget {
  final Project project;
  final VoidCallback onSwitchProject;

  const ExpContent({
    super.key,
    required this.project,
    required this.onSwitchProject,
  });

  @override
  Widget build(BuildContext context) {
    final entries = visibleExpEntries();
    final defaultTargetUrl = project.domain.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.5),
                  ),
                ),
                child: const Icon(
                  Icons.bug_report,
                  color: AppColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      S.expManagementScopedTitle(project.name),
                      style: AppTextStyles.heading(
                        size: 15,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      project.domain,
                      style: AppTextStyles.caption(
                        size: 13,
                        color: AppColors.cyan,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: onSwitchProject,
                icon: const Icon(
                  Icons.swap_horiz,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                label: Text(
                  S.btnSwitchProject,
                  style: AppTextStyles.caption(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              S.expManagementHint,
              style: AppTextStyles.caption(
                size: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ),
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
                versionRequirement: e.versionRequirement,
                tag: e.tag,

                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => e.pageBuilder(defaultTargetUrl),
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

class _ExpEntryCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String versionRequirement;
  final String tag;
  final VoidCallback? onTap;

  const _ExpEntryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.versionRequirement,
    required this.tag,
    required this.onTap,
  });

  @override
  State<_ExpEntryCard> createState() => _ExpEntryCardState();
}

class _ExpEntryCardState extends State<_ExpEntryCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
      onExit: enabled ? (_) => setState(() => _hovered = false) : null,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: !enabled
                ? AppColors.bgCard.withValues(alpha: 0.7)
                : _hovered
                    ? AppColors.bgElevated
                    : AppColors.bgCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hovered && enabled
                  ? AppColors.primary.withValues(alpha: 0.55)
                  : AppColors.border,
              width: _hovered && enabled ? 1.2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(
                  alpha: _hovered && enabled ? 0.14 : 0.0,
                ),
                blurRadius: 14,
                spreadRadius: 0,
              ),
            ],
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
                child: Icon(widget.icon, color: AppColors.primary, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.heading(
                        size: 15,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption(
                        size: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      S.expVersionRequirement(widget.versionRequirement),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption(
                        size: 12,
                        color: AppColors.cyan.withValues(alpha: 0.95),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _EntryPill(label: widget.tag, color: AppColors.textSecondary),
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
