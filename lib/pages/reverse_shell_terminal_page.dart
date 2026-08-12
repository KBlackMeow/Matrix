import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../io/terminal_output_pipe.dart';
import '../services/reverse_shell_service.dart';
import '../theme/app_theme.dart';

/// 与 Matrix 深色主题一致的 xterm 调色板（远端 `ls --color`、`bat` 等 ANSI 输出）。
const _matrixXtermTheme = TerminalTheme(
  cursor: Color(0xFF00E676),
  selection: Color(0x6630363D),
  foreground: Color(0xFFB8C0CC),
  background: Color(0xFF0D1117),
  black: Color(0xFF131920),
  red: Color(0xFFFF5370),
  green: Color(0xFF00E676),
  yellow: Color(0xFFFFD740),
  blue: Color(0xFF61AEEE),
  magenta: Color(0xFFD670D6),
  cyan: Color(0xFF00E5FF),
  white: Color(0xFFD0E8D0),
  brightBlack: Color(0xFF5A705A),
  brightRed: Color(0xFFFF7A8F),
  brightGreen: Color(0xFF69F0AE),
  brightYellow: Color(0xFFFFE082),
  brightBlue: Color(0xFF82B1FF),
  brightMagenta: Color(0xFFE6A3FF),
  brightCyan: Color(0xFF84FFFF),
  brightWhite: Color(0xFFF0FFF4),
  searchHitBackground: Color(0x66FFD740),
  searchHitBackgroundCurrent: Color(0xCC00E676),
  searchHitForeground: Color(0xFF0D1117),
);

TerminalTargetPlatform get _currentPlatform {
  if (Platform.isMacOS) return TerminalTargetPlatform.macos;
  if (Platform.isLinux) return TerminalTargetPlatform.linux;
  if (Platform.isWindows) return TerminalTargetPlatform.windows;
  return TerminalTargetPlatform.unknown;
}

/// 等宽 CJK 回退链——优先选用"真正等宽"的 CJK 字体。
///
/// 问题：xterm 计算 CJK 字符为 2 cell = `2 × JetBrainsMono.charAdvance` 像素，
/// 但 PingFang SC / Microsoft YaHei 等比例 CJK 字体的 glyph 宽度不恰好等于该值，
/// 导致 CJK 字符溢出 cell 或被截断。
///
/// 解决：首选用 `Noto Sans Mono CJK SC`——这是 Google 专门为终端设计的等宽 CJK
/// 字体，Han 字宽严格等于 `2 × Latin`。仅在它不可用时回退到系统字体。
List<String> get _cjkFallback {
  // Noto Sans Mono CJK SC 在所有平台上都是首选，它保证 CJK = 2 × Latin 宽度
  const notoCjk = 'Noto Sans Mono CJK SC';
  if (Platform.isMacOS) {
    return const [
      notoCjk,
      'Menlo',               // Apple 等宽，有部分 CJK，度量与 JBM 接近
      'PingFang SC',         // 系统中文（比例字体，最后手段）
      'sans-serif',
    ];
  }
  if (Platform.isWindows) {
    return const [
      notoCjk,
      'Cascadia Mono',       // 微软等宽终端字体，CJK 度量调校良好
      'Microsoft YaHei UI',  // 系统中文（比例字体）
      'sans-serif',
    ];
  }
  return const [
    notoCjk,
    'DejaVu Sans Mono',
    'sans-serif',
  ];
}

/// 基于反弹 Shell 的完整终端页面（使用 xterm 终端模拟器）
class ReverseShellTerminalPage extends StatefulWidget {
  final ReverseShellSession session;

  const ReverseShellTerminalPage({super.key, required this.session});

  @override
  State<ReverseShellTerminalPage> createState() =>
      _ReverseShellTerminalPageState();
}

class _ReverseShellTerminalPageState extends State<ReverseShellTerminalPage> {
  late final Terminal _terminal;
  late final TerminalController _terminalController;
  late final TerminalOutputPipe _pipe;
  late final FocusNode _focusNode;
  bool _closedManually = false;
  bool _connectionClosed = false;

  // Resize 状态（含消抖定时器）
  Timer? _resizeDebounce;
  int _lastCols = -1;
  int _lastRows = -1;

