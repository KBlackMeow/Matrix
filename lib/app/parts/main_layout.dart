import 'dart:math';

import 'package:flutter/material.dart';

import '../../models/project.dart';
import '../../pages/dictionary_management_page.dart';
import '../../pages/frp_tunnel_page.dart';
import '../../pages/info_collection_page.dart';
import '../../pages/payload_management_page.dart';
import '../../pages/project_management_page.dart';
import '../../pages/project_scoped_page.dart';
import '../../pages/reverse_shell_dashboard_page.dart';
import '../../pages/webshell_management_page.dart';
import '../../theme/app_theme.dart';
import 'exp_content.dart' as exp;
import 'layout_widgets.dart';

/// 主布局：左侧菜单栏 + 右侧工作区
class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> with TickerProviderStateMixin {
  int _selectedIndex = 0;
  Project? _selectedProject;
  bool _sidebarExpanded = true;
  bool _sidebarHidden = false;
  static const double _sidebarWidth = 220.0;
  static const double _sidebarCollapsedWidth = 72.0;

  late final AnimationController _blinkController;
  late final Animation<double> _blinkAnimation;

  final List<MenuItem> _menuItems = [
    MenuItem(icon: Icons.folder_outlined, label: '项目管理', selectedIcon: Icons.folder),
    MenuItem(icon: Icons.search_outlined, label: '信息收集', selectedIcon: Icons.search),
    MenuItem(icon: Icons.terminal_outlined, label: 'Webshell管理', selectedIcon: Icons.terminal),
    MenuItem(icon: Icons.bug_report_outlined, label: 'EXP管理', selectedIcon: Icons.bug_report),
    MenuItem(icon: Icons.code_outlined, label: 'Payload管理', selectedIcon: Icons.code),
    MenuItem(icon: Icons.menu_book_outlined, label: '字典管理', selectedIcon: Icons.menu_book),
    MenuItem(icon: Icons.computer_outlined, label: '完整终端', selectedIcon: Icons.computer),
    MenuItem(icon: Icons.alt_route_outlined, label: 'FRP隧道', selectedIcon: Icons.alt_route),
  ];

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _blinkAnimation = CurvedAnimation(parent: _blinkController, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _blinkController.dispose();
    super.dispose();
  }

  void _handleMenuTap(int index) {
    setState(() => _selectedIndex = index);
  }

