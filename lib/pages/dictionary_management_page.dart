import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../database/database_helper.dart';
import '../models/dictionary.dart';
import '../theme/app_theme.dart';

// ── 分类配色 / 图标 ──────────────────────────────────────────────────────────

const _catColor = {
  'passwords': Color(0xFFE06C75),
  'usernames': Color(0xFF61AFEF),
  'paths':     Color(0xFF56B6C2),
  'subdomains':Color(0xFFC678DD),
  'custom':    Color(0xFF56C2A6),
};

const _catIcon = {
  'passwords':  Icons.lock_outline,
  'usernames':  Icons.person_outline,
  'paths':      Icons.folder_open_outlined,
  'subdomains': Icons.dns_outlined,
  'custom':     Icons.list_alt_outlined,
};

const _catLabels = {
  'passwords':  'Passwords',
  'usernames':  'Usernames',
  'paths':      'Paths',
  'subdomains': 'Subdomains',
  'custom':     'Custom',
};

Color _colorOf(String cat) => _catColor[cat] ?? const Color(0xFF56C2A6);
IconData _iconOf(String cat) => _catIcon[cat] ?? Icons.list_alt_outlined;
String _labelOf(String cat) => _catLabels[cat] ?? cat;

String _fmtSize(int bytes) {
  if (bytes < 1024) return '${bytes}B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
}

String _fmtLines(int n) {
  if (n < 1000) return '$n L';
  if (n < 1000000) return '${(n / 1000).toStringAsFixed(1)}K L';
  return '${(n / 1000000).toStringAsFixed(2)}M L';
}

// ── 主页面 ───────────────────────────────────────────────────────────────────

class DictionaryManagementPage extends StatefulWidget {
  const DictionaryManagementPage({super.key});

  @override
  State<DictionaryManagementPage> createState() =>
      _DictionaryManagementPageState();
}

