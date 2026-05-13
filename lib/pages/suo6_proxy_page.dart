import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/localization.dart';
import '../database/database_helper.dart';
import '../models/project.dart';
import '../models/suo6_profile.dart';
import '../services/suo6_client_service.dart';
import '../theme/app_theme.dart';

class Suo6ProxyPage extends StatefulWidget {
  static final _refreshBus = StreamController<void>.broadcast();
  static void notifyRefresh() => _refreshBus.add(null);

  final Project project;
  final VoidCallback onSwitchProject;

  const Suo6ProxyPage({
    super.key,
    required this.project,
    required this.onSwitchProject,
  });

  @override
  State<Suo6ProxyPage> createState() => _Suo6ProxyPageState();
}

class _Suo6ProxyPageState extends State<Suo6ProxyPage> {
  final DatabaseHelper _db = DatabaseHelper();
  final Suo6ClientService _service = Suo6ClientService();
  final ScrollController _logScroll = ScrollController();
  StreamSubscription<void>? _refreshSub;

  List<Suo6Profile> _profiles = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _service.onChanged = () {
      if (!mounted) return;
      setState(() {});
      _scrollLogsToBottom();
    };
    _refreshSub = Suo6ProxyPage._refreshBus.stream.listen((_) {
      if (mounted) _loadProfiles();
    });
    _loadProfiles();
  }

  @override
  void didUpdateWidget(covariant Suo6ProxyPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.project.id != widget.project.id) {
      _loadProfiles();
    }
  }

  @override
  void dispose() {
    _refreshSub?.cancel();
    _service.onChanged = null;
    _logScroll.dispose();
    super.dispose();
  }

  Future<void> _loadProfiles() async {
    setState(() => _loading = true);
    final list = await _db.getSuo6ProfilesByProject(widget.project.id);
    if (!mounted) return;
    setState(() {
      _profiles = list;
      _loading = false;
    });
  }

  String _deriveNameFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.host.isNotEmpty) return uri.host;
      return url;
    } catch (_) {
      return url;
    }
  }

  Future<void> _startOrStopProfile(Suo6Profile p) async {
    if (_service.isRunning(p.id)) {
      await _service.stopProfile(p.id);
      return;
    }
    final conflict = _profiles.where(
      (other) =>
          other.id != p.id &&
          other.listenHost == p.listenHost &&
          other.listenPort == p.listenPort,
    );
    if (conflict.isNotEmpty) {
      if (!mounted) return;
      final occupiedBy = conflict.first.name;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '端口冲突: ${p.listenHost}:${p.listenPort} 已被配置 "$occupiedBy" 占用',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }
    if (p.targetUrl.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.suo6MissingUrl),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    await _service.startProfile(p.id, p.toConfig(), label: p.name);
  }

  Future<void> _showCreateDialog() async {
    final urlController = TextEditingController();
    final nameController = TextEditingController();
    final hostController = TextEditingController(text: '127.0.0.1');
    final portController = TextEditingController(text: _suggestPort());

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => _Suo6EditorDialog(
        title: S.suo6NewConfigTitle,
        urlController: urlController,
        nameController: nameController,
        hostController: hostController,
        portController: portController,
        locked: false,
        submitLabel: S.btnAdd,
      ),
    );
    if (result != true) return;
    final url = urlController.text.trim();
    if (url.isEmpty) return;
    final port = int.tryParse(portController.text.trim()) ?? 0;
    final host = hostController.text.trim().isEmpty
        ? '127.0.0.1'
        : hostController.text.trim();
    if (port < 1 || port > 65535) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.suo6InvalidPort)),
      );
      return;
    }
    if (_hasPortConflict(editingId: null, host: host, port: port)) {
      final occupiedBy = _profiles
          .firstWhere((p) => p.listenHost == host && p.listenPort == port)
          .name;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('端口冲突: $host:$port 已被配置 "$occupiedBy" 占用'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.suo6InvalidUrl)),
      );
      return;
    }
    final name = nameController.text.trim().isEmpty
        ? _deriveNameFromUrl(url)
        : nameController.text.trim();
    await _db.createSuo6Profile(
      projectId: widget.project.id,
      name: name,
      targetUrl: url,
      listenHost: host,
      listenPort: port,
    );
    await _loadProfiles();
  }

  String _suggestPort() {
    final used = _profiles.map((p) => p.listenPort).toSet();
    for (var port = 1081; port <= 1099; port++) {
      if (!used.contains(port)) return port.toString();
    }
    return '1081';
  }

  bool _hasPortConflict({
    required int? editingId,
    required String host,
    required int port,
  }) {
    return _profiles.any(
      (p) => p.id != editingId && p.listenHost == host && p.listenPort == port,
    );
  }

  Future<void> _showEditDialog(Suo6Profile p) async {
    final urlController = TextEditingController(text: p.targetUrl);
    final nameController = TextEditingController(text: p.name);
    final hostController = TextEditingController(text: p.listenHost);
    final portController = TextEditingController(text: p.listenPort.toString());
    final locked = _service.isRunning(p.id);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => _Suo6EditorDialog(
        title: S.suo6EditConfigTitle,
        urlController: urlController,
        nameController: nameController,
        hostController: hostController,
        portController: portController,
        locked: locked,
        submitLabel: S.btnSave,
      ),
    );
    if (result != true) return;
    final url = urlController.text.trim();
    if (url.isEmpty) return;
    final port = int.tryParse(portController.text.trim()) ?? 0;
    final host = hostController.text.trim().isEmpty
        ? '127.0.0.1'
        : hostController.text.trim();
    if (port < 1 || port > 65535) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.suo6InvalidPort)),
      );
      return;
    }
    if (_hasPortConflict(editingId: p.id, host: host, port: port)) {
      final occupiedBy = _profiles
          .firstWhere(
            (other) =>
                other.id != p.id &&
                other.listenHost == host &&
                other.listenPort == port,
          )
          .name;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('端口冲突: $host:$port 已被配置 "$occupiedBy" 占用'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.suo6InvalidUrl)),
      );
      return;
    }
    final name = nameController.text.trim().isEmpty
        ? _deriveNameFromUrl(url)
        : nameController.text.trim();
    await _db.updateSuo6Profile(p.copyWith(
      name: name,
      targetUrl: url,
      listenHost: host,
      listenPort: port,
    ));
    _service.sessionFor(p.id)?.label = name;
    await _loadProfiles();
  }

  Future<void> _confirmDelete(Suo6Profile p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: Text(
          S.btnDelete,
          style: const TextStyle(color: AppColors.red),
        ),
        content: Text(
          S.confirmDeleteSuo6(p.name),
          style: const TextStyle(color: AppColors.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              S.btnCancel,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            child: Text(
              S.btnDelete,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _service.removeProfile(p.id);
    await _db.deleteSuo6Profile(p.id);
    await _loadProfiles();
  }

  void _scrollLogsToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_logScroll.hasClients) return;
      _logScroll.animateTo(
        _logScroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  String _fmtBytes(int b) {
    if (b < 1024) return '${b}B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)}KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildProjectHeader(),
        const SizedBox(height: 16),
        _buildToolbar(),
        const SizedBox(height: 16),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final useHorizontal = constraints.maxWidth >= 720;
              if (useHorizontal) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _buildProfileList()),
                    const SizedBox(width: 16),
                    Expanded(child: _buildLogSection()),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _buildProfileList()),
                  const SizedBox(height: 16),
                  Expanded(child: _buildLogSection()),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildProjectHeader() {
    final running = _service.runningCount;
    final connecting = _service.sessions.values
        .where((s) => s.status == Suo6Status.connecting)
        .length;
    final total = _profiles.length;
    final hasActive = running + connecting > 0;
    final accent = hasActive ? AppColors.primary : AppColors.textMuted;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: accent.withValues(alpha: 0.5)),
            ),
            child: Icon(Icons.cable, color: accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  S.suo6ManagementTitle(widget.project.name),
                  style: AppTextStyles.heading(
                    size: 15,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  S.suo6HeaderRunningSummary(running, total),
                  style: AppTextStyles.caption(size: 13, color: accent),
                ),
                if (hasActive) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      Text(
                        '${S.suo6StatActiveConn}: ${_service.totalActiveConn}',
                        style: AppTextStyles.caption(
                          size: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                      Text(
                        '${S.suo6StatUpload}: ${_fmtBytes(_service.totalUpload)}',
                        style: AppTextStyles.caption(
                          size: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                      Text(
                        '${S.suo6StatDownload}: ${_fmtBytes(_service.totalDownload)}',
                        style: AppTextStyles.caption(
                          size: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          TextButton.icon(
            onPressed: widget.onSwitchProject,
            icon: const Icon(
              Icons.swap_horiz,
              size: 16,
              color: AppColors.textSecondary,
            ),
            label: Text(
              S.btnSwitchProject,
              style: AppTextStyles.caption(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Row(
      children: [
        FilledButton.icon(
          onPressed: _loading ? null : _showCreateDialog,
          icon: const Icon(Icons.add, size: 18),
          label: Text(S.actionAddSuo6),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.bgDark,
          ),
        ),
        const SizedBox(width: 12),
        IconButton(
          onPressed: _loading ? null : _loadProfiles,
          icon: const Icon(Icons.refresh),
          color: AppColors.textSecondary,
          tooltip: S.actionRefresh,
        ),
        const Spacer(),
        if (!_loading)
          Text(
            S.suo6Count(_profiles.length),
            style: AppTextStyles.caption(color: AppColors.textMuted),
          ),
      ],
    );
  }

  Widget _buildProfileList() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (_profiles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cable_outlined,
              size: 64,
              color: AppColors.textSecondary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              S.suo6EmptyHint(S.actionAddSuo6),
              style: AppTextStyles.body(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      itemCount: _profiles.length,
      itemBuilder: (context, index) {
        final p = _profiles[index];
        final session = _service.sessionFor(p.id);
        return _Suo6Card(
          profile: p,
          session: session,
          fmtBytes: _fmtBytes,
          onStartStop: () => _startOrStopProfile(p),
          onEdit: () => _showEditDialog(p),
          onDelete: () => _confirmDelete(p),
        );
      },
    );
  }

  Widget _buildLogSection() {
    final lines = _service.aggregatedLogs;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.bgCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.terminal, size: 14, color: AppColors.textMuted),
              const SizedBox(width: 6),
              Text(
                S.suo6RunLog,
                style: AppTextStyles.caption(
                  size: 12,
                  color: AppColors.textMuted,
                ),
              ),
              const Spacer(),
              if (lines.isNotEmpty) ...[
                GestureDetector(
                  onTap: () async {
                    final text = lines.join('\n');
                    await Clipboard.setData(ClipboardData(text: text));
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(S.suo6LogCopiedSnack),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  child: Text(
                    S.actionCopy,
                    style: AppTextStyles.caption(
                      size: 11,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () {
                    _service.clearAllLogs();
                    setState(() {});
                  },
                  child: Text(
                    S.btnClear,
                    style: AppTextStyles.caption(
                      size: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: lines.isEmpty
                ? Center(
                    child: Text(
                      S.suo6NoLogs,
                      style: AppTextStyles.terminal(
                        size: 13,
                        color: AppColors.textMuted,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _logScroll,
                    itemCount: lines.length,
                    itemBuilder: (context, i) {
                      final line = lines[i];
                      final isError = line.contains('失败') ||
                          line.contains('异常') ||
                          line.contains('错误') ||
                          line.contains('error') ||
                          line.contains('Error');
                      final isOk = line.contains('成功') ||
                          line.contains('建立') ||
                          line.contains('success') ||
                          line.contains('listening');
                      final color = isError
                          ? AppColors.red
                          : isOk
                              ? AppColors.primary
                              : AppColors.textSecondary;
                      return Text(
                        line,
                        style: AppTextStyles.terminal(size: 12, color: color),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── Card ────────────────────────────────────────────────────────────────────

class _Suo6Card extends StatefulWidget {
  final Suo6Profile profile;
  final Suo6Session? session;
  final String Function(int bytes) fmtBytes;
  final VoidCallback onStartStop;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _Suo6Card({
    required this.profile,
    required this.session,
    required this.fmtBytes,
    required this.onStartStop,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_Suo6Card> createState() => _Suo6CardState();
}

class _Suo6CardState extends State<_Suo6Card> {
  bool _hovered = false;

  Suo6Status get _status => widget.session?.status ?? Suo6Status.idle;

  bool get _running =>
      _status == Suo6Status.running || _status == Suo6Status.connecting;

  Color get _statusColor {
    switch (_status) {
      case Suo6Status.running:
        return AppColors.primary;
      case Suo6Status.connecting:
        return Colors.orange;
      case Suo6Status.error:
        return AppColors.red;
      case Suo6Status.idle:
        return AppColors.textMuted;
    }
  }

  String get _statusLabel {
    switch (_status) {
      case Suo6Status.running:
        return S.suo6StatusRunning;
      case Suo6Status.connecting:
        return S.suo6StatusConnecting;
      case Suo6Status.error:
        return S.suo6StatusError;
      case Suo6Status.idle:
        return S.suo6StatusIdle;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final s = widget.session;
    final running = _running;
    final connecting = _status == Suo6Status.connecting;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _hovered ? AppColors.bgElevated : AppColors.bgCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: running
                ? _statusColor.withValues(alpha: 0.55)
                : _hovered
                    ? AppColors.primary.withValues(alpha: 0.35)
                    : AppColors.border,
            width: running || _hovered ? 1.2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: _statusColor.withValues(
                alpha: running ? 0.18 : (_hovered ? 0.12 : 0.0),
              ),
              blurRadius: 14,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _statusColor,
                    shape: BoxShape.circle,
                    boxShadow: running
                        ? [
                            BoxShadow(
                              color: _statusColor.withValues(alpha: 0.5),
                              blurRadius: 6,
                            ),
                          ]
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Icon(
                    Icons.cable,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              p.name,
                              style: AppTextStyles.body(
                                size: 14,
                                color: AppColors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _Tag(
                            label: '${p.listenHost}:${p.listenPort}',
                            color: AppColors.cyan,
                          ),
                          if (s != null && running) ...[
                            const SizedBox(width: 6),
                            _Tag(
                              label: _statusLabel,
                              color: _statusColor,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              p.targetUrl,
                              style: AppTextStyles.caption(
                                size: 12,
                                color: AppColors.primary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: () {
                              Clipboard.setData(
                                ClipboardData(text: p.targetUrl),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(S.snackCopied),
                                  backgroundColor: AppColors.bgCard,
                                  behavior: SnackBarBehavior.floating,
                                  duration: const Duration(seconds: 1),
                                ),
                              );
                            },
                            child: const Icon(
                              Icons.copy_outlined,
                              size: 14,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                      if (s != null && running) ...[
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 12,
                          runSpacing: 2,
                          children: [
                            Text(
                              '${S.suo6StatActiveConn}: ${s.activeConnections}',
                              style: AppTextStyles.caption(
                                size: 11,
                                color: AppColors.textMuted,
                              ),
                            ),
                            Text(
                              '${S.suo6StatUpload}: ${widget.fmtBytes(s.uploadBytes)}',
                              style: AppTextStyles.caption(
                                size: 11,
                                color: AppColors.textMuted,
                              ),
                            ),
                            Text(
                              '${S.suo6StatDownload}: ${widget.fmtBytes(s.downloadBytes)}',
                              style: AppTextStyles.caption(
                                size: 11,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: connecting ? null : widget.onStartStop,
                  icon: Icon(
                    running ? Icons.stop : Icons.play_arrow,
                    size: 16,
                    color: running ? AppColors.red : AppColors.primary,
                  ),
                  label: Text(
                    running ? S.btnStop : S.btnStart,
                    style: AppTextStyles.caption(
                      size: 12,
                      color: running ? AppColors.red : AppColors.primary,
                    ),
                  ),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: widget.onEdit,
                  icon: const Icon(
                    Icons.edit_outlined,
                    size: 16,
                    color: AppColors.cyan,
                  ),
                  label: Text(
                    S.btnEdit,
                    style: AppTextStyles.caption(
                      size: 12,
                      color: AppColors.cyan,
                    ),
                  ),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: running ? null : widget.onDelete,
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 16,
                    color: AppColors.red,
                  ),
                  label: Text(
                    S.btnDelete,
                    style: AppTextStyles.caption(
                      size: 12,
                      color: AppColors.red,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color color;

  const _Tag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(label, style: AppTextStyles.caption(size: 11, color: color)),
    );
  }
}

// ─── 创建/编辑弹窗 ────────────────────────────────────────────────────────────

class _Suo6EditorDialog extends StatelessWidget {
  final String title;
  final String submitLabel;
  final TextEditingController urlController;
  final TextEditingController nameController;
  final TextEditingController hostController;
  final TextEditingController portController;
  final bool locked;

  const _Suo6EditorDialog({
    required this.title,
    required this.submitLabel,
    required this.urlController,
    required this.nameController,
    required this.hostController,
    required this.portController,
    required this.locked,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.bgCard,
      title: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: AppTextStyles.heading(color: AppColors.primary),
            ),
          ),
          if (locked)
            Text(
              S.suo6RunningNoEdit,
              style: AppTextStyles.caption(
                size: 10,
                color: Colors.orange,
              ),
            ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _field(
                controller: urlController,
                label: S.suo6TargetUrl,
                hint: S.suo6TargetUrlHint,
                autofocus: true,
                enabled: !locked,
              ),
              const SizedBox(height: 16),
              _field(
                controller: nameController,
                label: S.suo6ConfigName,
                hint: S.suo6ConfigNameHint,
                enabled: !locked,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: _field(
                      controller: hostController,
                      label: S.suo6ListenHost,
                      hint: '127.0.0.1',
                      enabled: !locked,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _field(
                      controller: portController,
                      label: S.suo6ListenPort,
                      hint: '1081',
                      enabled: !locked,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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
          onPressed: locked
              ? null
              : () {
                  if (urlController.text.trim().isEmpty) return;
                  Navigator.pop(context, true);
                },
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          child: Text(
            submitLabel,
            style: AppTextStyles.body(color: AppColors.bgDark),
          ),
        ),
      ],
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    bool autofocus = false,
    bool enabled = true,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      enabled: enabled,
      keyboardType: keyboardType,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontFamily: 'monospace',
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textMuted),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(
            color: AppColors.primary.withValues(alpha: 0.5),
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderSide: BorderSide(
            color: AppColors.border.withValues(alpha: 0.3),
          ),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.primary),
        ),
      ),
    );
  }
}
