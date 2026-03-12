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
    _focusNode = FocusNode();

    // 重新进入完整终端页面时，先回放该会话已有历史输出
    for (final chunk in widget.session.historyRaw) {
      if (chunk.isNotEmpty) {
        _writeToTerminal(chunk);
      }
    }

    // 远端输出字节流 → 原样写入终端；会话结束时自动关闭页面
    _rawSub = widget.session.rawStream.listen(
      (data) {
        _writeToTerminal(data);
      },
      onDone: () {
        // 远端主动 exit/断开时自动关闭完整终端页面
        if (mounted) {
          Navigator.of(context).pop();
        }
      },
      onError: (_, _) {
        if (mounted) {
          Navigator.of(context).pop();
        }
      },
    );
  }

  @override
  void dispose() {
    _rawSub?.cancel();
    _focusNode.dispose();
    _terminalController.dispose();
    super.dispose();
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
          focusNode: _focusNode,
          autofocus: true,
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
                // 仅做最小化规范：
                // - 将 CRLF 归一为 LF
                // - 去掉残留的单独 CR（避免来自其他终端的回车控制符打乱行内顺序）
                // - 去掉首部多余换行，避免光标直接跳到下一行
                var t = text.replaceAll('\r\n', '\n').replaceAll('\r', '');
                while (t.startsWith('\n')) {
                  t = t.substring(1);
                }
                if (t.isNotEmpty) {
                  _terminal.textInput(t);
                }
              }
            }
          },
        ),
      ],
    );
  }
}

