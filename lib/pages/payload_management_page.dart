import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../database/database_helper.dart';
import '../models/payload.dart';
import '../models/webshell.dart';
import '../services/webshell_service.dart';
import '../theme/app_theme.dart';
import '../app/localization.dart';
import '../widgets/upload_success_dialog.dart';

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
const _binaryContentPrefix = '__MATRIX_BINARY_B64__:';

bool _isBinaryPayload(Payload payload) =>
    payload.content.startsWith(_binaryContentPrefix);

Uint8List? _decodeBinaryPayload(Payload payload) {
  if (!_isBinaryPayload(payload)) return null;
  try {
    final encoded = payload.content.substring(_binaryContentPrefix.length);
    return Uint8List.fromList(base64Decode(encoded));
  } catch (_) {
    return null;
  }
}

Uint8List? _payloadBytes(Payload payload) {
  if (payload.content.startsWith(_binaryContentPrefix)) {
    return _decodeBinaryPayload(payload);
  }
  return Uint8List.fromList(utf8.encode(payload.content));
}

String _safeRemoteBaseName(String name) {
  final n = name.trim().replaceAll('\\', '/');
  if (n.isEmpty) return 'payload.txt';
  final parts = n.split('/').where((s) => s.isNotEmpty).toList();
  return parts.isEmpty ? 'payload.txt' : parts.last;
}