class _DictionaryManagementPageState extends State<DictionaryManagementPage> {
  final DatabaseHelper _db = DatabaseHelper();
  List<Dictionary> _dicts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _db.getAllDictionaries();
    setState(() {
      _dicts = list;
      _loading = false;
    });
  }

  Future<void> _importFromFile() async {
    try {
      const typeGroup = XTypeGroup(
        label: 'Dictionaries',
        extensions: ['txt', 'lst', 'dict', 'csv', 'wordlist'],
      );
      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (file == null) return;

      final bytes = await file.readAsBytes();

      // 分类选择弹窗
      if (!mounted) return;
      final category = await _pickCategory();
      if (category == null) return;

      await _db.createDictionary(
        name: file.name,
        category: category,
        bytes: bytes,
      );
      if (!mounted) return;
      _showSnack('已导入 ${file.name}');
      await _load();
    } catch (e) {
      if (!mounted) return;
      _showSnack('导入失败: $e', error: true);
    }
  }

  Future<String?> _pickCategory() {
    return showDialog<String>(
      context: context,
      builder: (_) => _CategoryPickerDialog(),
    );
  }

  Future<void> _downloadToFile(Dictionary dict) async {
    final location = await getSaveLocation(
      suggestedName: dict.name,
      acceptedTypeGroups: [
        const XTypeGroup(label: 'All', extensions: ['txt', 'lst', 'dict']),
      ],
    );
    if (location == null) return;
    try {
      await File(dict.filePath).copy(location.path);
      if (!mounted) return;
      _showSnack('已保存到 ${location.path}');
    } catch (e) {
      if (!mounted) return;
      _showSnack('保存失败: $e', error: true);
    }
  }

  Future<void> _copyPreviewToClipboard(Dictionary dict) async {
    try {
      String text;
      if (dict.filePath.isNotEmpty) {
        text = await _db.readDictionaryPreview(dict.filePath, maxLines: 500);
      } else {
        text = '// Web 模式无法访问文件';
      }
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      _showSnack('已复制前 500 行到剪贴板');
    } catch (e) {
      if (!mounted) return;
      _showSnack('复制失败: $e', error: true);
    }
  }

  Future<void> _delete(Dictionary dict) async {
    if (dict.isDefault) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmDeleteDialog(name: dict.name),
    );
    if (confirmed != true) return;
    await _db.deleteDictionary(dict.id);
    await _load();
  }

  void _showDetail(Dictionary dict) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (_) => _DictDetailDialog(
        dict: dict,
        db: _db,
        onCopy: () => _copyPreviewToClipboard(dict),
        onDownload: () => _downloadToFile(dict),
        onDelete: () async {
          Navigator.pop(context);
          await _delete(dict);
        },
      ),
    );
  }

  void _showSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: AppTextStyles.caption(
              color: error ? AppColors.red : AppColors.primary),
        ),
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
                '${_dicts.length} files',
                style: AppTextStyles.caption(
                    size: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        const Spacer(),
        _TbBtn(icon: Icons.refresh, tooltip: '刷新', onPressed: _load),
        const SizedBox(width: 6),
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
          label: Text('导入字典',
              style: AppTextStyles.body(size: 13, color: AppColors.bgDark)),
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

    if (_dicts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_outlined,
                size: 40, color: AppColors.primary.withValues(alpha: 0.25)),
            const SizedBox(height: 12),
            Text('no dictionaries found',
                style: AppTextStyles.body(color: AppColors.textMuted)),
            const SizedBox(height: 4),
            Text('import a wordlist to get started',
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
      itemCount: _dicts.length,
      itemBuilder: (context, i) => _DictCard(
        dict: _dicts[i],
        onTap: () => _showDetail(_dicts[i]),
        onDelete: () => _delete(_dicts[i]),
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

// ── 字典文件卡片 ──────────────────────────────────────────────────────────────

class _DictCard extends StatefulWidget {
  final Dictionary dict;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _DictCard(
      {required this.dict, required this.onTap, required this.onDelete});

  @override
  State<_DictCard> createState() => _DictCardState();
}

class _DictCardState extends State<_DictCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = _colorOf(widget.dict.category);
    final icon = _iconOf(widget.dict.category);

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
                    ),
                  ]
                : [],
          ),
          child: Stack(
            children: [
              // 顶部分类色条
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: _hovered ? 0.8 : 0.4),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(9)),
                  ),
                ),
              ),

              // 右上角：默认项锁图标，非默认项 hover 时删除按钮
              if (widget.dict.isDefault)
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
                        border:
                            Border.all(color: color.withValues(alpha: 0.28)),
                      ),
                      child: Icon(icon, size: 24, color: color),
                    ),
                    const SizedBox(height: 10),
                    // 文件名
                    Text(
                      widget.dict.name,
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
                    // 行数 + 大小
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _CatBadge(
                            category: widget.dict.category, color: color),
                        const SizedBox(width: 6),
                        Text(
                          _fmtLines(widget.dict.lineCount),
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

class _CatBadge extends StatelessWidget {
  final String category;
  final Color color;

  const _CatBadge({required this.category, required this.color});

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
        _labelOf(category).toUpperCase(),
        style: AppTextStyles.caption(size: 9, color: color),
      ),
    );
  }
}

// ── 分类选择弹窗 ──────────────────────────────────────────────────────────────

class _CategoryPickerDialog extends StatelessWidget {
  const _CategoryPickerDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      title: Text('选择字典分类',
          style: AppTextStyles.heading(
              size: 14, color: AppColors.textPrimary)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: _catLabels.entries.map((e) {
          final color = _colorOf(e.key);
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: InkWell(
              onTap: () => Navigator.pop(context, e.key),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: color.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    Icon(_iconOf(e.key), size: 16, color: color),
                    const SizedBox(width: 10),
                    Text(e.value,
                        style: AppTextStyles.body(
                            size: 13, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('取消',
              style:
                  AppTextStyles.body(color: AppColors.textSecondary)),
        ),
      ],
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
          Text('删除字典',
              style:
                  AppTextStyles.heading(size: 14, color: AppColors.red)),
        ],
      ),
      content: Text(
        '确定要删除 "$name" 吗？\n此操作不可撤销。',
        style:
            AppTextStyles.body(size: 13, color: AppColors.textSecondary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('取消',
              style:
                  AppTextStyles.body(color: AppColors.textSecondary)),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.red.withValues(alpha: 0.85),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6)),
          ),
          child: Text('删除',
              style: AppTextStyles.body(color: AppColors.bgDark)),
        ),
      ],
    );
  }
}

