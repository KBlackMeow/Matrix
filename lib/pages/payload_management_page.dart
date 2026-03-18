import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../database/database_helper.dart';
import '../models/payload.dart';
import '../theme/app_theme.dart';

// ── 类型配色 / 图标 ──────────────────────────────────────────────────────────

const _typeColor = {
  'php': Color(0xFF8892BF),
  'jsp': Color(0xFFF89820),
  'asp': Color(0xFF68B5E8),
  'other': Color(0xFF56C2A6),
};

const _typeIcon = {
  'php': Icons.php,
  'jsp': Icons.coffee_outlined,
  'asp': Icons.window_outlined,
  'other': Icons.code,
};

Color _colorOf(String type) => _typeColor[type] ?? const Color(0xFF56C2A6);
IconData _iconOf(String type) => _typeIcon[type] ?? Icons.code;

// ── 主页面 ───────────────────────────────────────────────────────────────────

class PayloadManagementPage extends StatefulWidget {
  const PayloadManagementPage({super.key});

  @override
  State<PayloadManagementPage> createState() => _PayloadManagementPageState();
}

class _PayloadManagementPageState extends State<PayloadManagementPage> {
  final DatabaseHelper _db = DatabaseHelper();
  List<Payload> _payloads = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _db.getAllPayloads();
    setState(() {
      _payloads = list;
      _loading = false;
    });
  }

  Future<void> _importFromFile() async {
    try {
      const typeGroup = XTypeGroup(
        label: 'Scripts',
        extensions: ['php', 'jsp', 'asp', 'txt'],
      );
      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (file == null) return;

      final bytes = await file.readAsBytes();
      final content = utf8.decode(bytes, allowMalformed: true);
      final name = file.name;
      final ext =
          name.contains('.') ? name.split('.').last.toLowerCase() : 'txt';
      final type = ['php', 'jsp', 'asp'].contains(ext) ? ext : 'other';

      await _db.createPayload(name: name, type: type, content: content);
      if (!mounted) return;
      _showSnack('已导入 $name');
      await _load();
    } catch (e) {
      if (!mounted) return;
      _showSnack('导入失败: $e', error: true);
    }
  }

  Future<void> _downloadToFile(Payload payload) async {
    // 完全尊重 payload.name，不再自动补扩展名，让用户自行控制文件名
    final suggestedName =
        payload.name.isNotEmpty ? payload.name : 'payload_${payload.id}.txt';

    final location = await getSaveLocation(
      suggestedName: suggestedName,
    );
    if (location == null) return;
    try {
      await File(location.path).writeAsString(payload.content);
      if (!mounted) return;
      _showSnack('已保存到 ${location.path}');
    } catch (e) {
      if (!mounted) return;
      _showSnack('保存失败: $e', error: true);
    }
  }

  Future<void> _copyToClipboard(Payload payload) async {
    await Clipboard.setData(ClipboardData(text: payload.content));
    if (!mounted) return;
    _showSnack('已复制到剪贴板');
  }

  Future<void> _copyAsBase64(Payload payload) async {
    final b64 = base64Encode(utf8.encode(payload.content));
    await Clipboard.setData(ClipboardData(text: b64));
    if (!mounted) return;
    _showSnack('已复制为 Base64');
  }

  Future<void> _delete(Payload payload) async {
    if (payload.isDefault) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmDeleteDialog(name: payload.name),
    );
    if (confirmed != true) return;
    await _db.deletePayload(payload.id);
    await _load();
  }

  void _showDetail(Payload payload) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (_) => _PayloadDetailDialog(
        payload: payload,
        onCopy: () => _copyToClipboard(payload),
        onCopyBase64: () => _copyAsBase64(payload),
        onDownload: () => _downloadToFile(payload),
        onDelete: () async {
          Navigator.pop(context);
          await _delete(payload);
        },
      ),
    );
  }

  void _showSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg,
            style: AppTextStyles.caption(
                color: error ? AppColors.red : AppColors.primary)),
        backgroundColor: AppColors.bgElevated,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: (error ? AppColors.red : AppColors.primary)
                .withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildToolbar(),
        const SizedBox(height: 16),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildToolbar() {
    return Row(
      children: [
        // 总数统计
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.bgElevated,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.folder_outlined,
                  size: 13, color: AppColors.textSecondary),
              const SizedBox(width: 5),
              Text(
                '${_payloads.length} files',
                style:
                    AppTextStyles.caption(size: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        const Spacer(),
        // 刷新
        _TbBtn(
          icon: Icons.refresh,
          tooltip: '刷新',
          onPressed: _load,
        ),
        const SizedBox(width: 6),
        // 导入
        FilledButton.icon(
          onPressed: _importFromFile,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.bgDark,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          icon: const Icon(Icons.file_upload_outlined, size: 15),
          label: Text('导入文件',
              style: AppTextStyles.body(
                  size: 13,
                  color: AppColors.bgDark)),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primary.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 10),
            Text('loading...',
                style: AppTextStyles.caption(color: AppColors.textMuted)),
          ],
        ),
      );
    }

    if (_payloads.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.terminal,
                size: 40,
                color: AppColors.primary.withValues(alpha: 0.25)),
            const SizedBox(height: 12),
            Text('no payloads found',
                style: AppTextStyles.body(color: AppColors.textMuted)),
            const SizedBox(height: 4),
            Text('import a file to get started',
                style: AppTextStyles.caption(
                    color: AppColors.textMuted.withValues(alpha: 0.6))),
          ],
        ),
      );
    }

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 176,
        mainAxisExtent: 148,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: _payloads.length,
      itemBuilder: (context, i) => _PayloadCard(
        payload: _payloads[i],
        onTap: () => _showDetail(_payloads[i]),
        onDelete: () => _delete(_payloads[i]),
      ),
    );
  }
}