bool _bytesLookBinary(List<int> bytes) {
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
      final ext = name.contains('.')
          ? name.split('.').last.toLowerCase()
          : 'txt';
      final type = ['php', 'jsp', 'asp'].contains(ext) ? ext : 'other';

      await _db.createPayload(name: name, type: type, content: content);
      if (!mounted) return;
      _showSnack(S.snackImported(name));
      await _load();
    } catch (e) {
      if (!mounted) return;
      _showSnack(S.snackImportFailed(e), error: true);
    }
  }

  Future<void> _downloadToFile(Payload payload) async {
    // 完全尊重 payload.name，不再自动补扩展名，让用户自行控制文件名
    final suggestedName = payload.name.isNotEmpty
        ? payload.name
        : 'payload_${payload.id}.txt';

    final location = await getSaveLocation(suggestedName: suggestedName);
    if (location == null) return;
    try {
      final binary = _decodeBinaryPayload(payload);
      if (binary != null) {
        await File(location.path).writeAsBytes(binary, flush: true);
      } else {
        await File(location.path).writeAsString(payload.content);
      }
      if (!mounted) return;
      _showSnack(S.snackSavedTo(location.path));
    } catch (e) {
      if (!mounted) return;
      _showSnack(S.snackSaveFailed(e), error: true);
    }
  }

  Future<void> _copyToClipboard(Payload payload) async {
    if (_isBinaryPayload(payload)) {
      if (!mounted) return;
      _showSnack(S.snackBinaryCopyUnsupported, error: true);
      return;
    }
    await Clipboard.setData(ClipboardData(text: payload.content));
    if (!mounted) return;
    _showSnack(S.snackCopied);
  }

  Future<void> _copyAsBase64(Payload payload) async {
    final binary = _decodeBinaryPayload(payload);
    final b64 = binary != null
        ? base64Encode(binary)
        : base64Encode(utf8.encode(payload.content));
    await Clipboard.setData(ClipboardData(text: b64));
    if (!mounted) return;
    _showSnack(S.snackCopiedBase64);
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

  Future<void> _uploadPayloadToWebshellTmp(Payload payload) async {
    final projects = await _db.getAllProjects();
    final entries = <_WebshellPickEntry>[];
    for (final p in projects) {
      final shells = await _db.getWebshellsByProject(p.id);
      for (final w in shells) {
        entries.add(_WebshellPickEntry(webshell: w, projectName: p.name));
      }
    }
    if (!mounted) return;
    if (entries.isEmpty) {
      await showUploadFailureDialog(context, S.snackNoWebshellsAnyProject);
      return;
    }

    final picked = await showDialog<Webshell>(
      context: context,
      builder: (_) => _WebshellPickerDialog(entries: entries),
    );
    if (picked == null || !mounted) return;

    final bytes = _payloadBytes(payload);
    if (bytes == null) {
      await showUploadFailureDialog(
        context,
        S.snackPayloadDecodeFailed(payload.name),
      );
      return;
    }

    final service = WebshellService(picked);
    if (!service.supportsFileWrite) {
      await showUploadFailureDialog(context, S.snackWriteNotSupported);
      return;
    }

    final remoteName = _safeRemoteBaseName(payload.name);
    final remotePath = '/tmp/$remoteName';

    await _uploadBytesToRemoteTmp(service, remoteName, remotePath, bytes);
  }

  Future<void> _uploadBytesToRemoteTmp(
    WebshellService service,
    String fileName,
    String remotePath,
    Uint8List bytes,
  ) async {
    var uploadCancelled = false;
    var ok = false;
    var usedBinaryPath = false;
    var progressShown = false;
    ValueNotifier<int>? transferred;

    try {
      final looksBinary = _bytesLookBinary(bytes);
      final useBinaryPath = looksBinary || bytes.length > 100 * 1024;
      if (!useBinaryPath) {
        final content = utf8.decode(bytes);
        ok = await service.writeFile(remotePath, content);
      } else {
        usedBinaryPath = true;
        final progress = ValueNotifier<int>(0);
        transferred = progress;
        if (!mounted) return;
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _PayloadUploadProgressDialog(
            fileName: fileName,
            fileSize: bytes.length,
            transferred: progress,
            onCancel: () {
              uploadCancelled = true;
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
          ),
        );
        progressShown = true;
        ok = await service.writeFileBinaryWithProgress(
          remotePath,
          bytes,
          (sent, _) {
            if (!mounted) return;
            if (uploadCancelled) {
              throw _PayloadUploadCancelled();
            }
            progress.value = sent;
          },
        );
      }
    } catch (e) {
      if (!mounted) {
        transferred?.dispose();
        return;
      }
      if (progressShown && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      transferred?.dispose();
      if (e is _PayloadUploadCancelled) {
        await showUploadCancelledDialog(context);
      } else {
        debugPrint(
          '[Matrix][payload_upload] error file=$fileName path=$remotePath '
          'size=${bytes.length} error=$e',
        );
        await showUploadFailureDialog(context, S.snackUploadFailed(e));
      }
      return;
    }

    if (!ok && !usedBinaryPath) {
      try {
        final content = utf8.decode(bytes);
        ok = await service.writeFile(remotePath, content);
      } catch (_) {}
    }

    if (!mounted) {
      transferred?.dispose();
      return;
    }
    if (progressShown && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    transferred?.dispose();

    if (ok) {
      await showUploadSuccessDialog(
        context,
        S.snackPayloadUploadedToRemote(remotePath),
      );
    } else {
      debugPrint(
        '[Matrix][payload_upload] failed file=$fileName path=$remotePath '
        'size=${bytes.length} usedBinaryPath=$usedBinaryPath',
      );
      await showUploadFailureDialog(context, S.snackUploadFail);
    }
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
        content: Text(
          msg,
          style: AppTextStyles.caption(
            color: error ? AppColors.red : AppColors.primary,
          ),
        ),
        backgroundColor: AppColors.bgElevated,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: (error ? AppColors.red : AppColors.primary).withValues(
              alpha: 0.4,
            ),
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
              const Icon(
                Icons.folder_outlined,
                size: 13,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 5),
              Text(
                S.payloadCount(_payloads.length),
                style: AppTextStyles.caption(
                  size: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        // 刷新
        _TbBtn(icon: Icons.refresh, tooltip: S.actionRefresh, onPressed: _load),
        const SizedBox(width: 6),
        // 导入
        FilledButton.icon(
          onPressed: _importFromFile,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.bgDark,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          icon: const Icon(Icons.file_upload_outlined, size: 15),
          label: Text(
            S.quickActionUpload,
            style: AppTextStyles.body(size: 13, color: AppColors.bgDark),
          ),
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
            Text(
              S.loading,
              style: AppTextStyles.caption(color: AppColors.textMuted),
            ),
          ],
        ),
      );
    }

    if (_payloads.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.terminal,
              size: 40,
              color: AppColors.primary.withValues(alpha: 0.25),
            ),
            const SizedBox(height: 12),
            Text(
              S.payloadNoneFound,
              style: AppTextStyles.body(color: AppColors.textMuted),
            ),
            const SizedBox(height: 4),
            Text(
              S.payloadImportHint,
              style: AppTextStyles.caption(
                color: AppColors.textMuted.withValues(alpha: 0.6),
              ),
            ),
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
        onUploadToWebshellTmp: () => _uploadPayloadToWebshellTmp(_payloads[i]),
      ),
    );
  }
}