// ── 内容预览弹窗 ─────────────────────────────────────────────────────────────

class _DictDetailDialog extends StatefulWidget {
  final Dictionary dict;
  final DatabaseHelper db;
  final VoidCallback onCopy;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  const _DictDetailDialog({
    required this.dict,
    required this.db,
    required this.onCopy,
    required this.onDownload,
    required this.onDelete,
  });

  @override
  State<_DictDetailDialog> createState() => _DictDetailDialogState();
}

class _DictDetailDialogState extends State<_DictDetailDialog> {
  final ScrollController _scrollController = ScrollController();
  String _preview = '';
  bool _loadingPreview = true;
  static const _kPreviewLines = 300;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    final text = await widget.db.readDictionaryPreview(
      widget.dict.filePath,
      maxLines: _kPreviewLines,
    );
    if (!mounted) return;
    setState(() {
      _preview = text;
      _loadingPreview = false;
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorOf(widget.dict.category);
    final lines = _preview.isEmpty ? [] : _preview.split('\n');
    final isPartial = widget.dict.lineCount > _kPreviewLines;

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
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(13)),
                border: const Border(
                    bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(_iconOf(widget.dict.category),
                        size: 16, color: color),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.dict.name,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body(
                          size: 13, color: AppColors.textPrimary),
                    ),
                  ),
                  // 统计信息
                  Text(
                    '${_fmtLines(widget.dict.lineCount)}  ${_fmtSize(widget.dict.fileSize)}',
                    style: AppTextStyles.caption(
                        size: 11, color: AppColors.textMuted),
                  ),
                  const SizedBox(width: 14),
                  _DialogBtn(
                      icon: Icons.copy_outlined,
                      label: '复制',
                      onPressed: widget.onCopy),
                  const SizedBox(width: 6),
                  _DialogBtn(
                      icon: Icons.download_outlined,
                      label: '下载',
                      onPressed: widget.onDownload),
                  const SizedBox(width: 6),
                  if (!widget.dict.isDefault) ...[
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

            // ── 预览提示条（仅当文件超出预览行数时显示）─────────────────
            if (isPartial)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 6),
                color: color.withValues(alpha: 0.07),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 13, color: color.withValues(alpha: 0.7)),
                    const SizedBox(width: 6),
                    Text(
                      '仅显示前 $_kPreviewLines 行（共 ${_fmtLines(widget.dict.lineCount)}）',
                      style: AppTextStyles.caption(
                          size: 11,
                          color: color.withValues(alpha: 0.85)),
                    ),
                  ],
                ),
              ),

            // ── 内容区 ──────────────────────────────────────────
            Expanded(
              child: _loadingPreview
                  ? Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary.withValues(alpha: 0.6),
                        ),
                      ),
                    )
                  : Container(
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
                            padding:
                                const EdgeInsets.symmetric(vertical: 12),
                            child: IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: [
                                  // 行号列
                                  Container(
                                    width: 48,
                                    color: AppColors.bgElevated,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children:
                                          List.generate(lines.length, (i) {
                                        return SizedBox(
                                          height: 19,
                                          child: Text(
                                            '${i + 1}',
                                            style: AppTextStyles.caption(
                                                size: 11,
                                                color:
                                                    AppColors.textMuted),
                                          ),
                                        );
                                      }),
                                    ),
                                  ),
                                  Container(
                                      width: 1,
                                      color: AppColors.border),
                                  // 内容
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                          left: 12, right: 12),
                                      child: SelectableText(
                                        _preview,
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
            Text(label, style: AppTextStyles.caption(size: 11, color: c)),
          ],
        ),
      ),
    );
  }
}