// ── 工具栏小按钮 ─────────────────────────────────────────────────────────────

class _TbBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _TbBtn(
      {required this.icon, required this.tooltip, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppColors.bgElevated,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.border),
          ),
          child: Icon(icon, size: 15, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}

// ── 文件卡片 ─────────────────────────────────────────────────────────────────

class _PayloadCard extends StatefulWidget {
  final Payload payload;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _PayloadCard(
      {required this.payload, required this.onTap, required this.onDelete});

  @override
  State<_PayloadCard> createState() => _PayloadCardState();
}

class _PayloadCardState extends State<_PayloadCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = _colorOf(widget.payload.type);
    final icon = _iconOf(widget.payload.type);
    final lines = '\n'.allMatches(widget.payload.content).length + 1;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: _hovered ? AppColors.bgElevated : AppColors.bgCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _hovered
                  ? color.withValues(alpha: 0.55)
                  : AppColors.border,
              width: _hovered ? 1.2 : 1,
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.14),
                      blurRadius: 14,
                      spreadRadius: 0,
                    ),
                  ]
                : [],
          ),
          child: Stack(
            children: [
              // 顶部类型色条
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: _hovered ? 0.8 : 0.4),
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(9)),
                  ),
                ),
              ),

              // 右上角：默认项显示锁图标，非默认项 hover 时显示删除按钮
              if (widget.payload.isDefault)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Tooltip(
                    message: '内置默认，不可删除',
                    child: Icon(Icons.lock_outline,
                        size: 12,
                        color: AppColors.textMuted.withValues(alpha: 0.5)),
                  ),
                )
              else if (_hovered)
                Positioned(
                  top: 6,
                  right: 6,
                  child: GestureDetector(
                    onTap: widget.onDelete,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: AppColors.bgDark,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: AppColors.red.withValues(alpha: 0.5)),
                      ),
                      child: Icon(Icons.close,
                          size: 11,
                          color: AppColors.red.withValues(alpha: 0.8)),
                    ),
                  ),
                ),

              // 主体
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // 图标
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: color.withValues(alpha: 0.28)),
                      ),
                      child: Icon(icon, size: 24, color: color),
                    ),
                    const SizedBox(height: 10),
                    // 文件名
                    Text(
                      widget.payload.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.body(
                        size: 11,
                        color: _hovered
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // 类型标签 + 行数
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _TypeBadge(type: widget.payload.type, color: color),
                        const SizedBox(width: 6),
                        Text(
                          '$lines L',
                          style: AppTextStyles.caption(
                              size: 9, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  final String type;
  final Color color;

  const _TypeBadge({required this.type, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        type.toUpperCase(),
        style: AppTextStyles.caption(size: 9, color: color),
      ),
    );
  }
}

// ── 删除确认弹窗 ─────────────────────────────────────────────────────────────

class _ConfirmDeleteDialog extends StatelessWidget {
  final String name;

  const _ConfirmDeleteDialog({required this.name});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.red.withValues(alpha: 0.3)),
      ),
      title: Row(
        children: [
          Icon(Icons.warning_amber_outlined,
              size: 18, color: AppColors.red.withValues(alpha: 0.8)),
          const SizedBox(width: 8),
          Text('删除 Payload',
              style: AppTextStyles.heading(size: 14, color: AppColors.red)),
        ],
      ),
      content: Text(
        '确定要删除 "$name" 吗？\n此操作不可撤销。',
        style: AppTextStyles.body(size: 13, color: AppColors.textSecondary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('取消',
              style: AppTextStyles.body(color: AppColors.textSecondary)),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.red.withValues(alpha: 0.85),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          child: Text('删除',
              style: AppTextStyles.body(color: AppColors.bgDark)),
        ),
      ],
    );
  }
}

