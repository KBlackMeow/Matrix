import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../services/reverse_shell_service.dart';
import '../theme/app_theme.dart';

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
  late final FocusNode _focusNode;
  StreamSubscription<List<int>>? _rawSub;
  bool _closedManually = false;
  bool _connectionClosed = false;

  // 防抖定时器：窗口拖拽时不向远端频繁发 stty
  Timer? _resizeDebounce;

  @override
  void initState() {
    super.initState();

    // 本地输入 → 发送到反弹 Shell（连接断开时静默忽略，避免未处理异常）
    _terminal = Terminal(
      maxLines: 10000,
      onOutput: (data) {
        if (!widget.session.isAlive) return;
        widget.session.send(data).catchError((_) {});
      },
    );

    _terminalController = TerminalController();
    _focusNode = FocusNode();

    // 重新进入完整终端页面时，先回放该会话已有历史输出
    for (final chunk in widget.session.historyRaw) {
      if (chunk.isNotEmpty) {
        _writeToTerminal(chunk);
      }
    }

    // 远端输出字节流 → 原样写入终端；连接断开时仅标记状态，不自动关闭（由用户手动关闭）
    _rawSub = widget.session.rawStream.listen(
      (data) {
        _writeToTerminal(data);
      },
      onDone: () {
        if (mounted && !_closedManually) {
          setState(() => _connectionClosed = true);
        }
      },
      onError: (_, _) {
        if (mounted && !_closedManually) {
          setState(() => _connectionClosed = true);
        }
      },
    );
  }

  @override
  void dispose() {
    _rawSub?.cancel();
    _resizeDebounce?.cancel();
    _focusNode.dispose();
    _terminalController.dispose();
    super.dispose();
  }

  /// TerminalView 渲染后读取其实际 cols/rows，同步通知远端 shell。
  /// 仅在创建时和窗口尺寸变化时发送，避免每次进入页面都重复发送。
  void _resizeIfNeeded(Size size) {
    if (size.isEmpty) return;
    final cols = _terminal.viewWidth;
    final rows = _terminal.viewHeight;
    // 尺寸未变则跳过（含重入页面时 session 已记录上次发送值的情况）
    if (cols == widget.session.lastSttyCols && rows == widget.session.lastSttyRows) return;
    _resizeDebounce?.cancel();
    _resizeDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted && widget.session.isAlive) {
        widget.session.lastSttyCols = cols;
        widget.session.lastSttyRows = rows;
        widget.session.send('stty cols $cols rows $rows\n').catchError((_) {});
      }
    });
  }

  /// 写入数据到终端控件，并处理“阶梯效应” (Staircase Effect)
  ///
  /// 在没有 PTY 的裸反弹 Shell 中，远端只发送 \n 而不包含 \r。
  /// 此方法确保 \n 都会被解释为 \r\n，从而让光标回到行首。
  void _writeToTerminal(List<int> data) {
    // 使用 utf8 解码支持中文字符，allowMalformed 避免非法序列崩溃
    final text = utf8.decode(data, allowMalformed: true);

    // 算法：将所有 \n 替换为 \r\n，但要避免将原本就是 \r\n 的变成 \r\r\n
    final fixedText = text.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n');

    _terminal.write(fixedText);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: SafeArea(
        child: Column(
          children: [
            // 顶部栏，风格与 Webshell 交互页一致
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
                    tooltip: '返回',
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.computer,
                      color: AppColors.primary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.session.label != null && widget.session.label!.isNotEmpty
                          ? '完整终端 · ${widget.session.label}'
                          : '完整终端 · ${widget.session.id}',
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
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.red.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '连接已断开',
                        style: AppTextStyles.caption(size: 11, color: AppColors.red),
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
                      _connectionClosed ? Icons.close : Icons.power_settings_new,
                      size: 16,
                      color: AppColors.red,
                    ),
                    label: Text(
                      _connectionClosed ? '关闭' : '主动断开',
                      style: AppTextStyles.caption(
                          size: 11, color: AppColors.red),
                    ),
                  ),
                ],
              ),
            ),
            // 终端内容区域（填满剩余空间，无圆角，直接铺满）
            Expanded(
              child: Container(
                // 使用 decoration + clipBehavior，避免 Flutter 对
                // “color + clipBehavior” 的断言报错
                decoration: const BoxDecoration(
                  color: Color(0xFF0D1117),
                ),
                clipBehavior: Clip.hardEdge,
                child: _buildTerminalWithContextMenu(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 终端 + 右键菜单；外层 LayoutBuilder 负责动态检测并同步终端尺寸
  Widget _buildTerminalWithContextMenu() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 在下一帧更新，避免在 build 阶段直接修改状态
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _resizeIfNeeded(constraints.biggest);
        });
        return Stack(
          children: [
            TerminalView(
              _terminal,
              backgroundOpacity: 0,
              cursorType: TerminalCursorType.block,
              controller: _terminalController,
              focusNode: _focusNode,
              autofocus: true,
              hardwareKeyboardOnly: true,
              onSecondaryTapUp: (details, cell) async {
                final selection = _terminalController.selection;
                final selectedText = selection != null
                    ? _terminal.buffer.getText(selection)
                    : null;

                final ctx = context;
                if (!ctx.mounted) return;
                final choice = await showMenu<String>(
                  context: ctx,
                  position: RelativeRect.fromLTRB(
                    details.globalPosition.dx,
                    details.globalPosition.dy,
                    details.globalPosition.dx,
                    details.globalPosition.dy,
                  ),
                  items: [
                    if (selectedText != null)
                      const PopupMenuItem(
                        value: 'copy',
                        child: Text('复制'),
                      ),
                    const PopupMenuItem(
                      value: 'paste',
                      child: Text('粘贴'),
                    ),
                  ],
                );

                if (choice == 'copy' && selectedText != null) {
                  await Clipboard.setData(ClipboardData(text: selectedText));
                } else if (choice == 'paste') {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  final text = data?.text;
                  if (text != null && text.isNotEmpty) {
                    var t = text.replaceAll('\r\n', '\n').replaceAll('\r', '');
                    while (t.startsWith('\n')) {
                      t = t.substring(1);
                    }
                    if (t.isNotEmpty && widget.session.isAlive) {
                      // Bracketed Paste Mode：告知远端 bash 这是粘贴而非逐键输入，
                      // 避免大量内容被 readline 逐字符处理导致缓冲区溢出、从头覆盖
                      widget.session.send('\x1b[200~$t\x1b[201~').catchError((_) {});
                    }
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }
}

