import 'dart:math';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/localization.dart';
import '../../models/project.dart';
import '../../pages/frp_tunnel_page.dart';
import '../../pages/payload_management_page.dart';
import '../../pages/project_management_page.dart';
import '../../pages/project_scoped_page.dart';
import '../../pages/reverse_shell_dashboard_page.dart';
import '../../pages/suo5_proxy_page.dart';
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

class _MainLayoutState extends State<MainLayout> {
  int _selectedIndex = 0;
  Project? _selectedProject;
  bool _sidebarExpanded = true;
  bool _sidebarHidden = false;
  String? _packageVersionLabel;
  static const double _sidebarWidth = 220.0;
  static const double _sidebarCollapsedWidth = 72.0;
  static const double _menuItemExtent = 56.0;

  // 子页面用 RepaintBoundary 包裹以隔离重绘域；切换 IndexedStack 时复用 GPU layer。
  // 每当 _selectedProject 或语言变化时，整体重建一次 _pages：
  //   • 同 runtimeType + 同位置 → State 自动复用，不会丢失会话/输入；
  //   • 而 const 单例的子页面树会被 Flutter 视为「未变化」从而跳过重建，导致语言切换后子页面文本不刷新。
  late ProjectManagementPage _projectPage;
  late ProjectScopedPage _webshellPage;
  late ProjectScopedPage _expPage;
  late ProjectScopedPage _suo5Page;
  late RepaintBoundary _projectBoundary;
  late RepaintBoundary _webshellBoundary;
  late RepaintBoundary _expBoundary;
  late RepaintBoundary _suo5Boundary;
  late List<Widget> _staticPages;
  late List<Widget> _pages;