// ── 内容详情弹窗 ─────────────────────────────────────────────────────────────

class _PayloadDetailDialog extends StatefulWidget {
  final Payload payload;
  final VoidCallback onCopy;
  final VoidCallback onCopyBase64;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  const _PayloadDetailDialog({
    required this.payload,
    required this.onCopy,
    required this.onCopyBase64,
    required this.onDownload,
    required this.onDelete,
  });

  @override
  State<_PayloadDetailDialog> createState() => _PayloadDetailDialogState();
}

class _PayloadDetailDialogState extends State<_PayloadDetailDialog> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorOf(widget.payload.type);
    final lines = widget.payload.content.split('\n');

    return Dialog(
      backgroundColor: AppColors.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color.withValues(alpha: 0.25)),
      ),
      child: SizedBox(
        width: 760,
        height: 580,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 标题栏 ──────────────────────────────────────────
            Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                color: AppColors.bgElevated,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(13)),
                border: const Border(
                    bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  // 类型图标 + 文件名
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(_iconOf(widget.payload.type),
                        size: 16, color: color),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.payload.name,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body(
                          size: 13, color: AppColors.textPrimary),
                    ),
                  ),
                  // 行数统计
                  Text(
                    '${lines.length} lines',
                    style: AppTextStyles.caption(
                        size: 11, color: AppColors.textMuted),
                  ),
                  const SizedBox(width: 14),
                  // 操作按钮
                  _DialogBtn(
                      icon: Icons.copy_outlined,
                      label: '复制',
                      onPressed: widget.onCopy),
                  const SizedBox(width: 6),
                  _DialogBtn(
                      icon: Icons.code,
                      label: '复制为Base64',
                      onPressed: widget.onCopyBase64),
                  const SizedBox(width: 6),
                  _DialogBtn(
                      icon: Icons.download_outlined,
                      label: '下载',
                      onPressed: widget.onDownload),
                  const SizedBox(width: 6),
                  if (!widget.payload.isDefault) ...[
                    _DialogBtn(
                        icon: Icons.delete_outline,
                        label: '删除',
                        color: AppColors.red,
                        onPressed: widget.onDelete),
                    const SizedBox(width: 6),
                  ],
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    borderRadius: BorderRadius.circular(4),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close,
                          size: 16, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),

            // ── 代码区（行号 + 内容）──────────────────────────────
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.bgDark,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Scrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    trackVisibility: true,
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // 行号列
                            Container(
                              width: 48,
                              color: AppColors.bgElevated,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.end,
                                children: List.generate(
                                  lines.length,
                                  (i) => SizedBox(
                                    height: 19,
                                    child: Text(
                                      '${i + 1}',
                                      style: AppTextStyles.caption(
                                          size: 11,
                                          color: AppColors.textMuted),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Container(
                                width: 1,
                                color: AppColors.border),
                            // 代码内容
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(
                                    left: 12, right: 12),
                                child: SelectableText(
                                  widget.payload.content,
                                  style: AppTextStyles.terminal(
                                    size: 12.5,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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

class _DialogBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onPressed;

  const _DialogBtn(
      {required this.icon,
      required this.label,
      required this.onPressed,
      this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textSecondary;
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: c.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: c),
            const SizedBox(width: 4),
            Text(label,
                style: AppTextStyles.caption(size: 11, color: c)),
          ],
        ),
      ),
    );
  }
}