  @override
  void initState() {
    super.initState();

    // ── 1. 创建 Terminal（必须先于 pipe，因为 pipe 持有 terminal 引用） ──
    _terminal = Terminal(
      maxLines: 10000,
      onOutput: (data) {
        if (!widget.session.isAlive) return;
        widget.session.send(data).catchError((_) {});
      },
      onResize: _onTerminalResize,
      onPrivateOSC: _onPrivateOSC,
      platform: _currentPlatform,
    );

    // ── 2. 创建输出管线 ──
    _pipe = TerminalOutputPipe(terminal: _terminal);

    // 背压：pipe 暂停/恢复 → socket 订阅暂停/恢复
    _pipe.onPause = () => widget.session.subscription?.pause();
    _pipe.onResume = () => widget.session.subscription?.resume();

    // ── 3. 订阅远端字节流 → pipe.add() ──
    widget.session.rawStream.listen(
      (data) => _pipe.add(data),
      onDone: _onConnectionClosed,
      onError: (_, _) => _onConnectionClosed(),
    );

    _terminalController = TerminalController(
      pointerInputs: const PointerInputs({
        PointerInput.tap,
        PointerInput.scroll,
        PointerInput.drag,
        PointerInput.move,
      }),
    );
    _focusNode = FocusNode();

    // ── 4. 历史回放 ──
    // resize 由 onResize 回调负责，不需要额外的延迟重试
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final chunk in widget.session.historyRaw) {
        _pipe.add(chunk);
      }
    });
  }

  @override
  void dispose() {
    _pipe.dispose();
    _resizeDebounce?.cancel();
    _focusNode.dispose();
    _terminalController.dispose();
    super.dispose();
  }

  // ── Resize：通过 terminal.onResize 回调触发（非 LayoutBuilder 轮询） ──

  void _onTerminalResize(int cols, int rows, int pw, int ph) {
    if (cols == _lastCols && rows == _lastRows) return;
    _lastCols = cols;
    _lastRows = rows;

    _resizeDebounce?.cancel();
    _resizeDebounce = Timer(const Duration(milliseconds: 150), () {
      _sendSttyResize();
    });
  }

  /// 通知远端 shell 当前终端尺寸。
  ///
  /// 双命令策略兼容有无 PTY 两种场景：
  /// - `stty cols/rows`——有 PTY（script 模式）时生效，内核发 SIGWINCH，
  ///   程序通过 `isatty()` 和 `TIOCGWINSZ` 获知正确尺寸
  /// - `export COLUMNS/LINES`——无 PTY（纯 bash 模式）时兜底，bash
  ///   用它们做 readline 换行；stty 的 ioctl 错误被 2>/dev/null 吞掉
  ///
  /// 仅当不在 alt buffer（vim/less）中时才发送，避免污染正在运行的程序。
  void _sendSttyResize() {
    if (!mounted || !widget.session.isAlive) return;
    if (_terminal.isUsingAltBuffer) return;
    final cols = _terminal.viewWidth;
    final rows = _terminal.viewHeight;
    if (cols <= 0 || rows <= 0) return;
    // 与上次发送的尺寸相同则跳过（包括重入终端页面的场景）
    if (cols == widget.session.lastSttyCols &&
        rows == widget.session.lastSttyRows) {
      return;
    }
    widget.session.lastSttyCols = cols;
    widget.session.lastSttyRows = rows;
    widget.session
        .send(
          'export COLUMNS=$cols LINES=$rows; '
          'stty cols $cols rows $rows 2>/dev/null\n',
        )
        .catchError((_) {});
  }

  // ── OSC 52 剪贴板 ──

  void _onPrivateOSC(String code, List<String> args) {
    if (code != '52' || args.isEmpty) return;
    final payload = args.join(';');
    final qIdx = payload.indexOf('?');
    if (qIdx < 0) return;
    try {
      final b64 = payload.substring(qIdx + 1);
      final bytes = base64Decode(b64);
      final text = utf8.decode(bytes);
      Clipboard.setData(ClipboardData(text: text));
    } catch (_) {
      // OSC 52 数据格式错误 — 静默忽略
    }
  }

  // ── 连接断开 ──

  void _onConnectionClosed() {
    if (!mounted || _closedManually) return;
    _terminal.write('\r\n\x1b[31m[Connection closed]\x1b[0m\r\n');
    setState(() => _connectionClosed = true);
  }

  // ── 平台感知终端样式 ──────────────────────────────────────────────────────────

  TerminalStyle _buildTerminalStyle() {
    // Windows 系统等宽字体（Consolas / Cascadia）在 w400 下经 Skia 灰阶 AA
    // 渲染偏细，且没有真 bold cut——Flutter 合成 bold 会加粗变形。对齐 ssterm：
    // Regular 用 w500（Medium），Bold 与 Regular 同重，避免合成 bold。
    if (Platform.isWindows) {
      return TerminalStyle(
        fontFamily: 'JetBrainsMono',
        fontSize: 14,
        height: 1.25,
        letterSpacing: 0,
        fontWeight: FontWeight.w500,
        boldFontWeight: FontWeight.w500,
        fontFamilyFallback: _cjkFallback,
      );
    }
    return TerminalStyle(
      fontFamily: 'JetBrainsMono',
      fontSize: 13,
      height: 1.25,
      letterSpacing: 0,
      fontFamilyFallback: _cjkFallback,
    );
  }

  // ── UI ────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: SafeArea(
        child: Column(
          children: [
            // 顶部栏
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.bgElevated,
                border: Border(
                  bottom: BorderSide(
                    color: AppColors.primary.withValues(alpha: 0.35),
                  ),
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
                    tooltip: 'Back',
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.computer,
                    color: AppColors.primary,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.session.label != null &&
                              widget.session.label!.isNotEmpty
                          ? 'Full terminal · ${widget.session.label!}'
                          : 'Full terminal · ${widget.session.id}',
                      style: AppTextStyles.heading(
                        size: 16,
                        color: AppColors.primary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_connectionClosed)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.red.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Connection closed',
                        style: AppTextStyles.caption(
                          size: 11,
                          color: AppColors.red,
                        ),
                      ),
                    ),
                  TextButton.icon(
                    onPressed: () async {
                      _closedManually = true;
                      final nav = Navigator.of(context);
                      await widget.session.close();
                      if (!mounted) return;
                      nav.pop();
                    },
                    icon: Icon(
                      _connectionClosed
                          ? Icons.close
                          : Icons.power_settings_new,
                      size: 16,
                      color: AppColors.red,
                    ),
                    label: Text(
                      _connectionClosed ? 'Close' : 'Disconnect',
                      style: AppTextStyles.caption(
                        size: 11,
                        color: AppColors.red,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 终端内容区域
            Expanded(
              child: Container(
                decoration: const BoxDecoration(color: Color(0xFF0D1117)),
                clipBehavior: Clip.hardEdge,
                child: _buildTerminal(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTerminal() {
    return Stack(
      children: [
        TerminalView(
          _terminal,
          theme: _matrixXtermTheme,
          textStyle: _buildTerminalStyle(),
          backgroundOpacity: 0,
          cursorType: TerminalCursorType.block,
          controller: _terminalController,
          focusNode: _focusNode,
          autofocus: true,
          hardwareKeyboardOnly: true,
          onSecondaryTapUp: _onSecondaryTap,
        ),
      ],
    );
  }

  Future<void> _onSecondaryTap(TapUpDetails details, CellOffset cell) async {
    final selection = _terminalController.selection;
    final selectedText =
        selection != null ? _terminal.buffer.getText(selection) : null;

    if (!mounted) return;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        details.globalPosition.dx,
        details.globalPosition.dy,
        details.globalPosition.dx,
        details.globalPosition.dy,
      ),
      items: [
        if (selectedText != null)
          PopupMenuItem(value: 'copy', child: Text('Copy')),
        PopupMenuItem(value: 'paste', child: Text('Paste')),
      ],
    );

    if (choice == 'copy' && selectedText != null) {
      await Clipboard.setData(ClipboardData(text: selectedText));
    } else if (choice == 'paste') {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text;
      if (text != null && text.isNotEmpty && widget.session.isAlive) {
        // 使用 terminal.paste() 自动处理 bracketed paste 包裹
        _terminal.paste(text);
      }
    }
  }
}
