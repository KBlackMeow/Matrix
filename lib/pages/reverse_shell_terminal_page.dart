import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
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

  // 当前终端列数/行数，初始值与 xterm 默认值一致
  int _termCols = 80;
  int _termRows = 24;
  // 防抖定时器：窗口拖拽时不向远端频繁发 stty
  Timer? _resizeDebounce;
  // 文件传输状态
  bool _uploading = false;
  bool _downloading = false;

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

    // 远端输出字节流 → 原样写入终端；会话结束时自动关闭页面（若未手动关闭）
    _rawSub = widget.session.rawStream.listen(
      (data) {
        _writeToTerminal(data);
      },
      onDone: () {
        // 远端主动 exit/断开时自动关闭完整终端页面（手动关闭时不再二次 pop）
        if (mounted && !_closedManually) {
          Navigator.of(context).pop();
        }
      },
      onError: (_, _) {
        if (mounted && !_closedManually) {
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

  /// TerminalView 渲染后读取其实际 cols/rows，同步通知远端 shell。
  /// 由 LayoutBuilder 的 postFrameCallback 调用：此时 TerminalView
  /// 已按真实字体尺寸完成 terminal.resize()，viewWidth/viewHeight 是精确值，
  /// 不再需要手动用字符宽度估算（避免右侧留白）。
  void _resizeIfNeeded(Size size) {
    if (size.isEmpty) return;
    // 读取 TerminalView 已设置好的实际列/行数
    final cols = _terminal.viewWidth;
    final rows = _terminal.viewHeight;
    if (cols == _termCols && rows == _termRows) return;
    _termCols = cols;
    _termRows = rows;
    // 防抖 300ms：拖拽窗口过程中不向远端频繁发 stty
    _resizeDebounce?.cancel();
    _resizeDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        widget.session.send('stty cols $cols rows $rows\n');
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

  /// 上传文件到远端（Base64 编码通过终端传输）
  Future<void> _uploadFile() async {
    if (_uploading) return;
    final file = await openFile(acceptedTypeGroups: const [XTypeGroup(label: '所有文件')]);
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;

    final remotePath = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController(text: '/tmp/${file.name}');
        return AlertDialog(
          backgroundColor: AppColors.bgCard,
          title: Text('上传到远端路径', style: AppTextStyles.heading(size: 16)),
          content: TextField(
            controller: ctrl,
            style: AppTextStyles.terminal(size: 13, color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: '/path/to/file',
              hintStyle: AppTextStyles.caption(size: 12, color: AppColors.textMuted),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('上传')),
          ],
        );
      },
    );
    if (remotePath == null || remotePath.isEmpty || !mounted) return;

    setState(() => _uploading = true);
    try {
      final b64 = base64Encode(bytes);
      const chunkSize = 40000;
      final chunks = <String>[];
      for (var i = 0; i < b64.length; i += chunkSize) {
        chunks.add(b64.substring(i, (i + chunkSize > b64.length) ? b64.length : i + chunkSize));
      }
      final escapedPath = remotePath.replaceAll("'", "'\\''");
      if (chunks.length == 1) {
        widget.session.send("echo '$b64' | base64 -d > '$escapedPath'\n");
      } else {
        widget.session.send("rm -f '$escapedPath.b64'\n");
        for (final chunk in chunks) {
          final esc = chunk.replaceAll("'", "'\\''");
          widget.session.send("echo '$esc' >> '$escapedPath.b64'\n");
        }
        widget.session.send("base64 -d '$escapedPath.b64' > '$escapedPath' && rm -f '$escapedPath.b64'\n");
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已发送上传命令：$remotePath'), backgroundColor: AppColors.primary),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// 从远端下载文件（通过 base64 命令捕获输出）
  Future<void> _downloadFile() async {
    if (_downloading) return;
    final remotePath = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          backgroundColor: AppColors.bgCard,
          title: Text('下载远端文件', style: AppTextStyles.heading(size: 16)),
          content: TextField(
            controller: ctrl,
            style: AppTextStyles.terminal(size: 13, color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: '/path/to/remote/file',
              hintStyle: AppTextStyles.caption(size: 12, color: AppColors.textMuted),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('下载')),
          ],
        );
      },
    );
    if (remotePath == null || remotePath.isEmpty || !mounted) return;

    setState(() => _downloading = true);
    const startMarker = 'MATRIX_B64_START';
    const endMarker = 'MATRIX_B64_END';
    final buffer = StringBuffer();
    StreamSubscription<List<int>>? captureSub;
    final completer = Completer<List<int>>();

    captureSub = widget.session.rawStream.listen(
      (data) {
        buffer.write(utf8.decode(data, allowMalformed: true));
        final s = buffer.toString();
        final startIdx = s.indexOf(startMarker);
        final endIdx = s.indexOf(endMarker);
        if (startIdx != -1 && endIdx != -1 && endIdx > startIdx) {
          final b64 = s.substring(startIdx + startMarker.length, endIdx).replaceAll(RegExp(r'\s'), '');
          try {
            final decoded = base64Decode(b64);
            captureSub?.cancel();
            if (!completer.isCompleted) completer.complete(decoded);
          } catch (_) {
            if (!completer.isCompleted) completer.completeError('Base64 解码失败');
          }
        }
      },
      onDone: () {
        if (!completer.isCompleted) completer.completeError('连接已断开');
      },
      onError: (e, _) {
        if (!completer.isCompleted) completer.completeError(e);
      },
    );

    widget.session.send("echo $startMarker; base64 '${remotePath.replaceAll("'", "'\\''")}'; echo $endMarker\n");

    try {
      final decoded = await completer.future.timeout(const Duration(seconds: 60));
      if (mounted) {
        await _saveDownloadedFile(decoded, remotePath.split('/').last);
      }
    } catch (e) {
      captureSub.cancel();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载失败: $e'), backgroundColor: AppColors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _saveDownloadedFile(List<int> bytes, String defaultName) async {
    final location = await getSaveLocation(suggestedName: defaultName);
    if (location == null || !mounted) return;
    final file = File(location.path);
    await file.writeAsBytes(bytes);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已保存到 ${location.path}'), backgroundColor: AppColors.primary),
      );
    }
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
                  IconButton(
                    onPressed: _uploading ? null : _uploadFile,
                    icon: const Icon(Icons.upload_file, size: 18),
                    tooltip: '上传文件',
                    color: AppColors.textSecondary,
                  ),
                  IconButton(
                    onPressed: _downloading ? null : _downloadFile,
                    icon: const Icon(Icons.download_outlined, size: 18),
                    tooltip: '下载文件',
                    color: AppColors.textSecondary,
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      _closedManually = true;
                      final nav = Navigator.of(context);
                      await widget.session.close();
                      if (!mounted) return;
                      nav.pop();
                    },
                    icon: const Icon(Icons.power_settings_new,
                        size: 16, color: AppColors.red),
                    label: Text(
                      '主动断开',
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
                    if (t.isNotEmpty) {
                      // Bracketed Paste Mode：告知远端 bash 这是粘贴而非逐键输入，
                      // 避免大量内容被 readline 逐字符处理导致缓冲区溢出、从头覆盖
                      widget.session.send('\x1b[200~$t\x1b[201~');
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