  final List<MenuItem> _menuItems = [
    MenuItem(
      icon: Icons.folder_outlined,
      label: '',
      selectedIcon: Icons.folder,
    ),
    MenuItem(
      icon: Icons.terminal_outlined,
      label: '',
      selectedIcon: Icons.terminal,
    ),
    MenuItem(
      icon: Icons.bug_report_outlined,
      label: '',
      selectedIcon: Icons.bug_report,
    ),
    MenuItem(icon: Icons.code_outlined, label: '', selectedIcon: Icons.code),
    MenuItem(
      icon: Icons.computer_outlined,
      label: '',
      selectedIcon: Icons.computer,
    ),
    MenuItem(
      icon: Icons.alt_route_outlined,
      label: '',
      selectedIcon: Icons.alt_route,
    ),
    MenuItem(
      icon: Icons.sync_alt_outlined,
      label: '',
      selectedIcon: Icons.sync_alt,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _rebuildDynamicPages();
    AppLanguageController.notifier.addListener(_onLanguageChanged);
    PackageInfo.fromPlatform().then((info) {
      if (!mounted) return;
      setState(() {
        _packageVersionLabel = info.version;
      });
    });
  }

  @override
  void dispose() {
    AppLanguageController.notifier.removeListener(_onLanguageChanged);
    super.dispose();
  }

  void _onLanguageChanged() {
    if (!mounted) return;
    setState(_rebuildDynamicPages);
  }

  void _rebuildDynamicPages() {
    _projectPage = ProjectManagementPage(
      selectedProject: _selectedProject,
      onEnterExp: (project) {
        setState(() {
          _selectedProject = project;
          _selectedIndex = 2;
          _rebuildDynamicPages();
        });
      },
      onEnterWebshell: (project) {
        setState(() {
          _selectedProject = project;
          _selectedIndex = 1;
          _rebuildDynamicPages();
        });
      },
      onEnterSuo5: (project) {
        setState(() {
          _selectedProject = project;
          _selectedIndex = 6;
          _rebuildDynamicPages();
        });
      },
      onProjectUpdated: (project) {
        setState(() {
          if (_selectedProject?.id == project.id) {
            _selectedProject = project;
          }
          _rebuildDynamicPages();
        });
      },
      onProjectDeleted: (projectId) {
        setState(() {
          if (_selectedProject?.id == projectId) {
            _selectedProject = null;
          }
          _rebuildDynamicPages();
        });
      },
    );
    _webshellPage = ProjectScopedPage(
      selectedProject: _selectedProject,
      onSelectProject: (p) {
        setState(() {
          _selectedProject = p;
          _rebuildDynamicPages();
        });
      },
      onClearProject: () {
        setState(() {
          _selectedProject = null;
          _rebuildDynamicPages();
        });
      },
      onNavigateToProjectManagement: () {
        setState(() {
          _selectedIndex = 0;
          _selectedProject = null;
          _rebuildDynamicPages();
        });
      },
      title: S.titleWebshellManager,
      icon: Icons.terminal,
      contentBuilder: (project, onSwitchProject) => WebshellManagementPage(
        project: project,
        onSwitchProject: onSwitchProject,
      ),
    );
    _projectBoundary = RepaintBoundary(child: _projectPage);
    _webshellBoundary = RepaintBoundary(child: _webshellPage);
    _expPage = ProjectScopedPage(
      selectedProject: _selectedProject,
      onSelectProject: (p) {
        setState(() {
          _selectedProject = p;
          _rebuildDynamicPages();
        });
      },
      onClearProject: () {
        setState(() {
          _selectedProject = null;
          _rebuildDynamicPages();
        });
      },
      onNavigateToProjectManagement: () {
        setState(() {
          _selectedIndex = 0;
          _selectedProject = null;
          _rebuildDynamicPages();
        });
      },
      title: S.menuExp,
      icon: Icons.bug_report,
      contentBuilder: (project, onSwitchProject) => exp.ExpContent(
        project: project,
        onSwitchProject: onSwitchProject,
      ),
    );
    _expBoundary = RepaintBoundary(child: _expPage);
    _suo5Page = ProjectScopedPage(
      selectedProject: _selectedProject,
      onSelectProject: (p) {
        setState(() {
          _selectedProject = p;
          _rebuildDynamicPages();
        });
      },
      onClearProject: () {
        setState(() {
          _selectedProject = null;
          _rebuildDynamicPages();
        });
      },
      onNavigateToProjectManagement: () {
        setState(() {
          _selectedIndex = 0;
          _selectedProject = null;
          _rebuildDynamicPages();
        });
      },
      title: S.titleSuo5Manager,
      icon: Icons.sync_alt,
      contentBuilder: (project, onSwitchProject) => Suo5ProxyPage(
        project: project,
        onSwitchProject: onSwitchProject,
      ),
    );
    _suo5Boundary = RepaintBoundary(child: _suo5Page);
    // 注意：每次都 new 一份非 const 实例，确保语言变化时 Flutter 会下钻 build()
    // （const 单例会被 widget 比对识为未变更，从而跳过子树重建）。
    _staticPages = <Widget>[
      _expBoundary,
      RepaintBoundary(child: PayloadManagementPage()),
      RepaintBoundary(child: ReverseShellDashboardPage()),
      RepaintBoundary(child: FrpTunnelPage()),
      _suo5Boundary,
    ];
    _pages = [_projectBoundary, _webshellBoundary, ..._staticPages];
  }

  void _handleMenuTap(int index) {
    setState(() => _selectedIndex = index);
  }

  String _menuLabelForIndex(int index) {
    switch (index) {
      case 0:
        return S.menuProject;
      case 1:
        return S.menuWebshell;
      case 2:
        return S.menuExp;
      case 3:
        return S.menuPayload;
      case 4:
        return S.menuTerminal;
      case 5:
        return S.menuFrp;
      case 6:
        return S.menuSuo5;
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.sizeOf(context).width < 720;
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
                  // 赛博网格背景：独立 layer，初次光栅化后永久缓存
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: CustomPaint(painter: CyberGridPainter()),
                    ),
                  ),
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 顶部栏：独立 layer，标题变化不触发内容区重绘
                          RepaintBoundary(
                            child: Container(
                              height: 64,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.bgElevated,
                                border: Border(
                                  bottom: BorderSide(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.5,
                                    ),
                                    width: 1,
                                  ),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.06,
                                    ),
                                    blurRadius: 12,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    '>_ ',
                                    style: AppTextStyles.terminal(
                                      size: 14,
                                      color: AppColors.primary.withValues(
                                        alpha: 0.5,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    _menuLabelForIndex(_selectedIndex),
                                    style: AppTextStyles.heading(
                                      size: 18,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                  const Spacer(),
                                  PopupMenuButton<AppLanguage>(
                                    icon: const Icon(Icons.settings),
                                    color: AppColors.bgElevated,
                                    onSelected: (lang) {
                                      // 真正的重建已由 _onLanguageChanged 监听处理。
                                      AppLanguageController.setLanguage(lang);
                                    },
                                    itemBuilder: (context) => [
                                      PopupMenuItem<AppLanguage>(
                                        value: AppLanguage.zh,
                                        child: Text(S.languageChinese),
                                      ),
                                      PopupMenuItem<AppLanguage>(
                                        value: AppLanguage.ja,
                                        child: Text(S.languageJapanese),
                                      ),
                                      PopupMenuItem<AppLanguage>(
                                        value: AppLanguage.en,
                                        child: Text(S.languageEnglish),
                                      ),
                                    ],
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.search),
                                    onPressed: () {},
                                    color: AppColors.textSecondary,
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.notifications_outlined,
                                    ),
                                    onPressed: () {},
                                    color: AppColors.textSecondary,
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: AppColors.primary.withValues(
                                          alpha: 0.6,
                                        ),
                                        width: 1.5,
                                      ),
                                      color: AppColors.primary.withValues(
                                        alpha: 0.1,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.primary.withValues(
                                            alpha: 0.2,
                                          ),
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
                          ),
                          // 工作区内容：expand 给子页面紧约束 → relayout boundary
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: IndexedStack(
                                index: _selectedIndex,
                                sizing: StackFit.expand,
                                children: _pages,
                              ),
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

          // 手机端：菜单展开时的遮罩
          if (isMobile && !_sidebarHidden)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _sidebarHidden = true),
                child: Container(color: Colors.black.withValues(alpha: 0.4)),
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
            child: RepaintBoundary(child: _buildSidebar()),
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
                  icon: const Icon(
                    Icons.chevron_right,
                    color: AppColors.textSecondary,
                  ),
                  tooltip: S.sidebarExpandTooltip,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final t =
            ((constraints.maxWidth - _sidebarCollapsedWidth) /
                    (_sidebarWidth - _sidebarCollapsedWidth))
                .clamp(0.0, 1.0);
        return _buildSidebarContent(t);
      },
    );
  }

  Widget _buildSidebarContent(double t) {
    // Label elements fade in during the second half of expansion
    final labelOpacity = ((t - 0.3) / 0.5).clamp(0.0, 1.0);
    final logoAreaHorizontalPadding = 8.0 + 8.0 * t;
    final logoSize = 34.0 + 12.0 * t;

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
              padding: EdgeInsets.symmetric(
                horizontal: logoAreaHorizontalPadding,
              ),
              child: Row(
                children: [
                  Container(
                    width: logoSize,
                    height: logoSize,
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: const Padding(
                      padding: EdgeInsets.all(2),
                      child: Image(
                        image: AssetImage('assets/icon/icon_square.png'),
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  if (t > 0.1)
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
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              child: Stack(
                children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeInOutCubic,
                    top: _selectedIndex * _menuItemExtent,
                    left: 0,
                    right: 0,
                    height: _menuItemExtent,
                    child: IgnorePointer(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ),
                  ListView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    itemCount: _menuItems.length,
                    itemExtent: _menuItemExtent,
                    itemBuilder: (context, index) {
                      final item = _menuItems[index];
                      final isSelected = _selectedIndex == index;
                      return RepaintBoundary(
                        child: SidebarMenuItem(
                          item: item,
                          isSelected: isSelected,
                          expandProgress: t,
                          onTap: () => _handleMenuTap(index),
                          overrideLabel: _menuLabelForIndex(index),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          if (t > 0.15 && _packageVersionLabel != null)
            Opacity(
              opacity: labelOpacity,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'v$_packageVersionLabel',
                    style: AppTextStyles.caption(
                      size: 11,
                      color:
                          AppColors.textSecondary.withValues(alpha: 0.72),
                    ),
                  ),
                ),
              ),
            ),

          // 折叠按钮 — 箭头随动画旋转，文字渐显
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: InkWell(
              onTap: () => setState(() => _sidebarExpanded = !_sidebarExpanded),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 12,
                ),
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
                            S.sidebarCollapse,
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
