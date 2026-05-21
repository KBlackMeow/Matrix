import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/localization.dart';
import '../database/database_helper.dart';
import '../models/project.dart';
import '../models/suo5_profile.dart';
import '../models/suo6_profile.dart';
import '../services/suo5_client_service.dart';
import '../services/suo6_client_service.dart';
import '../theme/app_theme.dart';

/// 从其他页面请求打开「新建隧道」编辑器（[SuoTunnelProxyPage] 须已挂载且项目 id 匹配）。
class SuoTunnelOpenCreateEvent {
  final int projectId;
  final String prefillUrl;

  /// 对应编辑器内 multiplex 协议（`initialS6`）。
  final bool defaultSuo6;

  const SuoTunnelOpenCreateEvent({
    required this.projectId,
    required this.prefillUrl,
    this.defaultSuo6 = false,
  });
}

/// 统一管理 suo5 / suo6 SOCKS 代理：同一列表、编辑时可切换协议版本。
class SuoTunnelProxyPage extends StatefulWidget {
  static final _refreshBus = StreamController<void>.broadcast();
  static void notifyRefresh() => _refreshBus.add(null);

  static final _openCreateBus =
      StreamController<SuoTunnelOpenCreateEvent>.broadcast();

  /// 在对应项目的隧道页上弹出新建配置对话框，并预填目标 URL。
  static void notifyOpenCreate({
    required int projectId,
    required String prefillUrl,
    bool defaultSuo6 = false,
  }) {
    _openCreateBus.add(
      SuoTunnelOpenCreateEvent(
        projectId: projectId,
        prefillUrl: prefillUrl,
        defaultSuo6: defaultSuo6,
      ),
    );
  }

  final Project project;
  final VoidCallback onSwitchProject;

  const SuoTunnelProxyPage({
    super.key,
    required this.project,
    required this.onSwitchProject,
  });

  @override
  State<SuoTunnelProxyPage> createState() => _SuoTunnelProxyPageState();
}

class _MergedEntry {
  final bool isS6;
  final Suo5Profile? p5;
  final Suo6Profile? p6;

  const _MergedEntry.s5(this.p5) : isS6 = false, p6 = null;
  const _MergedEntry.s6(this.p6) : isS6 = true, p5 = null;

  int get id => isS6 ? p6!.id : p5!.id;
  String get name => isS6 ? p6!.name : p5!.name;
  String get targetUrl => isS6 ? p6!.targetUrl : p5!.targetUrl;
  String get listenHost => isS6 ? p6!.listenHost : p5!.listenHost;
  int get listenPort => isS6 ? p6!.listenPort : p5!.listenPort;
  DateTime get updatedAt => isS6 ? p6!.updatedAt : p5!.updatedAt;
}

/// 单一路由：加载 → 结果，仅一次 [Navigator.pop]，避免残留遮罩导致无法操作。
class _SuoHandshakeProbeDialog extends StatefulWidget {
  const _SuoHandshakeProbeDialog({required this.runProbe});

  final Future<void> Function() runProbe;

  @override
  State<_SuoHandshakeProbeDialog> createState() => _SuoHandshakeProbeDialogState();
}

class _SuoHandshakeProbeDialogState extends State<_SuoHandshakeProbeDialog> {
  bool _loading = true;
  Object? _err;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    Object? err;
    try {
      await widget.runProbe();
    } catch (e) {
      err = e;
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _err = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  S.suoProbeHandshakeLoading,
                  style: AppTextStyles.body(size: 14),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final ok = _err == null;
    final bodyText =
        ok ? S.suo5HandshakeOk : S.suo5HandshakeFailed(_err as Object);
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(
          S.suoHandshakeResultTitle,
          style: AppTextStyles.heading(
            size: 16,
            color: ok ? AppColors.primary : AppColors.red,
          ),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440, maxHeight: 360),
          child: SingleChildScrollView(
            child: SelectableText(
              bodyText,
              style: AppTextStyles.body(
                size: 13,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            style: FilledButton.styleFrom(
              backgroundColor: ok
                  ? AppColors.primary.withValues(alpha: 0.22)
                  : AppColors.red.withValues(alpha: 0.2),
              foregroundColor: ok ? AppColors.primary : AppColors.red,
            ),
            child: Text(S.btnConfirm),
          ),
        ],
      ),
    );
  }
}

