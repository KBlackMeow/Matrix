import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/webshell.dart';
import '../services/webshell_service.dart';
import '../theme/app_theme.dart';

// ─── 主页面 ───────────────────────────────────────────────────────────────────

class WebshellInteractivePage extends StatefulWidget {
  final Webshell webshell;

  const WebshellInteractivePage({super.key, required this.webshell});

  @override
  State<WebshellInteractivePage> createState() =>
      _WebshellInteractivePageState();
}

class _WebshellInteractivePageState extends State<WebshellInteractivePage>
    with SingleTickerProviderStateMixin {
  late final WebshellService _service;
  late final TabController _tabController;
  bool _isConnected = false;
  bool _isChecking = true;

  @override
  void initState() {
    super.initState();
    _service = WebshellService(widget.webshell);
    _tabController = TabController(length: 3, vsync: this);
    _checkConnection();
  }

  Future<void> _checkConnection() async {
    setState(() => _isChecking = true);
    final alive = await _service.ping();
    if (mounted) {
      setState(() {
        _isConnected = alive;
        _isChecking = false;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Column(
        children: [
          _buildHeader(),
          _buildTabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _TerminalTab(service: _service),
                _FileManagerTab(service: _service),
                _SystemInfoTab(service: _service),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        border: Border(
          bottom: BorderSide(color: AppColors.primary.withValues(alpha: 0.35)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(
              Icons.arrow_back_ios_new,
              color: AppColors.textSecondary,
              size: 17,
            ),
            tooltip: '返回',
          ),
          const SizedBox(width: 4),
          // Status dot
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isChecking
                  ? AppColors.amber
                  : _isConnected
                  ? AppColors.primary
                  : AppColors.red,
              boxShadow: (!_isChecking && _isConnected)
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.7),
                        blurRadius: 8,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.webshell.name,
                  style: AppTextStyles.body(
                    size: 14,
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  widget.webshell.url,
                  style: AppTextStyles.caption(size: 11, color: AppColors.cyan),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (_isChecking)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.amber,
              ),
            ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: _isChecking ? null : _checkConnection,
            icon: const Icon(Icons.wifi_tethering_rounded, size: 15),
            label: Text(
              _isChecking
                  ? '检测中...'
                  : _isConnected
                  ? '已连接'
                  : '重新连接',
            ),
            style: TextButton.styleFrom(
              foregroundColor: _isConnected
                  ? AppColors.primary
                  : AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          _methodBadge(widget.webshell.method),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _methodBadge(String method) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.border,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: method == 'POST'
              ? AppColors.cyan.withValues(alpha: 0.5)
              : AppColors.amber.withValues(alpha: 0.5),
        ),
      ),
      child: Text(
        method,
        style: AppTextStyles.caption(
          size: 11,
          color: method == 'POST' ? AppColors.cyan : AppColors.amber,
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: AppColors.bgElevated,
      child: TabBar(
        controller: _tabController,
        indicatorColor: AppColors.primary,
        indicatorWeight: 2,
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: AppTextStyles.body(size: 13),
        tabs: const [
          Tab(icon: Icon(Icons.terminal, size: 15), text: '终  端'),
          Tab(icon: Icon(Icons.folder_open_outlined, size: 15), text: '文件管理'),
          Tab(icon: Icon(Icons.dns_outlined, size: 15), text: '系统信息'),
        ],
      ),
    );
  }
}

// ─── 终端 Tab ─────────────────────────────────────────────────────────────────

class _TerminalEntry {
  final String command;
  final String dir;
  final DateTime timestamp;
  String? output;

  _TerminalEntry({
    required this.command,
    required this.dir,
    required this.timestamp,
  });
}

class _TerminalTab extends StatefulWidget {
  final WebshellService service;

  const _TerminalTab({required this.service});

  @override
  State<_TerminalTab> createState() => _TerminalTabState();
}

class _TerminalTabState extends State<_TerminalTab>
    with AutomaticKeepAliveClientMixin {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _inputFocus = FocusNode();
  final List<_TerminalEntry> _entries = [];
  final List<String> _history = [];
  int _historyIndex = -1;
  bool _executing = false;

  /// false = 分离式（输出区 + 底部输入栏）
  /// true  = 一体式（输入嵌入输出流末尾，模拟真实终端）
  bool _integratedMode = false;
  String _currentDir = '~';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initDir();
  }

  Future<void> _initDir() async {
    final dir = await widget.service.getCurrentDir();
    if (mounted) setState(() => _currentDir = dir);
  }

  Future<void> _execute(String raw) async {
    final cmd = raw.trim();
    if (cmd.isEmpty) return;

    // 本地内置命令
    if (cmd == 'clear' || cmd == 'cls') {
      setState(() => _entries.clear());
      _inputController.clear();
      return;
    }

    // 加入历史
    if (_history.isEmpty || _history.last != cmd) _history.add(cmd);
    _historyIndex = -1;

    final entry = _TerminalEntry(
      command: cmd,
      dir: _currentDir,
      timestamp: DateTime.now(),
    );
    setState(() {
      _entries.add(entry);
      _executing = true;
    });
    _inputController.clear();
    _scrollToBottom(); // 立即跳转，显示 loading 指示器

    final output = await widget.service.executeCommand(cmd);

    // 如果是 cd 命令，刷新当前目录
    if (cmd.startsWith('cd ') || cmd == 'cd') {
      final newDir = await widget.service.getCurrentDir();
      if (mounted) setState(() => _currentDir = newDir);
    }

    if (mounted) {
      setState(() {
        entry.output = output.isEmpty ? '(无输出)' : output;
        _executing = false;
      });
      _scrollToBottom(animated: true); // 平滑滚动到最新输出
      // 执行完毕后恢复焦点
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _inputFocus.requestFocus();
      });
    }
  }

  /// [animated] = false → 立即跳转（提交命令时）
  /// [animated] = true  → 平滑滚动（输出返回后）
  void _scrollToBottom({bool animated = false}) {
    if (!animated) {
      // 单帧后立即跳转即可
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      });
      return;
    }
    // 等两帧：第一帧完成布局，第二帧 maxScrollExtent 才是最终值
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
        );
      });
    });
  }

  void _navigateHistory(bool up) {
    if (_history.isEmpty) return;
    setState(() {
      if (up) {
        _historyIndex = (_historyIndex + 1).clamp(0, _history.length - 1);
      } else {
        _historyIndex = _historyIndex - 1;
      }
    });
    if (_historyIndex >= 0 && _historyIndex < _history.length) {
      final cmd = _history[_history.length - 1 - _historyIndex];
      _inputController.text = cmd;
      _inputController.selection = TextSelection.collapsed(offset: cmd.length);
    } else {
      _historyIndex = -1;
      _inputController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        // ── 工具栏 ──────────────────────────────────────────────
        Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: const BoxDecoration(
            color: AppColors.bgElevated,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              const Icon(Icons.terminal, size: 13, color: AppColors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _currentDir,
                  style: AppTextStyles.caption(size: 11, color: AppColors.cyan),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_entries.isNotEmpty)
                _toolbarBtn(
                  icon: Icons.delete_sweep_outlined,
                  tooltip: '清空终端',
                  onTap: () => setState(() => _entries.clear()),
                ),
              const SizedBox(width: 6),
              // 模式切换按钮
              _ModeToggle(
                integrated: _integratedMode,
                onToggle: () {
                  setState(() => _integratedMode = !_integratedMode);
                  // 切换后把焦点给回输入框
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _inputFocus.requestFocus();
                  });
                },
              ),
            ],
          ),
        ),
        // ── 内容区 ───────────────────────────────────────────────
        Expanded(
          child: _integratedMode
              ? _buildIntegratedLayout()
              : _buildSeparateLayout(),
        ),
      ],
    );
  }

  // ── 模式A：分离式（输出区 + 底部输入栏）────────────────────────────────
  Widget _buildSeparateLayout() {
    const bgColor = Color(0xFF0D1117);
    const fadeHeight = 90.0;

    return Stack(
      children: [
        // ① 输出区 —— ShaderMask 底部渐隐（纯 CPU/Skia，无 GPU 合成开销）
        Positioned.fill(
          child: ShaderMask(
            shaderCallback: (rect) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: const [Colors.white, Colors.white, Colors.transparent],
              stops: [
                0.0,
                (1.0 - fadeHeight / rect.height).clamp(0.0, 0.8),
                1.0,
              ],
            ).createShader(rect),
            blendMode: BlendMode.dstIn,
            child: _buildOutputList(embedded: false),
          ),
        ),

        // ② 背景色填充渐变（替代 BackdropFilter，零 GPU 额外开销）
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: fadeHeight,
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    bgColor.withValues(alpha: 0.0),
                    bgColor.withValues(alpha: 0.7),
                    bgColor,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
        ),

        // ③ 悬浮输入框 —— 垂直居中于渐隐区 (90 - 46) / 2 = 22
        Positioned(
          left: 16,
          right: 16,
          bottom: (fadeHeight - 46) / 2,
          child: _buildFloatingInputBar(),
        ),
      ],
    );
  }

  Widget _buildFloatingInputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.45),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.12),
            blurRadius: 20,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Text(
            '$_currentDir\$ ',
            style: AppTextStyles.terminal(size: 13, color: AppColors.primary),
          ),
          Expanded(child: _buildInputField()),
          if (_executing)
            const Padding(
              padding: EdgeInsets.only(left: 10),
              child: SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: AppColors.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── 模式B：一体式（输入嵌入输出流末尾）──────────────────────────────────
  Widget _buildIntegratedLayout() {
    return _buildOutputList(embedded: true);
  }

  // ── 共用输出列表（embedded=true 时在末尾追加输入行）────────────────────
  Widget _buildOutputList({required bool embedded}) {
    final int extraItems = embedded ? 1 : (_executing ? 1 : 0);

    // 一体式空状态：直接显示空内容 + 输入行，不显示居中提示
    if (!embedded && _entries.isEmpty && !_executing) {
      return Container(
        color: const Color(0xFF0D1117),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.terminal, color: AppColors.primary, size: 48),
              const SizedBox(height: 16),
              Text(
                '> 输入命令开始执行',
                style: AppTextStyles.terminal(
                  size: 14,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '使用 ↑↓ 键切换历史命令，输入 clear 清空终端',
                style: AppTextStyles.caption(
                  size: 12,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      color: const Color(0xFF0D1117),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        itemCount: _entries.length + extraItems,
        itemBuilder: (context, i) {
          // 历史条目
          if (i < _entries.length) return _EntryBlock(entry: _entries[i]);

          // 分离式：执行中的 loading 条目
          if (!embedded && _executing) return _buildLoadingRow();

          // 一体式：最后一行（执行中 or 输入行）
          if (_executing) return _buildLoadingRow();
          return _buildEmbeddedInputRow();
        },
      ),
    );
  }

  Widget _buildLoadingRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '执行中...',
            style: AppTextStyles.terminal(size: 12, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  // 一体式模式下嵌入在列表末尾的输入行
  Widget _buildEmbeddedInputRow() {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '$_currentDir\$ ',
            style: AppTextStyles.terminal(size: 13, color: AppColors.primary),
          ),
          Expanded(child: _buildInputField()),
        ],
      ),
    );
  }

  // 两种模式共用的 TextField（样式/逻辑完全一致）
  Widget _buildInputField() {
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _navigateHistory(true);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            _navigateHistory(false);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: TextField(
        controller: _inputController,
        focusNode: _inputFocus,
        autofocus: true,
        enabled: !_executing,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontFamily: 'Monaco',
          fontFamilyFallback: ['Courier New', 'Courier', 'monospace'],
          fontSize: 13,
        ),
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
        onSubmitted: (v) {
          _execute(v);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _inputFocus.requestFocus();
          });
        },
      ),
    );
  }

  Widget _toolbarBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon, size: 16, color: AppColors.textSecondary),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }
}

