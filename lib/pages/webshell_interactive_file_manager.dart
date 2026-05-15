import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/crypto/payload_obfuscator.dart';
import '../database/database_helper.dart';
import '../models/payload.dart';
import '../services/webshell_service.dart';
import '../theme/app_theme.dart';
import '../app/localization.dart';
import '../widgets/upload_success_dialog.dart';

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
  final DatabaseHelper _db = DatabaseHelper();
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
    if (widget.service.isWindowsTarget) {
      _currentPath = r'C:\';
    }
    _initPath();
  }

  Future<void> _initPath() async {
    final dir = await widget.service.getInitialWorkingDirectory();
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
      if (files.isEmpty) _errorMsg = S.dirEmptyOrDenied;
      widget.service.currentDir = path;
    });
  }

  String _parent(String path) {
    if (_isWindowsPath(path)) {
      final p = path.replaceAll('/', r'\').trim();

      // UNC: \\server\share\dir\sub
      if (p.startsWith(r'\\')) {
        final parts = p.split(r'\').where((s) => s.isNotEmpty).toList();
        if (parts.length <= 2) {
          // 已到 UNC 根：\\server\share
          return parts.length == 2 ? '\\\\${parts[0]}\\${parts[1]}' : path;
        }
        parts.removeLast();
        return '\\\\${parts.join('\\')}';
      }

      // Drive: C:\dir\sub
      final drive = RegExp(r'^[a-zA-Z]:').stringMatch(p);
      if (drive != null) {
        var rest = p
            .substring(drive.length)
            .replaceFirst(RegExp(r'^[\\]+'), '');
        if (rest.isEmpty) return '$drive\\';
        final parts = rest.split(r'\').where((s) => s.isNotEmpty).toList();
        if (parts.isEmpty) return '$drive\\';
        parts.removeLast();
        if (parts.isEmpty) return '$drive\\';
        return '$drive\\${parts.join(r'\')}';
      }

      return path;
    }

    final norm = path.replaceAll('\\', '/');
    final parts = norm.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return '/';
    parts.removeLast();
    if (parts.isEmpty) return '/';
    return '/${parts.join('/')}';
  }

  String _join(String dir, String name) {
    if (name == '..') return _parent(dir);
    if (_isWindowsPath(dir)) {
      var base = dir.replaceAll('/', r'\').trim();
      if (base.endsWith(r'\')) {
        base = base.substring(0, base.length - 1);
      }
      if (RegExp(r'^[a-zA-Z]:$').hasMatch(base)) {
        return '$base\\$name';
      }
      return '$base\\$name';
    }
    final norm = dir.replaceAll('\\', '/').trimRight();
    return norm.endsWith('/') ? '$norm$name' : '$norm/$name';
  }

  bool _isWindowsPath(String path) =>
      RegExp(r'^[a-zA-Z]:[\\/]|^[a-zA-Z]:$|^\\\\').hasMatch(path.trim());

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
      await showUploadFailureDialog(context, S.snackWriteNotSupported);
      return;
    }
    final file = await openFile(
      acceptedTypeGroups: [XTypeGroup(label: S.allFiles)],
    );
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    await _uploadBytes(file.name, bytes);
  }

  Future<void> _uploadPayloadFile() async {
    if (!widget.service.supportsFileWrite) {
      await showUploadFailureDialog(context, S.snackWriteNotSupported);
      return;
    }

    final payloads = await _db.getAllPayloads();
    if (!mounted) return;
    if (payloads.isEmpty) {
      await showUploadFailureDialog(context, S.snackNoPayloads);
      return;
    }

    final selected = await showDialog<Payload>(
      context: context,
      builder: (_) => _PayloadPickerDialog(payloads: payloads),
    );
    if (selected == null || !mounted) return;

    var bytes = _payloadBytes(selected);
    if (bytes == null) {
      await showUploadFailureDialog(
        context,
        S.snackPayloadDecodeFailed(selected.name),
      );
      return;
    }

    final type = PayloadObfuscator.typeFromFileName(selected.name);
    final obfuscated = PayloadObfuscator.obfuscateBytes(bytes, type);
    if (obfuscated != null) bytes = obfuscated;

    await _uploadBytes(selected.name, bytes);
  }

  Uint8List? _payloadBytes(Payload payload) {
    const binaryPrefix = '__MATRIX_BINARY_B64__:';
    if (payload.content.startsWith(binaryPrefix)) {
      try {
        return base64Decode(payload.content.substring(binaryPrefix.length));
      } catch (_) {
        return null;
      }
    }
    return Uint8List.fromList(utf8.encode(payload.content));
  }

  Future<void> _uploadBytes(String fileName, Uint8List bytes) async {
    if (!mounted) return;
    final remotePath = _join(_currentPath, fileName);
    final transferred = ValueNotifier<int>(0);
    _uploadCancelled = false;
    bool ok = false;
    bool usedBinaryPath = false;
    bool progressShown = false;
    NavigatorState? uploadProgressNav;
    try {
      // Windows 目标（ASP/ASPX）强制走二进制分块上传，避免 cmd 单条命令长度限制。
      // 其他目标：文本小文件走文本写入；大文件或二进制走分块上传。
      final looksBinary = _isBinary(bytes);
      final useBinaryPath =
          widget.service.isWindowsTarget ||
          looksBinary ||
          bytes.length > 100 * 1024;
      if (!useBinaryPath) {
        setState(() => _uploading = true);
        final content = utf8.decode(bytes);
        ok = await widget.service.writeFile(remotePath, content);
      } else {
        usedBinaryPath = true; // 二进制文件或大文件（>100KB）走分块
        setState(() => _uploading = true);
        final nav = Navigator.of(context, rootNavigator: true);
        uploadProgressNav = nav;
        showDialog<void>(
          context: context,
          useRootNavigator: true,
          barrierDismissible: false,
          builder: (_) => _TransferProgressDialog(
            fileName: fileName,
            fileSize: bytes.length,
            transferred: transferred,
            isUpload: true,
            onCancel: () {
              _uploadCancelled = true;
              if (nav.mounted) nav.pop();
            },
          ),
        );
        progressShown = true;
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
      if (progressShown &&
          uploadProgressNav != null &&
          uploadProgressNav.mounted) {
        uploadProgressNav.pop();
      }
      if (!mounted) {
        transferred.dispose();
        return;
      }
      // 不再主动关闭当前页面，仅结束上传状态和进度
      setState(() => _uploading = false);
      transferred.dispose();
      if (e is _TransferCancelled) {
        await showUploadCancelledDialog(context);
      } else {
        debugPrint(
          '[Matrix][upload] error file=$fileName path=$remotePath size=${bytes.length} error=$e',
        );
        await showUploadFailureDialog(context, S.snackUploadFailed(e));
      }
      return;
    }
    // 若文本路径失败且文件看起来是文本，尝试回退到二进制写入（更稳，避免命令长度限制）。
    if (!ok && !usedBinaryPath) {
      try {
        ok = await widget.service.writeFileBinary(remotePath, bytes);
      } catch (_) {
        // ignore, 保持原有失败提示
      }
    }

    if (!mounted) {
      if (progressShown &&
          uploadProgressNav != null &&
          uploadProgressNav.mounted) {
        uploadProgressNav.pop();
      }
      transferred.dispose();
      return;
    }
    setState(() => _uploading = false);
    if (progressShown &&
        uploadProgressNav != null &&
        uploadProgressNav.mounted) {
      uploadProgressNav.pop();
    }
    transferred.dispose();
    if (ok) {
      await showUploadSuccessDialog(context, S.snackUploaded(fileName));
      _loadDirectory(_currentPath);
      widget.onInvalidateCompleterDir(_parent(remotePath));
    } else {
      debugPrint(
        '[Matrix][upload] failed file=$fileName path=$remotePath size=${bytes.length} '
        'usedBinaryPath=$usedBinaryPath',
      );
      await showUploadFailureDialog(context, S.snackUploadFail);
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
      final dir = await getDirectoryPath(
        confirmButtonText: S.selectDownloadDir,
      );
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
    final rootNav = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => _TransferProgressDialog(
        fileName: entry.name,
        fileSize: entry.size,
        transferred: transferred,
        isUpload: false,
        onCancel: () {
          _downloadCancelled = true;
          if (rootNav.mounted) rootNav.pop();
        },
      ),
    );
    var progressPopped = false;
    void popProgress() {
      if (!progressPopped && rootNav.mounted) {
        progressPopped = true;
        rootNav.pop();
      }
    }

    try {
      var bytes = await widget.service.readFileBinary(remotePath);
      if (!mounted) {
        popProgress();
        transferred.dispose();
        return;
      }
      if (_downloadCancelled) {
        setState(() => _downloading = false);
        popProgress();
        transferred.dispose();
        return;
      }
      // Dismiss the progress indicator before potentially showing another dialog.
      popProgress();

      List<int> saveBytes = bytes;
      if (!_isBinary(bytes)) {
        try {
          final text = utf8.decode(bytes);
          final deobfuscated = PayloadObfuscator.tryDeobfuscate(text);
          if (deobfuscated != null && mounted) {
            final choice = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                title: Text(
                  S.obfuscatedFileDialogTitle,
                  style: const TextStyle(color: AppColors.primary),
                ),
                content: Text(
                  S.obfuscatedFileDialogMsg,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(
                      S.btnSaveAsIs,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.bgDark,
                    ),
                    child: Text(S.btnSaveDeobfuscated),
                  ),
                ],
              ),
            );
            if (choice == true) saveBytes = utf8.encode(deobfuscated);
          }
        } catch (_) {}
      }
      if (!mounted) {
        transferred.dispose();
        return;
      }
      await File(localPath).writeAsBytes(saveBytes, flush: true);
      if (!mounted) {
        transferred.dispose();
        return;
      }
      setState(() => _downloading = false);
      transferred.dispose();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            S.snackDownloadedTo(localPath),
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: const Color(0xFF064D2E),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) {
        popProgress();
        transferred.dispose();
        return;
      }
      popProgress();
      setState(() => _downloading = false);
      transferred.dispose();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            S.snackDownloadFailed(e),
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: AppColors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _detectWritableDirs() async {
    setState(() => _loading = true);
    final dirs = await widget.service.detectWritableDirs();
    if (!mounted) return;
    setState(() => _loading = false);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.manage_search, color: AppColors.amber, size: 18),
            const SizedBox(width: 8),
            const Text('可写目录', style: TextStyle(color: AppColors.textPrimary)),
          ],
        ),
        content: dirs.isEmpty
            ? const Text(
                '未检测到可写目录',
                style: TextStyle(color: AppColors.textSecondary),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '找到 ${dirs.length} 个可写目录，点击跳转：',
                    style: AppTextStyles.caption(
                      color: AppColors.textMuted,
                      size: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...dirs.map(
                    (d) => InkWell(
                      onTap: () {
                        Navigator.pop(ctx);
                        _loadDirectory(d);
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 6,
                          horizontal: 4,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.folder_open,
                              color: AppColors.primary,
                              size: 14,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                d,
                                style: AppTextStyles.terminal(
                                  color: AppColors.primary,
                                  size: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.btnClose),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteFile(FileEntry entry) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          S.titleConfirmDelete,
          style: const TextStyle(color: AppColors.red),
        ),
        content: Text(
          S.confirmDeleteFile(entry.name),
          style: const TextStyle(color: AppColors.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              S.btnCancel,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            child: Text(
              S.tooltipDelete,
              style: const TextStyle(color: Colors.white),
            ),
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
          ok ? S.snackDeleted(entry.name) : S.snackDeleteFailed,
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: ok ? const Color(0xFF064D2E) : AppColors.red,
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
                tooltip: S.tooltipParentDir,
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
                  onPressed: _loading || _uploading || _downloading
                      ? null
                      : _uploadFile,
                  icon: const Icon(Icons.upload_file, size: 16),
                  color: AppColors.primary,
                  tooltip: S.tooltipUploadFile,
                ),
              if (widget.service.supportsFileWrite)
                IconButton(
                  onPressed: _loading || _uploading || _downloading
                      ? null
                      : _uploadPayloadFile,
                  icon: const Icon(Icons.inventory_2_outlined, size: 16),
                  color: AppColors.cyan,
                  tooltip: S.quickActionUpload,
                ),
              if (widget.service.isWindowsTarget)
                IconButton(
                  onPressed: _loading ? null : _detectWritableDirs,
                  icon: const Icon(Icons.manage_search, size: 16),
                  color: AppColors.amber,
                  tooltip: '检测可写目录',
                ),
              IconButton(
                onPressed: _loading ? null : () => _loadDirectory(_currentPath),
                icon: const Icon(Icons.refresh, size: 16),
                color: AppColors.textSecondary,
                tooltip: S.actionRefresh,
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
                  _colHeader(S.colName, flex: 5),
                  if (w > 480) _colHeader(S.colSize, width: 80),
                  if (w > 560) _colHeader(S.colPermissions, width: 60),
                  if (w > 640) _colHeader(S.colModified, width: 130),
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
                    _errorMsg ?? S.dirEmpty,
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
                      onDownload:
                          f.isDirectory || f.name == '..' || _downloading
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
                          S.tooltipView,
                          onView!,
                        ),
                      if (onEdit != null)
                        _iconBtn(
                          Icons.edit_outlined,
                          AppColors.primary,
                          S.tooltipEdit,
                          onEdit!,
                        ),
                      if (onDownload != null)
                        _iconBtn(
                          Icons.download_outlined,
                          AppColors.primaryDim,
                          S.tooltipDownload,
                          onDownload!,
                        ),
                      if (onDelete != null)
                        _iconBtn(
                          Icons.delete_outline,
                          AppColors.red,
                          S.tooltipDelete,
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

class _PayloadPickerDialog extends StatelessWidget {
  final List<Payload> payloads;

  const _PayloadPickerDialog({required this.payloads});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: MatrixDialogStyle.outlinePrimary(0.25),
      child: SizedBox(
        width: 520,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: const BoxDecoration(
                color: AppColors.bgElevated,
                borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.inventory_2_outlined,
                    color: AppColors.primary,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      S.titleSelectPayload,
                      style: AppTextStyles.heading(
                        size: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                    tooltip: S.tooltipClose,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: payloads.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, color: AppColors.border),
                itemBuilder: (context, index) {
                  final payload = payloads[index];
                  final isBinary = payload.content.startsWith(
                    '__MATRIX_BINARY_B64__:',
                  );
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      isBinary
                          ? Icons.memory_outlined
                          : Icons.insert_drive_file_outlined,
                      color: isBinary ? AppColors.amber : AppColors.primary,
                      size: 20,
                    ),
                    title: Text(
                      payload.name,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body(
                        size: 13,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      '${payload.type.toUpperCase()}'
                      '${payload.isDefault ? ' · ${S.payloadBuiltin}' : ''}'
                      '${isBinary ? ' · Binary' : ''}',
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption(
                        size: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                    onTap: () => Navigator.pop(context, payload),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
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
                        isUpload ? S.uploading : S.downloading,
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
                            horizontal: 8,
                            vertical: 4,
                          ),
                          minimumSize: const Size(0, 0),
                        ),
                        child: Text(
                          S.btnCancel,
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
                    style: AppTextStyles.terminal(
                      size: 12,
                      color: AppColors.cyan,
                    ),
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
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.primary,
                      ),
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
                            color: AppColors.textSecondary,
                            size: 11,
                          ),
                        ),
                        Text(
                          '${(progress * 100).round()}%',
                          style: AppTextStyles.caption(
                            color: AppColors.primary,
                            size: 11,
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      isUpload ? S.uploadingProgress : S.downloadingProgress,
                      style: AppTextStyles.caption(
                        color: AppColors.textSecondary,
                        size: 11,
                      ),
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
  String? _deobfuscated;
  bool _loading = true;
  bool _showDeobfuscated = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final content = await widget.service.readFile(widget.path);
    if (mounted) {
      final deob = PayloadObfuscator.tryDeobfuscate(content);
      setState(() {
        _content = content;
        _deobfuscated = deob;
        _showDeobfuscated = deob != null;
        _loading = false;
      });
    }
  }

  String get _displayContent => (_showDeobfuscated && _deobfuscated != null)
      ? _deobfuscated!
      : (_content ?? '');

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 700,
        height: 520,
        child: Column(
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: const BoxDecoration(
                color: AppColors.bgElevated,
                borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
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
                  // Deobfuscate toggle (only shown when content is obfuscated)
                  if (!_loading && _deobfuscated != null)
                    IconButton(
                      onPressed: () => setState(
                        () => _showDeobfuscated = !_showDeobfuscated,
                      ),
                      icon: Icon(
                        _showDeobfuscated
                            ? Icons.lock_open_outlined
                            : Icons.lock_outline,
                        size: 16,
                      ),
                      color: _showDeobfuscated
                          ? AppColors.primary
                          : AppColors.amber,
                      tooltip: _showDeobfuscated
                          ? S.tooltipShowObfuscated
                          : S.tooltipDeobfuscate,
                    ),
                  if (!_loading && _content != null)
                    IconButton(
                      onPressed: () => Clipboard.setData(
                        ClipboardData(text: _displayContent),
                      ),
                      icon: const Icon(
                        Icons.copy_outlined,
                        size: 16,
                        color: AppColors.textSecondary,
                      ),
                      tooltip: S.tooltipCopyContent,
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
                  : Directionality(
                      textDirection: TextDirection.ltr,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: SizedBox(
                          width: double.infinity,
                          child: SelectableText(
                            _displayContent,
                            textDirection: TextDirection.ltr,
                            textAlign: TextAlign.left,
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
        SnackBar(
          content: Text(S.snackSaveSuccess),
          backgroundColor: AppColors.bgCard,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.snackSaveFailure),
          backgroundColor: AppColors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 700,
        height: 560,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: const BoxDecoration(
                color: AppColors.bgElevated,
                borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
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
                    child: Text(
                      S.btnCancel,
                      style: const TextStyle(color: AppColors.textSecondary),
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
                    label: Text(S.btnSave),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.bgDark,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: TextField(
                  controller: _controller,
                  maxLines: null,
                  expands: true,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.left,
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
            ),
          ],
        ),
      ),
    );
  }
}