class _SuoTunnelProxyPageState extends State<SuoTunnelProxyPage> {
  final DatabaseHelper _db = DatabaseHelper();
  final Suo5ClientService _s5 = Suo5ClientService();
  final Suo6ClientService _s6 = Suo6ClientService();
  final ScrollController _logScroll = ScrollController();
  StreamSubscription<void>? _refreshSub;
  StreamSubscription<SuoTunnelOpenCreateEvent>? _openCreateSub;

  List<Suo5Profile> _profiles5 = [];
  List<Suo6Profile> _profiles6 = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    void onAny() {
      if (!mounted) return;
      setState(() {});
      _scrollLogsToBottom();
    }

    _s5.onChanged = onAny;
    _s6.onChanged = onAny;
    _refreshSub = SuoTunnelProxyPage._refreshBus.stream.listen((_) {
      if (mounted) _loadProfiles();
    });
    _openCreateSub = SuoTunnelProxyPage._openCreateBus.stream.listen((e) {
      if (!mounted || e.projectId != widget.project.id) return;
      _showEditorDialog(
        title: S.suoTunnelNewConfigTitle,
        submitLabel: S.btnAdd,
        initialS6: e.defaultSuo6,
        protocolLocked: false,
        wasS6: null,
        editingId: null,
        url: e.prefillUrl,
        name: _deriveNameFromUrl(e.prefillUrl),
        host: '127.0.0.1',
        port: _suggestPort(),
      );
    });
    _loadProfiles();
  }

  @override
  void didUpdateWidget(covariant SuoTunnelProxyPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.project.id != widget.project.id) {
      _loadProfiles();
    }
  }

  @override
  void dispose() {
    _refreshSub?.cancel();
    _openCreateSub?.cancel();
    _s5.onChanged = null;
    _s6.onChanged = null;
    _logScroll.dispose();
    super.dispose();
  }

  Future<void> _loadProfiles() async {
    setState(() => _loading = true);
    final a = await _db.getSuo5ProfilesByProject(widget.project.id);
    final b = await _db.getSuo6ProfilesByProject(widget.project.id);
    if (!mounted) return;
    setState(() {
      _profiles5 = a;
      _profiles6 = b;
      _loading = false;
    });
  }

  List<_MergedEntry> _mergedSorted() {
    final list = <_MergedEntry>[
      ..._profiles5.map(_MergedEntry.s5),
      ..._profiles6.map(_MergedEntry.s6),
    ];
    list.sort((x, y) => y.updatedAt.compareTo(x.updatedAt));
    return list;
  }

  bool _portTaken(int? editingId, bool editingIs6, String host, int port) {
    for (final p in _profiles5) {
      if (p.listenHost == host &&
          p.listenPort == port &&
          !(editingId == p.id && !editingIs6)) {
        return true;
      }
    }
    for (final p in _profiles6) {
      if (p.listenHost == host &&
          p.listenPort == port &&
          !(editingId == p.id && editingIs6)) {
        return true;
      }
    }
    return false;
  }

  String _occupiedName(String host, int port) {
    for (final p in _profiles5) {
      if (p.listenHost == host && p.listenPort == port) return p.name;
    }
    for (final p in _profiles6) {
      if (p.listenHost == host && p.listenPort == port) return p.name;
    }
    return '';
  }

  String _suggestPort() {
    final used = <int>{
      ..._profiles5.map((p) => p.listenPort),
      ..._profiles6.map((p) => p.listenPort),
    };
    for (var port = 1080; port <= 1099; port++) {
      if (!used.contains(port)) return port.toString();
    }
    return '1080';
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

  Future<void> _startOrStop(_MergedEntry e) async {
    if (e.isS6) {
      final p = e.p6!;
      if (_s6.isRunning(p.id)) {
        await _s6.stopProfile(p.id);
        return;
      }
      if (p.targetUrl.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.suo6MissingUrl),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      await _s6.startProfile(p.id, p.toConfig(), label: p.name);
    } else {
      final p = e.p5!;
      if (_s5.isRunning(p.id)) {
        await _s5.stopProfile(p.id);
        return;
      }
      if (p.targetUrl.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.suo5MissingUrl),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      await _s5.startProfile(p.id, p.toConfig(), label: p.name);
    }
  }

  Future<void> _probeHandshake(
    Future<void> Function() runProbe,
  ) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (ctx) => _SuoHandshakeProbeDialog(runProbe: runProbe),
    );
  }

  Future<void> _probeS5(Suo5Profile p) =>
      _probeHandshake(() => _s5.probe(p.toConfig(), label: p.name));

  Future<void> _probeS6(Suo6Profile p) =>
      _probeHandshake(() => _s6.probe(p.toConfig(), label: p.name));

  Future<void> _confirmDelete(_MergedEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.btnDelete, style: const TextStyle(color: AppColors.red)),
        content: Text(
          e.isS6 ? S.confirmDeleteSuo6(e.name) : S.confirmDeleteSuo5(e.name),
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
    if (e.isS6) {
      await _s6.removeProfile(e.p6!.id);
      await _db.deleteSuo6Profile(e.p6!.id);
    } else {
      await _s5.removeProfile(e.p5!.id);
      await _db.deleteSuo5Profile(e.p5!.id);
    }
    await _loadProfiles();
  }

  Future<void> _showCreateDialog() async {
    await _showEditorDialog(
      title: S.suoTunnelNewConfigTitle,
      submitLabel: S.btnAdd,
      initialS6: false,
      protocolLocked: false,
      wasS6: null,
      editingId: null,
      url: '',
      name: '',
      host: '127.0.0.1',
      port: _suggestPort(),
    );
  }

  Future<void> _showEditDialog(_MergedEntry e) async {
    final locked = e.isS6
        ? (_s6.isRunning(e.p6!.id))
        : (_s5.isRunning(e.p5!.id));
    await _showEditorDialog(
      title: S.suoTunnelEditConfigTitle,
      submitLabel: S.btnSave,
      initialS6: e.isS6,
      protocolLocked: locked,
      wasS6: e.isS6,
      editingId: e.id,
      url: e.targetUrl,
      name: e.name,
      host: e.listenHost,
      port: e.listenPort.toString(),
    );
  }

  Future<void> _showEditorDialog({
    required String title,
    required String submitLabel,
    required bool initialS6,
    required bool protocolLocked,
    required bool? wasS6,
    required int? editingId,
    required String url,
    required String name,
    required String host,
    required String port,
  }) async {
    final urlCtrl = TextEditingController(text: url);
    final nameCtrl = TextEditingController(text: name);
    final hostCtrl = TextEditingController(text: host);
    final portCtrl = TextEditingController(text: port);

    final result = await showDialog<_EditorResult>(
      context: context,
      builder: (ctx) => _TunnelEditorDialog(
        title: title,
        submitLabel: submitLabel,
        initialS6: initialS6,
        protocolLocked: protocolLocked,
        urlController: urlCtrl,
        nameController: nameCtrl,
        hostController: hostCtrl,
        portController: portCtrl,
      ),
    );
    if (result == null || !result.ok) return;

    final newUrl = urlCtrl.text.trim();
    final newName = nameCtrl.text.trim().isEmpty
        ? _deriveNameFromUrl(newUrl)
        : nameCtrl.text.trim();
    final newHost = hostCtrl.text.trim().isEmpty
        ? '127.0.0.1'
        : hostCtrl.text.trim();
    final newPort = int.tryParse(portCtrl.text.trim()) ?? 0;
    if (newUrl.isEmpty) return;
    if (newPort < 1 || newPort > 65535) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.isS6 ? S.suo6InvalidPort : S.suo5InvalidPort),
        ),
      );
      return;
    }
    final uri = Uri.tryParse(newUrl);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.isS6 ? S.suo6InvalidUrl : S.suo5InvalidUrl),
        ),
      );
      return;
    }

    if (_portTaken(editingId, wasS6 ?? false, newHost, newPort)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '端口冲突: $newHost:$newPort 已被配置 "${_occupiedName(newHost, newPort)}" 占用',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (editingId == null) {
      if (result.isS6) {
        await _db.createSuo6Profile(
          projectId: widget.project.id,
          name: newName,
          targetUrl: newUrl,
          listenHost: newHost,
          listenPort: newPort,
        );
      } else {
        await _db.createSuo5Profile(
          projectId: widget.project.id,
          name: newName,
          targetUrl: newUrl,
          listenHost: newHost,
          listenPort: newPort,
        );
      }
    } else {
      final switched = wasS6 != null && wasS6 != result.isS6;
      if (switched) {
        if (!mounted) return;
        final confirm = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(
              S.suoTunnelProtocolSwitchTitle,
              style: AppTextStyles.heading(color: AppColors.primary),
            ),
            content: Text(
              S.suoTunnelProtocolSwitchBody,
              style: const TextStyle(color: AppColors.textPrimary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: Text(
                  S.btnCancel,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text(
                  S.btnSave,
                  style: const TextStyle(color: AppColors.bgDark),
                ),
              ),
            ],
          ),
        );
        if (confirm != true) return;
        if (wasS6 == true) {
          await _s6.removeProfile(editingId);
          await _db.deleteSuo6Profile(editingId);
          await _db.createSuo5Profile(
            projectId: widget.project.id,
            name: newName,
            targetUrl: newUrl,
            listenHost: newHost,
            listenPort: newPort,
          );
        } else {
          await _s5.removeProfile(editingId);
          await _db.deleteSuo5Profile(editingId);
          await _db.createSuo6Profile(
            projectId: widget.project.id,
            name: newName,
            targetUrl: newUrl,
            listenHost: newHost,
            listenPort: newPort,
          );
        }
      } else if (result.isS6) {
        final p = _profiles6.firstWhere((x) => x.id == editingId);
        await _db.updateSuo6Profile(
          p.copyWith(
            name: newName,
            targetUrl: newUrl,
            listenHost: newHost,
            listenPort: newPort,
          ),
        );
        _s6.sessionFor(editingId)?.label = newName;
      } else {
        final p = _profiles5.firstWhere((x) => x.id == editingId);
        await _db.updateSuo5Profile(
          p.copyWith(
            name: newName,
            targetUrl: newUrl,
            listenHost: newHost,
            listenPort: newPort,
          ),
        );
        _s5.sessionFor(editingId)?.label = newName;
      }
    }

    await _loadProfiles();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(S.suoTunnelProfileCreatedSnack),
        behavior: SnackBarBehavior.floating,
      ),
    );
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

  List<String> _mergedLogLines() {
    final merged =
        <({DateTime when, String line})>[
          ..._s5.aggregatedLogEvents,
          ..._s6.aggregatedLogEvents,
        ]..sort((a, b) {
          final c = a.when.compareTo(b.when);
          if (c != 0) return c;
          return a.line.compareTo(b.line);
        });
    return merged.map((e) => e.line).toList(growable: false);
  }

  Color _tunnelLogLineColor(String line) {
    final lower = line.toLowerCase();
    final err =
        line.contains('失败') ||
        line.contains('异常') ||
        line.contains('错误') ||
        lower.contains('error') ||
        lower.contains('failed');
    final ok =
        line.contains('成功') ||
        line.contains('建立') ||
        line.contains('✓') ||
        lower.contains('success') ||
        lower.contains('handshake ok') ||
        lower.contains('probe ok') ||
        lower.contains('channel established');
    if (err) return AppColors.red;
    if (ok) return AppColors.primary;
    return AppColors.textSecondary;
  }

  int _runningTotal() => _s5.runningCount + _s6.runningCount;
  int _connectingTotal() =>
      _s5.connectingCount +
      _s6.sessions.values
          .where((s) => s.status == Suo6Status.connecting)
          .length;

  @override
  Widget build(BuildContext context) {
    final merged = _mergedSorted();
    final total = _profiles5.length + _profiles6.length;
    final running = _runningTotal();
    final connecting = _connectingTotal();
    final hasActive = running + connecting > 0;
    final accent = hasActive ? AppColors.primary : AppColors.textMuted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
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
                child: Icon(AppTunnelIcons.outlined, color: accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      S.suoTunnelManagementTitle(widget.project.name),
                      style: AppTextStyles.heading(
                        size: 15,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      S.suo5HeaderRunningSummary(running + connecting, total),
                      style: AppTextStyles.caption(size: 13, color: accent),
                    ),
                    if (hasActive) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          Text(
                            '${S.suo5StatActiveConn}: ${_s5.totalActiveConnections + _s6.totalActiveConn}',
                            style: AppTextStyles.caption(
                              size: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                          Text(
                            '↑ ${_fmtBytes(_s5.totalUploadBytes + _s6.totalUpload)}',
                            style: AppTextStyles.caption(
                              size: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                          Text(
                            '↓ ${_fmtBytes(_s5.totalDownloadBytes + _s6.totalDownload)}',
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
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            FilledButton.icon(
              onPressed: _loading ? null : _showCreateDialog,
              icon: const Icon(Icons.add, size: 18),
              label: Text(S.actionAddSuoTunnel),
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
                S.suoTunnelCount(total),
                style: AppTextStyles.caption(color: AppColors.textMuted),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 720;
              final list = _buildList(merged);
              final logs = _buildLogSection();
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: list),
                    const SizedBox(width: 16),
                    Expanded(child: logs),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: list),
                  const SizedBox(height: 16),
                  Expanded(child: logs),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildList(List<_MergedEntry> merged) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (merged.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              AppTunnelIcons.outlined,
              size: 64,
              color: AppColors.textSecondary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              S.suoTunnelEmptyHint(S.actionAddSuoTunnel),
              style: AppTextStyles.body(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      itemCount: merged.length,
      itemBuilder: (context, i) {
        final e = merged[i];
        return _TunnelEntryCard(
          entry: e,
          s5: _s5,
          s6: _s6,
          fmtBytes: _fmtBytes,
          onStartStop: () => _startOrStop(e),
          onProbe: e.isS6 ? () => _probeS6(e.p6!) : () => _probeS5(e.p5!),
          onEdit: () => _showEditDialog(e),
          onDelete: () => _confirmDelete(e),
        );
      },
    );
  }

  Widget _buildLogSection() {
    final lines = _mergedLogLines();
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
                S.suoTunnelRunLog,
                style: AppTextStyles.caption(
                  size: 12,
                  color: AppColors.textMuted,
                ),
              ),
              const Spacer(),
              if (lines.isNotEmpty) ...[
                GestureDetector(
                  onTap: () async {
                    await Clipboard.setData(
                      ClipboardData(text: lines.join('\n')),
                    );
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(S.suo5LogCopiedSnack),
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
                    _s5.clearAllLogs();
                    _s6.clearAllLogs();
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
                      S.suo5NoLogs,
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
                      return Text(
                        line,
                        style: AppTextStyles.terminal(
                          size: 12,
                          color: _tunnelLogLineColor(line),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _EditorResult {
  final bool ok;
  final bool isS6;
  const _EditorResult({required this.ok, required this.isS6});
}

class _TunnelEditorDialog extends StatefulWidget {
  final String title;
  final String submitLabel;
  final bool initialS6;
  final bool protocolLocked;
  final TextEditingController urlController;
  final TextEditingController nameController;
  final TextEditingController hostController;
  final TextEditingController portController;

  const _TunnelEditorDialog({
    required this.title,
    required this.submitLabel,
    required this.initialS6,
    required this.protocolLocked,
    required this.urlController,
    required this.nameController,
    required this.hostController,
    required this.portController,
  });

  @override
  State<_TunnelEditorDialog> createState() => _TunnelEditorDialogState();
}

class _TunnelEditorDialogState extends State<_TunnelEditorDialog> {
  late bool _is6;

  @override
  void initState() {
    super.initState();
    _is6 = widget.initialS6;
  }

  @override
  Widget build(BuildContext context) {
    final locked = widget.protocolLocked;
    return AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Text(
              widget.title,
              style: AppTextStyles.heading(color: AppColors.primary),
            ),
          ),
          if (locked)
            Text(
              S.suo5RunningNoEdit,
              style: AppTextStyles.caption(size: 10, color: Colors.orange),
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
              Text(
                S.suoTunnelProtocol,
                style: AppTextStyles.caption(
                  size: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment<bool>(
                    value: false,
                    label: Text(S.suoTunnelProtocolSuo5),
                  ),
                  ButtonSegment<bool>(
                    value: true,
                    label: Text(S.suoTunnelProtocolSuo6),
                  ),
                ],
                selected: {_is6},
                emptySelectionAllowed: false,
                showSelectedIcon: false,
                onSelectionChanged: locked
                    ? (_) {}
                    : (s) => setState(() => _is6 = s.first),
              ),
              const SizedBox(height: 16),
              _tf(
                widget.urlController,
                S.suo5TargetUrl,
                S.suo5TargetUrlHint,
                autofocus: true,
                enabled: !locked,
              ),
              const SizedBox(height: 16),
              _tf(
                widget.nameController,
                S.suo5ConfigName,
                S.suo5ConfigNameHint,
                enabled: !locked,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: _tf(
                      widget.hostController,
                      S.suo5ListenHost,
                      '127.0.0.1',
                      enabled: !locked,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _tf(
                      widget.portController,
                      S.suo5ListenPort,
                      '1080',
                      enabled: !locked,
                      number: true,
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
          onPressed: () => Navigator.pop(context),
          child: Text(
            S.btnCancel,
            style: AppTextStyles.body(color: AppColors.textSecondary),
          ),
        ),
        FilledButton(
          onPressed: locked || widget.urlController.text.trim().isEmpty
              ? null
              : () =>
                    Navigator.pop(context, _EditorResult(ok: true, isS6: _is6)),
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          child: Text(
            widget.submitLabel,
            style: AppTextStyles.body(color: AppColors.bgDark),
          ),
        ),
      ],
    );
  }

  Widget _tf(
    TextEditingController c,
    String label,
    String hint, {
    bool autofocus = false,
    bool enabled = true,
    bool number = false,
  }) {
    return TextField(
      controller: c,
      autofocus: autofocus,
      enabled: enabled,
      onChanged: (_) => setState(() {}),
      keyboardType: number ? TextInputType.number : TextInputType.text,
      style: AppTextStyles.terminal(size: 14, color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: AppTextStyles.caption(color: AppColors.textMuted),
        labelStyle: AppTextStyles.caption(color: AppColors.textSecondary),
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

class _TunnelEntryCard extends StatefulWidget {
  final _MergedEntry entry;
  final Suo5ClientService s5;
  final Suo6ClientService s6;
  final String Function(int) fmtBytes;
  final VoidCallback onStartStop;
  final VoidCallback? onProbe;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _TunnelEntryCard({
    required this.entry,
    required this.s5,
    required this.s6,
    required this.fmtBytes,
    required this.onStartStop,
    required this.onProbe,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_TunnelEntryCard> createState() => _TunnelEntryCardState();
}

class _TunnelEntryCardState extends State<_TunnelEntryCard> {
  bool _hovered = false;

  bool get _is6 => widget.entry.isS6;

  bool get _running {
    if (_is6) {
      final s = widget.s6.sessionFor(widget.entry.p6!.id);
      return s != null &&
          (s.status == Suo6Status.running || s.status == Suo6Status.connecting);
    }
    final s = widget.s5.sessionFor(widget.entry.p5!.id);
    return s != null &&
        (s.status == Suo5Status.running || s.status == Suo5Status.connecting);
  }

  bool get _connecting {
    if (_is6) {
      return widget.s6.sessionFor(widget.entry.p6!.id)?.status ==
          Suo6Status.connecting;
    }
    return widget.s5.sessionFor(widget.entry.p5!.id)?.status ==
        Suo5Status.connecting;
  }

  Color get _statusColor {
    if (_is6) {
      switch (widget.s6.sessionFor(widget.entry.p6!.id)?.status ??
          Suo6Status.idle) {
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
    switch (widget.s5.sessionFor(widget.entry.p5!.id)?.status ??
        Suo5Status.idle) {
      case Suo5Status.running:
        return AppColors.primary;
      case Suo5Status.connecting:
        return Colors.orange;
      case Suo5Status.error:
        return AppColors.red;
      case Suo5Status.idle:
        return AppColors.textMuted;
    }
  }

  String get _statusLabel {
    if (_is6) {
      switch (widget.s6.sessionFor(widget.entry.p6!.id)?.status ??
          Suo6Status.idle) {
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
    switch (widget.s5.sessionFor(widget.entry.p5!.id)?.status ??
        Suo5Status.idle) {
      case Suo5Status.running:
        return S.suo5StatusRunning;
      case Suo5Status.connecting:
        return S.suo5StatusConnecting;
      case Suo5Status.error:
        return S.suo5StatusError;
      case Suo5Status.idle:
        return S.suo5StatusIdle;
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final running = _running;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
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
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  _is6 ? Icons.cable : Icons.sync_alt,
                  color: AppColors.primary,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              e.name,
                              style: AppTextStyles.body(
                                size: 14,
                                color: AppColors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          _ChipLbl(
                            label: _is6
                                ? S.suoTunnelProtocolSuo6
                                : S.suoTunnelProtocolSuo5,
                            color: _is6 ? AppColors.primary : AppColors.cyan,
                          ),
                          const SizedBox(width: 6),
                          _ChipLbl(
                            label: '${e.listenHost}:${e.listenPort}',
                            color: AppColors.cyan,
                          ),
                          if (running) ...[
                            const SizedBox(width: 6),
                            _ChipLbl(label: _statusLabel, color: _statusColor),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              e.targetUrl,
                              style: AppTextStyles.caption(
                                size: 12,
                                color: AppColors.primary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          InkWell(
                            onTap: () {
                              Clipboard.setData(
                                ClipboardData(text: e.targetUrl),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(S.snackCopied),
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
                      if (running) _statsRow(),
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
                  onPressed: _connecting ? null : widget.onStartStop,
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
                if (widget.onProbe != null)
                  TextButton.icon(
                    onPressed: running ? null : widget.onProbe,
                    icon: const Icon(
                      Icons.wifi_tethering,
                      size: 16,
                      color: AppColors.cyan,
                    ),
                    label: Text(
                      S.suo5BtnProbe,
                      style: AppTextStyles.caption(
                        size: 12,
                        color: AppColors.cyan,
                      ),
                    ),
                  ),
                TextButton.icon(
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

  Widget _statsRow() {
    if (_is6) {
      final s = widget.s6.sessionFor(widget.entry.p6!.id);
      if (s == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          spacing: 12,
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
      );
    }
    final s = widget.s5.sessionFor(widget.entry.p5!.id);
    if (s == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 12,
        children: [
          Text(
            '${S.suo5StatActiveConn}: ${s.activeConnections}',
            style: AppTextStyles.caption(size: 11, color: AppColors.textMuted),
          ),
          Text(
            '${S.suo5StatUpload}: ${widget.fmtBytes(s.uploadBytes)}',
            style: AppTextStyles.caption(size: 11, color: AppColors.textMuted),
          ),
          Text(
            '${S.suo5StatDownload}: ${widget.fmtBytes(s.downloadBytes)}',
            style: AppTextStyles.caption(size: 11, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _ChipLbl extends StatelessWidget {
  final String label;
  final Color color;
  const _ChipLbl({required this.label, required this.color});

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