// ─── 模式切换按钮 ──────────────────────────────────────────────────────────────

class _ModeToggle extends StatelessWidget {
  final bool integrated;
  final VoidCallback onToggle;

  const _ModeToggle({required this.integrated, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: integrated ? '切换到分离式（底部输入栏）' : '切换到一体式（模拟真实终端）',
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: integrated
                ? AppColors.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: integrated
                  ? AppColors.primary.withValues(alpha: 0.5)
                  : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                integrated ? Icons.terminal : Icons.horizontal_split_outlined,
                size: 13,
                color: integrated ? AppColors.primary : AppColors.textSecondary,
              ),
              const SizedBox(width: 5),
              Text(
                integrated ? '一体式' : '分离式',
                style: AppTextStyles.caption(
                  size: 11,
                  color: integrated
                      ? AppColors.primary
                      : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EntryBlock extends StatelessWidget {
  final _TerminalEntry entry;

  const _EntryBlock({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 命令行
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${entry.dir}\$ ',
                style: AppTextStyles.terminal(
                  size: 13,
                  color: AppColors.primary,
                ),
              ),
              Expanded(
                child: SelectableText(
                  entry.command,
                  style: AppTextStyles.terminal(
                    size: 13,
                    color: AppColors.cyan,
                  ),
                ),
              ),
              Text(
                '${entry.timestamp.hour.toString().padLeft(2, '0')}'
                ':${entry.timestamp.minute.toString().padLeft(2, '0')}'
                ':${entry.timestamp.second.toString().padLeft(2, '0')}',
                style: AppTextStyles.caption(
                  size: 10,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          // 输出
          if (entry.output != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: SelectableText(
                entry.output!,
                style: const TextStyle(
                  color: Color(0xFFB8C0CC),
                  fontFamily: 'Monaco',
                  fontFamilyFallback: ['Courier New', 'Courier', 'monospace'],
                  fontSize: 12,
                  height: 1.6,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          const SizedBox(height: 4),
          const Divider(height: 1, color: Color(0xFF1C2128)),
        ],
      ),
    );
  }
}

// ─── 文件管理 Tab ──────────────────────────────────────────────────────────────

class _FileManagerTab extends StatefulWidget {
  final WebshellService service;

  const _FileManagerTab({required this.service});

  @override
  State<_FileManagerTab> createState() => _FileManagerTabState();
}

class _FileManagerTabState extends State<_FileManagerTab>
    with AutomaticKeepAliveClientMixin {
  String _currentPath = '/';
  List<FileEntry> _files = [];
  bool _loading = true;
  String? _errorMsg;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initPath();
  }

  Future<void> _initPath() async {
    final dir = await widget.service.getCurrentDir();
    if (mounted) _loadDirectory(dir);
  }

  Future<void> _loadDirectory(String path) async {
    setState(() {
      _loading = true;
      _errorMsg = null;
    });
    final files = await widget.service.listDirectory(path);
    if (!mounted) return;
    setState(() {
      _currentPath = path;
      _files = files;
      _loading = false;
      if (files.isEmpty) _errorMsg = '目录为空或无权访问';
      widget.service.currentDir = path;
    });
  }

  String _parent(String path) {
    final norm = path.replaceAll('\\', '/');
    final parts = norm.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return '/';
    parts.removeLast();
    if (parts.isEmpty) return '/';
    return '/${parts.join('/')}';
  }

  String _join(String dir, String name) {
    if (name == '..') return _parent(dir);
    final norm = dir.replaceAll('\\', '/').trimRight();
    return norm.endsWith('/') ? '$norm$name' : '$norm/$name';
  }

  Future<void> _viewFile(FileEntry entry) async {
    final path = _join(_currentPath, entry.name);
    showDialog(
      context: context,
      builder: (_) => _FileViewDialog(
        service: widget.service,
        path: path,
        name: entry.name,
      ),
    );
  }

  Future<void> _showEditDialog(FileEntry entry) async {
    final path = _join(_currentPath, entry.name);
    final content = await widget.service.readFile(path);
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => _FileEditDialog(
        service: widget.service,
        path: path,
        name: entry.name,
        initialContent: content,
        onSaved: () => _loadDirectory(_currentPath),
      ),
    );
  }

  Future<void> _deleteFile(FileEntry entry) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: const Text('确认删除', style: TextStyle(color: AppColors.red)),
        content: Text(
          '确定删除「${entry.name}」吗？此操作不可恢复。',
          style: const TextStyle(color: AppColors.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              '取消',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            child: const Text('删除', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final ok = await widget.service.deleteFile(_join(_currentPath, entry.name));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? '已删除 ${entry.name}' : '删除失败'),
        backgroundColor: ok ? AppColors.bgCard : AppColors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (ok) _loadDirectory(_currentPath);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        // 路径栏
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: AppColors.bgElevated,
          child: Row(
            children: [
              IconButton(
                onPressed: _loading
                    ? null
                    : () => _loadDirectory(_parent(_currentPath)),
                icon: const Icon(Icons.arrow_upward, size: 16),
                color: AppColors.textSecondary,
                tooltip: '上级目录',
              ),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.bgDark,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    _currentPath,
                    style: AppTextStyles.terminal(
                      size: 12,
                      color: AppColors.cyan,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              IconButton(
                onPressed: _loading ? null : () => _loadDirectory(_currentPath),
                icon: const Icon(Icons.refresh, size: 16),
                color: AppColors.textSecondary,
                tooltip: '刷新',
              ),
            ],
          ),
        ),
        // 列标题
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          decoration: const BoxDecoration(
            color: AppColors.bgCard,
            border: Border(
              bottom: BorderSide(color: AppColors.border),
              top: BorderSide(color: AppColors.border),
            ),
          ),
          child: Row(
            children: [
              const SizedBox(width: 28),
              _colHeader('名称', flex: 5),
              _colHeader('大小', width: 80),
              _colHeader('权限', width: 60),
              _colHeader('修改时间', width: 130),
              const SizedBox(width: 90),
            ],
          ),
        ),
        // 文件列表
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                )
              : _files.isEmpty
              ? Center(
                  child: Text(
                    _errorMsg ?? '目录为空',
                    style: AppTextStyles.body(color: AppColors.textSecondary),
                  ),
                )
              : ListView.builder(
                  itemCount: _files.length,
                  itemBuilder: (context, i) {
                    final f = _files[i];
                    return _FileRow(
                      entry: f,
                      onTap: () => f.isDirectory
                          ? _loadDirectory(_join(_currentPath, f.name))
                          : null,
                      onView: f.isDirectory || f.name == '..'
                          ? null
                          : () => _viewFile(f),
                      onEdit: f.isDirectory || f.name == '..'
                          ? null
                          : () => _showEditDialog(f),
                      onDelete: f.name == '..' ? null : () => _deleteFile(f),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _colHeader(String label, {int flex = 0, double? width}) {
    final text = Text(
      label,
      style: AppTextStyles.caption(size: 11, color: AppColors.textMuted),
    );
    if (width != null) return SizedBox(width: width, child: text);
    return Expanded(flex: flex, child: text);
  }
}

class _FileRow extends StatelessWidget {
  final FileEntry entry;
  final VoidCallback? onTap;
  final VoidCallback? onView;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _FileRow({
    required this.entry,
    this.onTap,
    this.onView,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isUp = entry.name == '..';
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Color(0xFF1C2128), width: 0.8),
          ),
        ),
        child: Row(
          children: [
            Icon(
              isUp
                  ? Icons.subdirectory_arrow_left
                  : entry.isDirectory
                  ? Icons.folder_rounded
                  : _fileIcon(entry.name),
              size: 18,
              color: isUp
                  ? AppColors.textMuted
                  : entry.isDirectory
                  ? AppColors.amber
                  : _fileIconColor(entry.name),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 5,
              child: Text(
                entry.name,
                style: AppTextStyles.body(
                  size: 13,
                  color: isUp
                      ? AppColors.textMuted
                      : entry.isDirectory
                      ? AppColors.amber
                      : AppColors.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(
              width: 80,
              child: Text(
                entry.formattedSize,
                style: AppTextStyles.caption(
                  size: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            SizedBox(
              width: 60,
              child: Text(
                entry.permissions,
                style: AppTextStyles.caption(
                  size: 12,
                  color: AppColors.primary,
                ).copyWith(letterSpacing: 0.5),
              ),
            ),
            SizedBox(
              width: 130,
              child: Text(
                entry.modified,
                style: AppTextStyles.caption(
                  size: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            SizedBox(
              width: 90,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (onView != null)
                    _iconBtn(
                      Icons.visibility_outlined,
                      AppColors.cyan,
                      '查看',
                      onView!,
                    ),
                  if (onEdit != null)
                    _iconBtn(
                      Icons.edit_outlined,
                      AppColors.primary,
                      '编辑',
                      onEdit!,
                    ),
                  if (onDelete != null)
                    _iconBtn(
                      Icons.delete_outline,
                      AppColors.red,
                      '删除',
                      onDelete!,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, Color color, String tip, VoidCallback fn) =>
      IconButton(
        onPressed: fn,
        icon: Icon(icon, size: 15),
        color: color,
        tooltip: tip,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      );

  IconData _fileIcon(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'php':
      case 'py':
      case 'js':
      case 'ts':
      case 'dart':
        return Icons.code;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
        return Icons.image_outlined;
      case 'zip':
      case 'gz':
      case 'tar':
      case 'rar':
        return Icons.archive_outlined;
      case 'txt':
      case 'log':
      case 'md':
        return Icons.article_outlined;
      case 'sh':
      case 'bash':
        return Icons.terminal;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  Color _fileIconColor(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'php':
        return AppColors.cyan;
      case 'py':
        return const Color(0xFF3B8EEA);
      case 'js':
      case 'ts':
        return AppColors.amber;
      case 'sh':
      case 'bash':
        return AppColors.primary;
      default:
        return AppColors.textSecondary;
    }
  }
}

// ─── 文件查看对话框 ─────────────────────────────────────────────────────────────

class _FileViewDialog extends StatefulWidget {
  final WebshellService service;
  final String path;
  final String name;

  const _FileViewDialog({
    required this.service,
    required this.path,
    required this.name,
  });

  @override
  State<_FileViewDialog> createState() => _FileViewDialogState();
}

class _FileViewDialogState extends State<_FileViewDialog> {
  String? _content;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final content = await widget.service.readFile(widget.path);
    if (mounted) {
      setState(() {
        _content = content;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.bgCard,
      child: SizedBox(
        width: 700,
        height: 520,
        child: Column(
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.article_outlined,
                    color: AppColors.primary,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.name,
                      style: AppTextStyles.body(
                        size: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (_content != null)
                    IconButton(
                      onPressed: () =>
                          Clipboard.setData(ClipboardData(text: _content!)),
                      icon: const Icon(
                        Icons.copy_outlined,
                        size: 16,
                        color: AppColors.textSecondary,
                      ),
                      tooltip: '复制内容',
                    ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: SelectableText(
                        _content ?? '',
                        style: const TextStyle(
                          color: Color(0xFFB8C0CC),
                          fontFamily: 'Monaco',
                          fontFamilyFallback: ['Courier New', 'Courier', 'monospace'],
                          fontSize: 12,
                          height: 1.7,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 文件编辑对话框 ────────────────────────────────────────────────────────────

class _FileEditDialog extends StatefulWidget {
  final WebshellService service;
  final String path;
  final String name;
  final String initialContent;
  final VoidCallback onSaved;

  const _FileEditDialog({
    required this.service,
    required this.path,
    required this.name,
    required this.initialContent,
    required this.onSaved,
  });

  @override
  State<_FileEditDialog> createState() => _FileEditDialogState();
}

class _FileEditDialogState extends State<_FileEditDialog> {
  late final TextEditingController _controller;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialContent);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await widget.service.writeFile(widget.path, _controller.text);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      Navigator.pop(context);
      widget.onSaved();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('保存成功'),
          backgroundColor: AppColors.bgCard,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('保存失败'),
          backgroundColor: AppColors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.bgCard,
      child: SizedBox(
        width: 700,
        height: 560,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.edit_outlined,
                    color: AppColors.primary,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.name,
                      style: AppTextStyles.body(
                        size: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      '取消',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.bgDark,
                            ),
                          )
                        : const Icon(Icons.save_outlined, size: 16),
                    label: const Text('保存'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.bgDark,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                style: const TextStyle(
                  color: Color(0xFFB8C0CC),
                  fontFamily: 'Monaco',
                  fontFamilyFallback: ['Courier New', 'Courier', 'monospace'],
                  fontSize: 12,
                  height: 1.7,
                ),
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.all(16),
                  border: InputBorder.none,
                  fillColor: Color(0xFF0D1117),
                  filled: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 系统信息 Tab ─────────────────────────────────────────────────────────────

class _SystemInfoTab extends StatefulWidget {
  final WebshellService service;

  const _SystemInfoTab({required this.service});

  @override
  State<_SystemInfoTab> createState() => _SystemInfoTabState();
}

class _SystemInfoTabState extends State<_SystemInfoTab>
    with AutomaticKeepAliveClientMixin {
  Map<String, String> _info = {};
  bool _loading = true;
  bool _failed = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    final info = await widget.service.getSystemInfo();
    if (mounted) {
      setState(() {
        _info = info;
        _loading = false;
        _failed = info.isEmpty;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        // 工具栏
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          color: AppColors.bgElevated,
          child: Row(
            children: [
              const Icon(
                Icons.dns_outlined,
                color: AppColors.primary,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                '服务器基本信息',
                style: AppTextStyles.heading(
                  size: 14,
                  color: AppColors.primary,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh, size: 15),
                label: const Text('刷新'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                )
              : _failed
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: AppColors.red,
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '无法获取系统信息',
                        style: AppTextStyles.body(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '请检查 Webshell 是否可正常执行 PHP 代码',
                        style: AppTextStyles.caption(
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('重试'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.bgDark,
                        ),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      // 主要信息卡
                      _InfoGrid(info: _info),
                      const SizedBox(height: 20),
                      // 禁用函数
                      if (_info['禁用函数'] != null && _info['禁用函数'] != '无')
                        _DisabledFunctionsCard(functions: _info['禁用函数']!),
                      // 扩展列表
                      if (_info['已加载扩展'] != null)
                        _ExtensionsCard(extensions: _info['已加载扩展']!),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _InfoGrid extends StatelessWidget {
  final Map<String, String> info;

  const _InfoGrid({required this.info});

  static const _mainKeys = [
    'OS',
    'PHP版本',
    '运行用户',
    '服务器IP',
    '服务器软件',
    '文档根目录',
    '当前目录',
    '内存限制',
    '最大执行时间',
    'Safe Mode',
  ];

  @override
  Widget build(BuildContext context) {
    final items = _mainKeys
        .where((k) => info.containsKey(k))
        .map((k) => MapEntry(k, info[k]!))
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: items.map((e) {
          final isLast = e == items.last;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              border: isLast
                  ? null
                  : const Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 120,
                  child: Text(
                    e.key,
                    style: AppTextStyles.caption(
                      size: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                Expanded(
                  child: SelectableText(
                    e.value,
                    style: AppTextStyles.body(
                      size: 13,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _DisabledFunctionsCard extends StatelessWidget {
  final String functions;

  const _DisabledFunctionsCard({required this.functions});

  @override
  Widget build(BuildContext context) {
    final funcs = functions
        .split(',')
        .map((f) => f.trim())
        .where((f) => f.isNotEmpty)
        .toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.block, color: AppColors.red, size: 16),
              const SizedBox(width: 8),
              Text(
                '禁用函数 (${funcs.length})',
                style: AppTextStyles.body(size: 13, color: AppColors.red),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: funcs
                .map(
                  (f) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: AppColors.red.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      f,
                      style: AppTextStyles.caption(
                        size: 11,
                        color: AppColors.red,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _ExtensionsCard extends StatelessWidget {
  final String extensions;

  const _ExtensionsCard({required this.extensions});

  @override
  Widget build(BuildContext context) {
    final exts =
        extensions
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList()
          ..sort();
    return Container(
      padding: const EdgeInsets.all(16),
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
              const Icon(
                Icons.extension_outlined,
                color: AppColors.primary,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                '已加载扩展 (${exts.length})',
                style: AppTextStyles.body(size: 13, color: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: exts
                .map(
                  (e) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      e,
                      style: AppTextStyles.caption(
                        size: 11,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}
