import 'dart:async';

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
  StreamSubscription<List<int>>? _rawSub;
  bool _lastCharWasCR = false;

  @override
  void initState() {
    super.initState();

    // 本地输入 → 发送到反弹 Shell
    _terminal = Terminal(
      maxLines: 10000,
      onOutput: (data) {
        widget.session.send(data);
      },
    );

    _terminalController = TerminalController();

    // 远端输出字节流 → 写入终端
    _rawSub = widget.session.rawStream.listen((data) {
      // 智能规范换行：
      // - 保留远端原始的 "\r\n"（CRLF）
      // - 单独的 "\r" 原样保留（用于进度条覆盖当前行）
      // - 单独的 "\n" 规范为 "\r\n"，修复 Bash 只下移不回行首的问题
      final text = String.fromCharCodes(data);
      final buf = StringBuffer();
      for (var i = 0; i < text.length; i++) {
        final ch = text[i];
        if (ch == '\r') {
          buf.write('\r');
          _lastCharWasCR = true;
        } else if (ch == '\n') {
          if (_lastCharWasCR) {
            // 这是 CRLF 中的 LF，直接写 LF 即可（前一个 CR 已写入）
            buf.write('\n');
          } else {
            // 单独的 LF，转换为 CRLF
            buf.write('\r\n');
          }
          _lastCharWasCR = false;
        } else {
          buf.write(ch);
          _lastCharWasCR = false;
        }
      }
      _terminal.write(buf.toString());
    });
  }

  @override
  void dispose() {
    _rawSub?.cancel();
    _terminalController.dispose();
    super.dispose();
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
                      '完整终端 · ${widget.session.id}',
                      style: AppTextStyles.heading(
                        size: 16,
                        color: AppColors.primary,
                      ),
                      overflow: TextOverflow.ellipsis,
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

  /// 终端 + 右键菜单（复制选中内容）
  Widget _buildTerminalWithContextMenu() {
    return Stack(
      children: [
        TerminalView(
          _terminal,
          backgroundOpacity: 0,
          cursorType: TerminalCursorType.block,
          controller: _terminalController,
          // 保留默认快捷键：Ctrl/Cmd + C 复制、V 粘贴、A 全选，
          // 只额外增加右键菜单
          hardwareKeyboardOnly: true,
          onSecondaryTapUp: (details, cell) async {
            final selection = _terminalController.selection;
            final selectedText = selection != null
                ? _terminal.buffer.getText(selection)
                : null;

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
                _terminal.paste(text);
              }
            }
          },
        ),
      ],
    );
  }
}

