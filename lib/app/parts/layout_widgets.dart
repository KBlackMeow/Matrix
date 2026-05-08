import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../localization.dart';

class MenuItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const MenuItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

class SidebarMenuItem extends StatefulWidget {
  final MenuItem item;
  final bool isSelected;
  final double expandProgress;
  final VoidCallback onTap;
  final String? overrideLabel;

  const SidebarMenuItem({
    super.key,
    required this.item,
    required this.isSelected,
    required this.expandProgress,
    required this.onTap,
    this.overrideLabel,
  });

  @override
  State<SidebarMenuItem> createState() => _SidebarMenuItemState();
}

class _SidebarMenuItemState extends State<SidebarMenuItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final labelOpacity = ((widget.expandProgress - 0.3) / 0.5).clamp(0.0, 1.0);
    final horizontalPadding = 12.0 + widget.expandProgress * 4.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            padding: EdgeInsets.symmetric(
              vertical: 12,
              horizontal: horizontalPadding,
            ),
            decoration: BoxDecoration(
              color: _hovered && !widget.isSelected
                  ? AppColors.primary.withValues(alpha: 0.06)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  widget.isSelected ? widget.item.selectedIcon : widget.item.icon,
                  size: 22,
                  color: widget.isSelected ? AppColors.primary : AppColors.textSecondary,
                ),
                Expanded(
                  child: Opacity(
                    opacity: labelOpacity,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Text(
                        widget.overrideLabel ?? widget.item.label,
                        style: TextStyle(
                          color: widget.isSelected ? AppColors.primary : AppColors.textSecondary,
                          fontSize: 14,
                          fontWeight: widget.isSelected ? FontWeight.w500 : FontWeight.normal,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 工作区内容区域
class WorkspaceContent extends StatelessWidget {
  final String title;

  const WorkspaceContent({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 欢迎卡片
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.5),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  blurRadius: 24,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  S.workspaceWelcomeTitle,
                  style: AppTextStyles.terminal(size: 22, color: AppColors.primary),
                ),
                const SizedBox(height: 8),
                Text(
                  S.workspaceWelcomeSubtitle(title),
                  style: AppTextStyles.body(size: 14, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // 快捷入口
          Text(
            S.workspaceQuickActions,
            style: AppTextStyles.heading(size: 16, color: AppColors.primary),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _QuickActionCard(
                icon: Icons.add_circle_outline,
                label: S.quickActionNew,
                color: AppColors.primary,
              ),
              const SizedBox(width: 16),
              _QuickActionCard(
                icon: Icons.upload_file,
                label: S.quickActionUpload,
                color: AppColors.cyan,
              ),
              const SizedBox(width: 16),
              _QuickActionCard(
                icon: Icons.folder_open,
                label: S.quickActionOpen,
                color: AppColors.red,
              ),
            ],
          ),
          const SizedBox(height: 32),
          // 最近活动
          Text(
            S.workspaceRecentActivities,
            style: AppTextStyles.heading(size: 16, color: AppColors.primary),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.border,
                width: 1,
              ),
            ),
            child: Column(
              children: List.generate(
                4,
                (index) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.bgElevated,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.4),
                            width: 1,
                          ),
                        ),
                        child: Icon(
                          [Icons.edit, Icons.folder, Icons.insert_drive_file, Icons.share][index],
                          color: AppColors.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              S.recentFileTitle(index + 1),
                              style: AppTextStyles.body(size: 14, color: AppColors.textPrimary),
                            ),
                            Text(
                              S.recentHoursAgo(2 + index),
                              style: AppTextStyles.caption(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () {},
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.border,
                width: 1,
              ),
            ),
            child: Column(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: color.withValues(alpha: 0.5),
                      width: 1,
                    ),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(height: 12),
                Text(
                  label,
                  style: AppTextStyles.body(color: AppColors.textPrimary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 赛博风格点阵网格背景（静态，零性能消耗）
class CyberGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.035)
      ..strokeWidth = 1;
    const spacing = 28.0;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(CyberGridPainter old) => false;
}
