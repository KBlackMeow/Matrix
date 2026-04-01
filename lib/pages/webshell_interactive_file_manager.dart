import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/webshell_service.dart';
import '../theme/app_theme.dart';

// ─── 文件管理 Tab ──────────────────────────────────────────────────────────────

class FileManagerTab extends StatefulWidget {
  final WebshellService service;
  final void Function(String dir) onInvalidateCompleterDir;

  const FileManagerTab({
    super.key,
    required this.service,
    required this.onInvalidateCompleterDir,
  });

  @override
  State<FileManagerTab> createState() => _FileManagerTabState();
}

class _FileManagerTabState extends State<FileManagerTab>
    with AutomaticKeepAliveClientMixin {
  String _currentPath = '/';
  List<FileEntry> _files = [];
  bool _loading = true;
  bool _uploading = false;
  bool _downloading = false;
  String? _downloadDir;
  String? _errorMsg;
  bool _uploadCancelled = false;
  bool _downloadCancelled = false;

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
        onSaved: () {
          _loadDirectory(_currentPath);
          widget.onInvalidateCompleterDir(_parent(path));
        },
      ),
    );
  }

  Future<void> _uploadFile() async {
    if (!widget.service.supportsFileWrite) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('当前连接器不支持文件写入'),
        backgroundColor: AppColors.red,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    final file = await openFile(acceptedTypeGroups: const [XTypeGroup(label: '所有文件')]);
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    final remotePath = _join(_currentPath, file.name);
    final transferred = ValueNotifier<int>(0);
    _uploadCancelled = false;
    bool ok = false;
    bool usedBinaryPath = false;
    try {
      // 若检测为文本文件且体积较小，则走文本写入；大文件一律走分块上传，避免单次请求超限。
      final looksBinary = _isBinary(bytes);
      final useBinaryPath = looksBinary || bytes.length > 100 * 1024;
      if (!useBinaryPath) {
        setState(() => _uploading = true);
        final content = utf8.decode(bytes);
        ok = await widget.service.writeFile(remotePath, content);
      } else {
        usedBinaryPath = true; // 二进制文件或大文件（>100KB）走分块
        setState(() => _uploading = true);
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => _TransferProgressDialog(
            fileName: file.name,
            fileSize: bytes.length,
            transferred: transferred,
            isUpload: true,
            onCancel: () {
              _uploadCancelled = true;
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
          ),
        );
        ok = await widget.service.writeFileBinaryWithProgress(
          remotePath,
          bytes,
          (sent, _) {
              if (!mounted) return;
              if (_uploadCancelled) {
                throw _TransferCancelled();
              }
              transferred.value = sent;
          },
        );
      }
    } catch (e) {
      if (!mounted) return;
      // 不再主动关闭当前页面，仅结束上传状态和进度
      setState(() => _uploading = false);
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      transferred.dispose();
      if (e is _TransferCancelled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '上传已取消',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Color(0xFF064D2E), // 暗绿色背景
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        debugPrint(
          '[Matrix][上传] 异常 file=${file.name} path=$remotePath size=${bytes.length} error=$e',
        );
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('上传失败: $e', style: const TextStyle(color: Colors.white)),
          backgroundColor: AppColors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }
    // 若二进制路径失败且是“看起来像文本”的文件，尝试自动回退到文本写入。
    if (!ok && !usedBinaryPath) {
      try {
        final content = utf8.decode(bytes);
        ok = await widget.service.writeFile(remotePath, content);
      } catch (_) {
        // ignore, 保持原有失败提示
      }
    }

    if (!mounted) {
      transferred.dispose();
      return;
    }
    setState(() => _uploading = false);
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    transferred.dispose();
    if (!ok) {
      debugPrint(
        '[Matrix][上传] 失败 file=${file.name} path=$remotePath size=${bytes.length} '
        'usedBinaryPath=$usedBinaryPath',
      );
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? '已上传 ${file.name}' : '上传失败',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor:
            ok ? const Color(0xFF064D2E) : AppColors.red, // 成功用暗绿，失败用红
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (ok) {
      _loadDirectory(_currentPath);
      widget.onInvalidateCompleterDir(_parent(remotePath));
    }
  }

  /// 粗略判断文件是否为二进制：
  /// - 采样前若干字节，如存在 NUL 字节则视为二进制；
  /// - 否则尝试按 UTF-8 解码，失败则视为二进制。
  bool _isBinary(List<int> bytes) {
    if (bytes.isEmpty) return false;
    final sampleLen = bytes.length > 4096 ? 4096 : bytes.length;
    for (var i = 0; i < sampleLen; i++) {
      if (bytes[i] == 0) return true;
    }
    try {
      utf8.decode(bytes, allowMalformed: false);
      return false;
    } catch (_) {
      return true;
    }
  }

  Future<void> _downloadFile(FileEntry entry) async {
    if (_downloading) return;
    if (_downloadDir == null) {
      final dir = await getDirectoryPath(confirmButtonText: '选择下载目录');
      if (dir == null || !mounted) return;
      setState(() => _downloadDir = dir);
    }
    setState(() {
      _downloading = true;
      _downloadCancelled = false;
    });
    final remotePath = _join(_currentPath, entry.name);
    final localPath = '${_downloadDir!}${Platform.pathSeparator}${entry.name}';
    // download is a single HTTP round-trip, so use indeterminate indicator
    final transferred = ValueNotifier<int>(0);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TransferProgressDialog(
        fileName: entry.name,
        fileSize: entry.size,
        transferred: transferred,
        isUpload: false,
        onCancel: () {
          _downloadCancelled = true;
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        },
      ),
    );
    try {
      final bytes = await widget.service.readFileBinary(remotePath);
      if (!mounted) {
        transferred.dispose();
        return;
      }
      if (_downloadCancelled) {
        // 已被用户取消，丢弃结果
        setState(() => _downloading = false);
        transferred.dispose();
        return;
      }
      await File(localPath).writeAsBytes(bytes, flush: true);
      if (!mounted) {
        transferred.dispose();
        return;
      }
      setState(() => _downloading = false);
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      transferred.dispose();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已保存至 $localPath',
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: const Color(0xFF064D2E), // 暗绿色背景
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) { transferred.dispose(); return; }
      Navigator.of(context).pop();
      setState(() => _downloading = false);
      transferred.dispose();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            Text('下载失败: $e', style: const TextStyle(color: Colors.white)),
        backgroundColor: AppColors.red,
        behavior: SnackBarBehavior.floating,
      ));
    }
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
    final deletedPath = _join(_currentPath, entry.name);
    final ok = await widget.service.deleteFile(deletedPath);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? '已删除 ${entry.name}' : '删除失败',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: ok
            ? const Color(0xFF064D2E) // 删除成功用暗绿色
            : AppColors.red, // 失败仍用红色
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (ok) {
      _loadDirectory(_currentPath);
      widget.onInvalidateCompleterDir(_parent(deletedPath));
    }
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
              if (widget.service.supportsFileWrite)
                IconButton(
                  onPressed: _loading || _uploading || _downloading ? null : _uploadFile,
                  icon: const Icon(Icons.upload_file, size: 16),
                  color: AppColors.primary,
                  tooltip: '上传文件',
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
        LayoutBuilder(
          builder: (ctx, constraints) {
            final w = constraints.maxWidth;
            return Container(
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
                  if (w > 480) _colHeader('大小', width: 80),
                  if (w > 560) _colHeader('权限', width: 60),
                  if (w > 640) _colHeader('修改时间', width: 130),
                  SizedBox(width: w > 480 ? 120 : 100),
                ],
              ),
            );
          },
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
                      onDownload: f.isDirectory || f.name == '..' || _downloading
                          ? null
                          : widget.service.supportsFileRead
                              ? () => _downloadFile(f)
                              : null,
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
  final VoidCallback? onDownload;
  final VoidCallback? onDelete;

  const _FileRow({
    required this.entry,
    this.onTap,
    this.onView,
    this.onEdit,
    this.onDownload,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isUp = entry.name == '..';
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final w = constraints.maxWidth;
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
            if (w > 480)
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
            if (w > 560)
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
            if (w > 640)
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
              width: w > 480 ? 120 : 100,
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
                  if (onDownload != null)
                    _iconBtn(
                      Icons.download_outlined,
                      AppColors.primaryDim,
                      '下载',
                      onDownload!,
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
      },
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

// ─── 传输进度对话框 ─────────────────────────────────────────────────────────────

class _TransferProgressDialog extends StatelessWidget {
  final String fileName;
  final int fileSize;
  final ValueNotifier<int> transferred;
  final bool isUpload;
  final VoidCallback onCancel;

  const _TransferProgressDialog({
    required this.fileName,
    required this.fileSize,
    required this.transferred,
    required this.isUpload,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SizedBox(
          width: 360,
          child: ValueListenableBuilder<int>(
            valueListenable: transferred,
            builder: (_, sent, _) {
              // Upload: deterministic progress; download: always indeterminate
              final double? progress = isUpload && fileSize > 0
                  ? (sent / fileSize).clamp(0.0, 1.0)
                  : null;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        isUpload ? Icons.upload_file : Icons.download_outlined,
                        color: AppColors.primary,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isUpload ? '上传中' : '下载中',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: onCancel,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          minimumSize: const Size(0, 0),
                        ),
                        child: Text(
                          '取消',
                          style: AppTextStyles.caption(
                            color: AppColors.textSecondary,
                            size: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    fileName,
                    style: AppTextStyles.terminal(size: 12, color: AppColors.cyan),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      backgroundColor: AppColors.bgDark,
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(AppColors.primary),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (progress != null)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${_fmtSize(sent)} / ${_fmtSize(fileSize)}',
                          style: AppTextStyles.caption(
                              color: AppColors.textSecondary, size: 11),
                        ),
                        Text(
                          '${(progress * 100).round()}%',
                          style: AppTextStyles.caption(
                              color: AppColors.primary, size: 11),
                        ),
                      ],
                    )
                  else
                    Text(
                      isUpload ? '正在上传...' : '正在接收数据，请稍候...',
                      style: AppTextStyles.caption(
                          color: AppColors.textSecondary, size: 11),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  static String _fmtSize(int bytes) {
    if (bytes <= 0) return '—';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}

class _TransferCancelled implements Exception {}

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
                          fontFamilyFallback: [
                            'Courier New',
                            'Courier',
                            'monospace',
                          ],
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