// ── 工具栏小按钮 ─────────────────────────────────────────────────────────────

class _TbBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _TbBtn({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

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
  final VoidCallback onUploadToWebshellTmp;

  const _PayloadCard({
    required this.payload,
    required this.onTap,
    required this.onDelete,
    required this.onUploadToWebshellTmp,
  });

  @override
  State<_PayloadCard> createState() => _PayloadCardState();
}

class _PayloadCardState extends State<_PayloadCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = _colorOf(widget.payload.type);
    final icon = _iconOf(widget.payload.type);
    final isBinary = _isBinaryPayload(widget.payload);
    final lines = isBinary
        ? 0
        : '\n'.allMatches(widget.payload.content).length + 1;

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
                      top: Radius.circular(9),
                    ),
                  ),
                ),
              ),

              // 右上角：默认项显示锁图标，非默认项 hover 时显示删除按钮
              if (widget.payload.isDefault)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Tooltip(
                    message: S.payloadBuiltinTooltip,
                    child: Icon(
                      Icons.lock_outline,
                      size: 12,
                      color: AppColors.textMuted.withValues(alpha: 0.5),
                    ),
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
                          color: AppColors.red.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Icon(
                        Icons.close,
                        size: 11,
                        color: AppColors.red.withValues(alpha: 0.8),
                      ),
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
                          color: color.withValues(alpha: 0.28),
                        ),
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
                    // 类型标签 + 行数 + 上传到 /tmp
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _TypeBadge(type: widget.payload.type, color: color),
                        const SizedBox(width: 6),
                        Text(
                          isBinary ? 'BIN' : '$lines L',
                          style: AppTextStyles.caption(
                            size: 9,
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Tooltip(
                          message: S.tooltipPayloadUploadToWebshellTmp,
                          child: GestureDetector(
                            onTap: () => widget.onUploadToWebshellTmp(),
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: Icon(
                                Icons.cloud_upload_outlined,
                                size: 14,
                                color: color.withValues(alpha: 0.85),
                              ),
                            ),
                          ),
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
          Icon(
            Icons.warning_amber_outlined,
            size: 18,
            color: AppColors.red.withValues(alpha: 0.8),
          ),
          const SizedBox(width: 8),
          Text(
            S.titleDeletePayload,
            style: AppTextStyles.heading(size: 14, color: AppColors.red),
          ),
        ],
      ),
      content: Text(
        S.confirmDeletePayload(name),
        style: AppTextStyles.body(size: 13, color: AppColors.textSecondary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(
            S.btnCancel,
            style: AppTextStyles.body(color: AppColors.textSecondary),
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.red.withValues(alpha: 0.85),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          child: Text(
            S.btnDelete,
            style: AppTextStyles.body(color: AppColors.bgDark),
          ),
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
    final isBinary = _isBinaryPayload(widget.payload);
    final lines = isBinary
        ? const <String>[]
        : widget.payload.content.split('\n');
    final binary = _decodeBinaryPayload(widget.payload);

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
                  top: Radius.circular(13),
                ),
                border: const Border(
                  bottom: BorderSide(color: AppColors.border),
                ),
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
                    child: Icon(
                      _iconOf(widget.payload.type),
                      size: 16,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.payload.name,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body(
                        size: 13,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  // 行数统计
                  Text(
                    isBinary
                        ? '${binary?.length ?? 0} bytes'
                        : '${lines.length} lines',
                    style: AppTextStyles.caption(
                      size: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(width: 14),
                  // 操作按钮
                  if (!isBinary) ...[
                    _DialogBtn(
                      icon: Icons.copy_outlined,
                      label: S.actionCopy,
                      onPressed: widget.onCopy,
                    ),
                    const SizedBox(width: 6),
                  ],
                  _DialogBtn(
                    icon: Icons.code,
                    label: S.actionCopyBase64,
                    onPressed: widget.onCopyBase64,
                  ),
                  const SizedBox(width: 6),
                  _DialogBtn(
                    icon: Icons.download_outlined,
                    label: S.actionDownload,
                    onPressed: widget.onDownload,
                  ),
                  const SizedBox(width: 6),
                  if (!widget.payload.isDefault) ...[
                    _DialogBtn(
                      icon: Icons.delete_outline,
                      label: S.btnDelete,
                      color: AppColors.red,
                      onPressed: widget.onDelete,
                    ),
                    const SizedBox(width: 6),
                  ],
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    borderRadius: BorderRadius.circular(4),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.close,
                        size: 16,
                        color: AppColors.textSecondary,
                      ),
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
                            if (!isBinary) ...[
                              // 行号列
                              Container(
                                width: 48,
                                color: AppColors.bgElevated,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: List.generate(
                                    lines.length,
                                    (i) => SizedBox(
                                      height: 19,
                                      child: Text(
                                        '${i + 1}',
                                        style: AppTextStyles.caption(
                                          size: 11,
                                          color: AppColors.textMuted,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Container(width: 1, color: AppColors.border),
                              // 代码内容
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    left: 12,
                                    right: 12,
                                  ),
                                  child: SelectableText(
                                    widget.payload.content,
                                    style: AppTextStyles.terminal(
                                      size: 12.5,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                              ),
                            ] else
                              Expanded(
                                child: Center(
                                  child: Text(
                                    S.binaryPreviewDisabled,
                                    textAlign: TextAlign.center,
                                    style: AppTextStyles.body(
                                      size: 12,
                                      color: AppColors.textMuted,
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

  const _DialogBtn({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
  });

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

class _PayloadUploadCancelled implements Exception {}

class _WebshellPickEntry {
  final Webshell webshell;
  final String projectName;

  const _WebshellPickEntry({
    required this.webshell,
    required this.projectName,
  });
}

class _WebshellPickerDialog extends StatelessWidget {
  final List<_WebshellPickEntry> entries;

  const _WebshellPickerDialog({required this.entries});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: SizedBox(
        width: 520,
        height: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: const BoxDecoration(
                color: AppColors.bgElevated,
                borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.terminal,
                    color: AppColors.primary,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      S.titleSelectWebshellForPayload,
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
                itemCount: entries.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, color: AppColors.border),
                itemBuilder: (context, index) {
                  final e = entries[index];
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      Icons.link,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    title: Text(
                      e.webshell.name,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body(
                        size: 13,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      '${e.projectName} · ${e.webshell.url}',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                      style: AppTextStyles.caption(
                        size: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                    onTap: () => Navigator.pop(context, e.webshell),
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

class _PayloadUploadProgressDialog extends StatelessWidget {
  final String fileName;
  final int fileSize;
  final ValueNotifier<int> transferred;
  final VoidCallback onCancel;

  const _PayloadUploadProgressDialog({
    required this.fileName,
    required this.fileSize,
    required this.transferred,
    required this.onCancel,
  });

  static String _fmtSize(int bytes) {
    if (bytes <= 0) return '—';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

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
              final double? progress =
                  fileSize > 0 ? (sent / fileSize).clamp(0.0, 1.0) : null;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.upload_file,
                        color: AppColors.primary,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        S.uploading,
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
                        '${((progress ?? 0) * 100).round()}%',
                        style: AppTextStyles.caption(
                          color: AppColors.primary,
                          size: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
