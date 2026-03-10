import 'dart:math';

import 'package:flutter/material.dart';

import 'database/database_helper.dart';
import 'database/database_init.dart';
import 'models/project.dart';
import 'pages/project_management_page.dart';
import 'pages/project_scoped_page.dart';
import 'pages/webshell_management_page.dart';
import 'pages/payload_management_page.dart';
import 'pages/dictionary_management_page.dart';
import 'services/seed_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initDatabase(); // 初始化 SQLite（桌面端使用 FFI）
  await SeedService.seed(DatabaseHelper()); // 首次启动种子化内置默认数据
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Matrix',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.dark(
          primary: AppColors.primary,
          surface: AppColors.bgDark,
          onSurface: AppColors.textPrimary,
        ),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const MainLayout(),
    );
  }
}

/// 主布局：左侧菜单栏 + 右侧工作区
class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _selectedIndex = 0;
  Project? _selectedProject;
  bool _sidebarExpanded = true;
  bool _sidebarHidden = false;
  static const double _sidebarWidth = 220.0;
   // 收起时的窄侧栏宽度
  static const double _sidebarCollapsedWidth = 72.0;

  final List<MenuItem> _menuItems = [
    MenuItem(icon: Icons.folder_outlined, label: '项目管理', selectedIcon: Icons.folder),
    MenuItem(icon: Icons.search_outlined, label: '信息收集', selectedIcon: Icons.search),
    MenuItem(icon: Icons.bug_report_outlined, label: 'EXP管理', selectedIcon: Icons.bug_report),
    MenuItem(icon: Icons.terminal_outlined, label: 'Webshell管理', selectedIcon: Icons.terminal),
    MenuItem(icon: Icons.code_outlined, label: 'Payload管理', selectedIcon: Icons.code),
    MenuItem(icon: Icons.menu_book_outlined, label: '字典管理', selectedIcon: Icons.menu_book),
  ];

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
            _selectedProject = project;
            _selectedIndex = 2;
          });
        },
        onEnterWebshell: (project) {
          setState(() {
            _selectedProject = project;
            _selectedIndex = 3;
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
            _InfoCollectionContent(project: project, onSwitchProject: onSwitchProject),
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
        title: 'EXP管理',
        icon: Icons.bug_report,
        contentBuilder: (project, onSwitchProject) =>
            _ExpContent(project: project, onSwitchProject: onSwitchProject),
      );
    }
    if (_selectedIndex == 3) {
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
    if (_selectedIndex == 5) {
      return const DictionaryManagementPage();
    }
    return _WorkspaceContent(title: _menuItems[_selectedIndex].label);
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
                              color: AppColors.primary.withValues(alpha: 0.4),
                              width: 1,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
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
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: AppColors.border,
                              child: Text(
                                'U',
                                style: AppTextStyles.heading(
                                  size: 14,
                                  color: AppColors.primary,
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
                          IconButton(
                            padding: EdgeInsets.zero,
                            iconSize: 18,
                            splashRadius: 18,
                            onPressed: labelOpacity > 0.5
                                ? () => setState(() => _sidebarHidden = true)
                                : null,
                            icon: const Icon(Icons.close, color: AppColors.textSecondary),
                            tooltip: '隐藏菜单',
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
                return _SidebarMenuItem(
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

class _InfoCollectionContent extends StatelessWidget {
  final Project project;
  final VoidCallback onSwitchProject;

  const _InfoCollectionContent({
    required this.project,
    required this.onSwitchProject,
  });

  @override
  Widget build(BuildContext context) {
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
              const Icon(Icons.search, color: AppColors.primary, size: 32),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '信息收集 · ${project.name}',
                      style: AppTextStyles.heading(size: 18, color: AppColors.primary),
                    ),
                    Text(
                      project.domain,
                      style: AppTextStyles.caption(size: 14, color: AppColors.cyan),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: onSwitchProject,
                icon: const Icon(Icons.swap_horiz, size: 18, color: AppColors.textSecondary),
                label: Text('切换项目', style: AppTextStyles.caption(color: AppColors.textSecondary)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: Text(
            '> 信息收集功能开发中...',
            style: AppTextStyles.terminal(size: 14, color: AppColors.textMuted),
          ),
        ),
      ],
    );
  }
}


class _ExpContent extends StatelessWidget {
  final Project project;
  final VoidCallback onSwitchProject;

  const _ExpContent({
    required this.project,
    required this.onSwitchProject,
  });

  @override
  Widget build(BuildContext context) {
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
                      'EXP管理 · ${project.name}',
                      style: AppTextStyles.heading(size: 18, color: AppColors.primary),
                    ),
                    Text(
                      project.domain,
                      style: AppTextStyles.caption(size: 14, color: AppColors.cyan),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: onSwitchProject,
                icon: const Icon(Icons.swap_horiz, size: 18, color: AppColors.textSecondary),
                label: Text('切换项目', style: AppTextStyles.caption(color: AppColors.textSecondary)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: Text(
            '> EXP 管理功能开发中...',
            style: AppTextStyles.terminal(size: 14, color: AppColors.textMuted),
          ),
        ),
      ],
    );
  }
}

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

class _SidebarMenuItem extends StatelessWidget {
  final MenuItem item;
  final bool isSelected;
  final double expandProgress;
  final VoidCallback onTap;

  const _SidebarMenuItem({
    required this.item,
    required this.isSelected,
    required this.expandProgress,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final labelOpacity = ((expandProgress - 0.3) / 0.5).clamp(0.0, 1.0);
    final horizontalPadding = 12.0 + expandProgress * 4.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: EdgeInsets.symmetric(
              vertical: 12,
              horizontal: horizontalPadding,
            ),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.bgCard : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  isSelected ? item.selectedIcon : item.icon,
                  size: 22,
                  color: isSelected ? AppColors.primary : AppColors.textSecondary,
                ),
                Expanded(
                  child: Opacity(
                    opacity: labelOpacity,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Text(
                        item.label,
                        style: TextStyle(
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.textSecondary,
                          fontSize: 14,
                          fontWeight:
                              isSelected ? FontWeight.w500 : FontWeight.normal,
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
class _WorkspaceContent extends StatelessWidget {
  final String title;

  const _WorkspaceContent({required this.title});

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
                  '> 欢迎使用 Matrix',
                  style: AppTextStyles.terminal(size: 22, color: AppColors.primary),
                ),
                const SizedBox(height: 8),
                Text(
                  '当前页面：$title · 开始您的工作吧',
                  style: AppTextStyles.body(size: 14, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // 快捷入口
          Text(
            '快捷入口',
            style: AppTextStyles.heading(size: 16, color: AppColors.primary),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _QuickActionCard(
                icon: Icons.add_circle_outline,
                label: '新建',
                color: AppColors.primary,
              ),
              const SizedBox(width: 16),
              _QuickActionCard(
                icon: Icons.upload_file,
                label: '上传',
                color: AppColors.cyan,
              ),
              const SizedBox(width: 16),
              _QuickActionCard(
                icon: Icons.folder_open,
                label: '打开',
                color: AppColors.red,
              ),
            ],
          ),
          const SizedBox(height: 32),
          // 最近活动
          Text(
            '最近活动',
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
                              '项目文件 ${index + 1}',
                              style: AppTextStyles.body(size: 14, color: AppColors.textPrimary),
                            ),
                            Text(
                              '${2 + index} 小时前',
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