  Widget _buildWorkspaceContent() {
    if (_selectedIndex == 0) {
      return ProjectManagementPage(
        selectedProject: _selectedProject,
        onEnterInfoCollection: (project) {
          setState(() {
            _selectedProject = project;
            _selectedIndex = 1;
          });
        },
        onEnterExp: (project) {
          setState(() {
            _selectedIndex = 3;
          });
        },
        onEnterWebshell: (project) {
          setState(() {
            _selectedProject = project;
            _selectedIndex = 2;
          });
        },
      );
    }
    if (_selectedIndex == 1) {
      return ProjectScopedPage(
        selectedProject: _selectedProject,
        onSelectProject: (p) => setState(() => _selectedProject = p),
        onClearProject: () => setState(() => _selectedProject = null),
        onNavigateToProjectManagement: () => setState(() {
          _selectedIndex = 0;
          _selectedProject = null;
        }),
        title: '信息收集',
        icon: Icons.search,
        contentBuilder: (project, onSwitchProject) =>
            InfoCollectionLandingPage(project: project, onSwitchProject: onSwitchProject),
      );
    }
    if (_selectedIndex == 2) {
      return ProjectScopedPage(
        selectedProject: _selectedProject,
        onSelectProject: (p) => setState(() => _selectedProject = p),
        onClearProject: () => setState(() => _selectedProject = null),
        onNavigateToProjectManagement: () => setState(() {
          _selectedIndex = 0;
          _selectedProject = null;
        }),
        title: 'Webshell管理',
        icon: Icons.terminal,
        contentBuilder: (project, onSwitchProject) =>
            WebshellManagementPage(project: project, onSwitchProject: onSwitchProject),
      );
    }
    if (_selectedIndex == 4) {
      return const PayloadManagementPage();
    }
    if (_selectedIndex == 3) {
      return const exp.ExpContent();
    }
    if (_selectedIndex == 5) {
      return const DictionaryManagementPage();
    }
    if (_selectedIndex == 6) {
      return const ReverseShellDashboardPage();
    }
    if (_selectedIndex == 7) {
      return const FrpTunnelPage();
    }
    return WorkspaceContent(title: _menuItems[_selectedIndex].label);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isMobile = constraints.maxWidth < 720;

        return Scaffold(
          body: Stack(
            children: [
              // 右侧工作区（底层）
              Positioned.fill(
                left: !isMobile && !_sidebarHidden
                    ? (_sidebarExpanded ? _sidebarWidth : _sidebarCollapsedWidth)
                    : 0,
                child: Container(
                  color: AppColors.bgDark,
                  child: Stack(
                    children: [
                      // 赛博网格背景
                      Positioned.fill(
                        child: CustomPaint(painter: CyberGridPainter()),
                      ),
                      Positioned.fill(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // 顶部栏
                            Container(
                              height: 64,
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              decoration: BoxDecoration(
                                color: AppColors.bgElevated,
                                border: Border(
                                  bottom: BorderSide(
                                    color: AppColors.primary.withValues(alpha: 0.5),
                                    width: 1,
                                  ),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary.withValues(alpha: 0.06),
                                    blurRadius: 12,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  // 闪烁状态点
                                  AnimatedBuilder(
                                    animation: _blinkAnimation,
                                    builder: (_, _) => Container(
                                      width: 8,
                                      height: 8,
                                      margin: const EdgeInsets.only(right: 10),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: AppColors.primary.withValues(
                                          alpha: 0.5 + _blinkAnimation.value * 0.5,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppColors.primary.withValues(
                                              alpha: _blinkAnimation.value * 0.7,
                                            ),
                                            blurRadius: 8,
                                            spreadRadius: 1,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '>_ ',
                                    style: AppTextStyles.terminal(
                                      size: 14,
                                      color: AppColors.primary.withValues(alpha: 0.5),
                                    ),
                                  ),
                                  Text(
                                    _menuItems[_selectedIndex].label,
                                    style: AppTextStyles.heading(
                                      size: 18,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                  const Spacer(),
                                  IconButton(
                                    icon: const Icon(Icons.search),
                                    onPressed: () {},
                                    color: AppColors.textSecondary,
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.notifications_outlined),
                                    onPressed: () {},
                                    color: AppColors.textSecondary,
                                  ),
                                  const SizedBox(width: 8),
                                  // 黑客风格用户头像
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: AppColors.primary.withValues(alpha: 0.6),
                                        width: 1.5,
                                      ),
                                      color: AppColors.primary.withValues(alpha: 0.1),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.primary.withValues(alpha: 0.2),
                                          blurRadius: 8,
                                        ),
                                      ],
                                    ),
                                    child: Center(
                                      child: Text(
                                        'R',
                                        style: AppTextStyles.heading(
                                          size: 14,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // 工作区内容
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: _buildWorkspaceContent(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 手机端：菜单展开时的遮罩
              if (isMobile && !_sidebarHidden)
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => setState(() => _sidebarHidden = true),
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.4),
                    ),
                  ),
                ),

              // 左侧菜单栏（上层，用位移动画实现侧滑）
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                top: 0,
                bottom: 0,
                left: _sidebarHidden ? -_sidebarWidth : 0,
                width: _sidebarExpanded ? _sidebarWidth : _sidebarCollapsedWidth,
                child: _buildSidebar(),
              ),

              // 桌面端：隐藏后的展开按钮
              if (!isMobile && _sidebarHidden)
                Positioned(
                  left: 0,
                  top: 16,
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 20,
                      splashRadius: 20,
                      onPressed: () => setState(() => _sidebarHidden = false),
                      icon: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
                      tooltip: '展开菜单',
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSidebar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final t = ((constraints.maxWidth - _sidebarCollapsedWidth) /
                (_sidebarWidth - _sidebarCollapsedWidth))
            .clamp(0.0, 1.0);
        return _buildSidebarContent(t);
      },
    );
  }

  Widget _buildSidebarContent(double t) {
    // Label elements fade in during the second half of expansion
    final labelOpacity = ((t - 0.3) / 0.5).clamp(0.0, 1.0);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgDark,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // Logo area — icon always left-aligned, title + close fade in
          SizedBox(
            height: 64,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.primary,
                        width: 1,
                      ),
                    ),
                    child: const Icon(
                      Icons.grid_view_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  Expanded(
                    child: Opacity(
                      opacity: labelOpacity,
                      child: Row(
                        children: [
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Matrix',
                              style: AppTextStyles.title(
                                size: 20,
                                color: AppColors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const Divider(height: 1, color: AppColors.border),

          // 菜单项
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              itemCount: _menuItems.length,
              itemBuilder: (context, index) {
                final item = _menuItems[index];
                final isSelected = _selectedIndex == index;
                return SidebarMenuItem(
                  item: item,
                  isSelected: isSelected,
                  expandProgress: t,
                  onTap: () => _handleMenuTap(index),
                );
              },
            ),
          ),

          // 折叠按钮 — 箭头随动画旋转，文字渐显
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: InkWell(
              onTap: () => setState(() => _sidebarExpanded = !_sidebarExpanded),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Transform.rotate(
                      angle: t * pi,
                      child: const Icon(
                        Icons.chevron_right,
                        color: AppColors.textSecondary,
                        size: 24,
                      ),
                    ),
                    Flexible(
                      child: Opacity(
                        opacity: labelOpacity,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: Text(
                            '收起',
                            style: AppTextStyles.caption(
                              size: 14,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
