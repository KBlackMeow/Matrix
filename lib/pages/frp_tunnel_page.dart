import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../app/localization.dart';
import '../database/database_helper.dart';
import '../models/frp_profile.dart';
import '../services/frp_client_service.dart';
import '../services/reverse_shell_service.dart';
import '../theme/app_theme.dart';

// ---------------------------------------------------------------------------
// 复制配置：frps 上 proxy 名称唯一，同一远端端口通常也只能被一个 TCP 代理占用
// ---------------------------------------------------------------------------

bool _frpSameServer(FrpProfile a, FrpProfile b) =>
    a.serverAddr == b.serverAddr && a.serverPort == b.serverPort;

bool _proxyNameTakenOnServer(
  String proxyName,
  FrpProfile serverRef,
  List<FrpProfile> all,
) => all.any((x) => _frpSameServer(x, serverRef) && x.proxyName == proxyName);

bool _remotePortTakenOnServer(
  int port,
  FrpProfile serverRef,
  List<FrpProfile> all,
) => all.any((x) => _frpSameServer(x, serverRef) && x.remotePort == port);

String _uniqueDuplicateDisplayName(String baseName, List<FrpProfile> all) {
  var name = S.frpDupDisplayName(baseName);
  if (!all.any((x) => x.name == name)) return name;
  for (var i = 2; ; i++) {
    name = S.frpDupDisplayNameIndexed(baseName, i);
    if (!all.any((x) => x.name == name)) return name;
  }
}

/// 与同一 frps 上已有配置不冲突的代理名
String _uniqueDuplicateProxyName(FrpProfile source, List<FrpProfile> all) {
  final first = S.frpDupProxyFirst(source.proxyName);
  if (!_proxyNameTakenOnServer(first, source, all)) return first;
  for (var i = 2; ; i++) {
    final c = S.frpDupProxyIndexed(source.proxyName, i);
    if (!_proxyNameTakenOnServer(c, source, all)) return c;
  }
}

/// 同一 frps 上尚未占用的远端端口（从原端口 +1 起找）
int _nextFreeRemotePortOnServer(FrpProfile source, List<FrpProfile> all) {
  bool taken(int port) => _remotePortTakenOnServer(port, source, all);
  for (var port = source.remotePort + 1; port <= 65535; port++) {
    if (!taken(port)) return port;
  }
  for (var port = 1024; port < source.remotePort; port++) {
    if (!taken(port)) return port;
  }
  return source.remotePort + 1;
}

/// 与 [FrpProfile.toConfig] 一致，用于把运行中的单例连接对应回某条已保存配置
bool _frpTunnelConfigMatchesProfile(FrpTunnelConfig c, FrpProfile p) {
  return c.serverAddr == p.serverAddr &&
      c.serverPort == p.serverPort &&
      c.token == p.token &&
      c.proxyName == p.proxyName &&
      c.remotePort == p.remotePort &&
      c.localAddr == p.localAddr &&
      c.localPort == p.localPort &&
      c.version == p.version &&
      c.useTcpMux == p.useTcpMux &&
      c.authMode == p.authMode;
}

/// FRP 客户端页面
///
/// 每条配置独立卡片：启动 / 编辑 / 复制 / 删除；编辑在弹窗中打开，修改自动保存。
class FrpTunnelPage extends StatefulWidget {
  const FrpTunnelPage({super.key});

  @override
  State<FrpTunnelPage> createState() => _FrpTunnelPageState();
}

class _FrpTunnelPageState extends State<FrpTunnelPage> {
  final _frpService = FrpClientService();
  final _shellService = ReverseShellService();
  final _db = DatabaseHelper();
  List<FrpProfile> _profiles = [];
  int? _activeProfileId;
  final ScrollController _logScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _frpService.onChanged = () {
      if (!mounted) return;
      setState(() {
        _activeProfileId = _resolveActiveProfileId();
      });
      _scrollLogsToBottom();
    };
    _loadProfiles();
  }

  /// [FrpClientService] 为全局单例，离开页面再进入时须根据 currentConfig 恢复「当前是哪条配置」
  int? _resolveActiveProfileId() {
    final cfg = _frpService.currentConfig;
    final s = _frpService.status;
    if (cfg == null ||
        (s != FrpTunnelStatus.running && s != FrpTunnelStatus.connecting)) {
      return null;
    }
    for (final p in _profiles) {
      if (_frpTunnelConfigMatchesProfile(cfg, p)) return p.id;
    }
    return null;
  }

  Future<void> _loadProfiles() async {
    final list = await _db.getAllFrpProfiles();
    if (!mounted) return;
    setState(() {
      _profiles = list;
      _activeProfileId = _resolveActiveProfileId();
    });
  }

  Future<void> _openEditorDialog({FrpProfile? profile}) async {
    await _shellService.loadConfig();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _FrpProfileEditorDialog(
        profile: profile,
        defaultLocalPort: _shellService.lport,
        frpService: _frpService,
        activeProfileId: _activeProfileId,
        onSaved: _loadProfiles,
      ),
    );
    await _loadProfiles();
  }

  Future<void> _duplicateProfile(FrpProfile p) async {
    try {
      final all = await _db.getAllFrpProfiles();
      final name = _uniqueDuplicateDisplayName(p.name, all);
      final proxyName = _uniqueDuplicateProxyName(p, all);
      final remotePort = _nextFreeRemotePortOnServer(p, all);

      await _db.createFrpProfile(
        name: name,
        serverAddr: p.serverAddr,
        serverPort: p.serverPort,
        token: p.token,
        proxyName: proxyName,
        remotePort: remotePort,
        localAddr: p.localAddr,
        localPort: p.localPort,
        version: p.version,
        useTcpMux: p.useTcpMux,
        authMode: p.authMode,
      );
      await _loadProfiles();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.frpDuplicatedSnack(name, proxyName, remotePort)),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.frpDuplicateFailed(e)),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  bool _isRunningProfile(FrpProfile p) {
    final s = _frpService.status;
    return (s == FrpTunnelStatus.running || s == FrpTunnelStatus.connecting) &&
        _activeProfileId == p.id;
  }

  Future<void> _startOrStopProfile(FrpProfile p) async {
    if (_isRunningProfile(p)) {
      await _frpService.stop();
      if (mounted) setState(() => _activeProfileId = null);
      return;
    }

    if (p.serverAddr.isEmpty || p.proxyName.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(S.frpMissingServerOrProxy)));
      return;
    }

    if (_frpService.status == FrpTunnelStatus.running ||
        _frpService.status == FrpTunnelStatus.connecting) {
      await _frpService.stop();
    }

    await _frpService.start(p.toConfig());
    if (mounted) setState(() => _activeProfileId = p.id);
  }

  Future<void> _confirmDelete(FrpProfile p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.frpDeleteTitle, style: AppTextStyles.heading(size: 16)),
        content: Text(
          S.frpConfirmDelete(p.name),
          style: AppTextStyles.caption(
            size: 13,
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              S.btnCancel,
              style: AppTextStyles.caption(
                size: 13,
                color: AppColors.textMuted,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              S.btnDelete,
              style: AppTextStyles.caption(size: 13, color: AppColors.red),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    if (_isRunningProfile(p)) {
      await _frpService.stop();
      _activeProfileId = null;
    }
    await _db.deleteFrpProfile(p.id);
    await _loadProfiles();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.frpDeletedSnack(p.name)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  void dispose() {
    _logScroll.dispose();
    _frpService.onChanged = null;
    super.dispose();
  }

  void _scrollLogsToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients) {
        _logScroll.animateTo(
          _logScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String? _activeProfileName() {
    if (_activeProfileId == null) return null;
    try {
      return _profiles.firstWhere((e) => e.id == _activeProfileId).name;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _frpService.status;
    final isActive =
        status == FrpTunnelStatus.running ||
        status == FrpTunnelStatus.connecting;

    return LayoutBuilder(
      builder: (context, constraints) {
        final useHorizontal = constraints.maxWidth >= 720;
        if (useHorizontal) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 1,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(right: 8),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 280),
                    child: _buildConfigColumn(status, isActive),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(flex: 1, child: _buildLogSection()),
            ],
          );
        } else {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: _buildConfigColumn(status, isActive),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(child: _buildLogSection()),
            ],
          );
        }
      },
    );
  }

  Widget _buildConfigColumn(FrpTunnelStatus status, bool isActive) {
    final activeName = _activeProfileName();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _statusColor(status).withValues(alpha: 0.6),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  AppFrpIcons.filled,
                  color: _statusColor(status),
                  size: 32,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        S.frpTunnelTitle,
                        style: AppTextStyles.heading(
                          size: 18,
                          color: _statusColor(status),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        activeName != null && isActive
                            ? '${_statusLabel(status)} · $activeName'
                            : _statusLabel(status),
                        style: AppTextStyles.caption(
                          size: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if (isActive && activeName == null) ...[
                        const SizedBox(height: 6),
                        Text(
                          S.frpActiveNotMatched,
                          style: AppTextStyles.caption(
                            size: 11,
                            color: Colors.orange,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (isActive && activeName == null)
                  TextButton(
                    onPressed: () async {
                      await _frpService.stop();
                      if (mounted) {
                        setState(() => _activeProfileId = null);
                      }
                    },
                    child: Text(
                      S.frpStopConnection,
                      style: AppTextStyles.caption(
                        size: 12,
                        color: AppColors.red,
                      ),
                    ),
                  ),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _statusColor(status),
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                              color: _statusColor(
                                status,
                              ).withValues(alpha: 0.6),
                              blurRadius: 8,
                            ),
                          ]
                        : null,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          Text(
            S.frpSavedConfigs,
            style: AppTextStyles.caption(size: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),

          if (_profiles.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              decoration: BoxDecoration(
                color: AppColors.bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.bgCard),
              ),
              child: Text(
                S.frpNoConfigs,
                style: AppTextStyles.caption(
                  size: 12,
                  color: AppColors.textMuted,
                ),
              ),
            )
          else
            ..._profiles.map(
              (p) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _buildProfileCard(p, status),
              ),
            ),

          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => _openEditorDialog(profile: null),
            icon: const Icon(Icons.add, size: 18),
            label: Text(S.frpNewConfig),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard(FrpProfile p, FrpTunnelStatus status) {
    final running = _isRunningProfile(p);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: running
              ? AppColors.primary.withValues(alpha: 0.45)
              : AppColors.bgCard.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                running ? Icons.play_circle_outline : Icons.bookmark_outline,
                size: 18,
                color: running ? AppColors.primary : AppColors.textMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      style: AppTextStyles.terminal(
                        size: 13,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      S.frpMappingLabel(p.remotePort, p.localAddr, p.localPort),
                      style: AppTextStyles.caption(
                        size: 11,
                        color: AppColors.textMuted,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      S.frpServerLabel(p.serverAddr, p.serverPort),
                      style: AppTextStyles.caption(
                        size: 10,
                        color: AppColors.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            alignment: WrapAlignment.start,
            children: [
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: status == FrpTunnelStatus.connecting && !running
                    ? null
                    : () => _startOrStopProfile(p),
                child: Text(
                  running ? S.btnStop : S.btnStart,
                  style: AppTextStyles.caption(
                    size: 12,
                    color: running ? AppColors.red : AppColors.primary,
                  ),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => _openEditorDialog(profile: p),
                child: Text(
                  S.btnEdit,
                  style: AppTextStyles.caption(
                    size: 12,
                    color: AppColors.primary,
                  ),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => _duplicateProfile(p),
                child: Text(
                  S.btnDuplicate,
                  style: AppTextStyles.caption(
                    size: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => _confirmDelete(p),
                child: Text(
                  S.btnDelete,
                  style: AppTextStyles.caption(
                    size: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLogSection() {
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
                S.frpRunLog,
                style: AppTextStyles.caption(
                  size: 12,
                  color: AppColors.textMuted,
                ),
              ),
              const Spacer(),
              if (_frpService.logs.isNotEmpty) ...[
                GestureDetector(
                  onTap: () async {
                    final text = _frpService.logs.join('\n');
                    await Clipboard.setData(ClipboardData(text: text));
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(S.frpLogCopiedSnack),
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
                    _frpService.clearLogs();
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
            child: _frpService.logs.isEmpty
                ? Center(
                    child: Text(
                      S.frpNoLogs,
                      style: AppTextStyles.terminal(
                        size: 13,
                        color: AppColors.textMuted,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _logScroll,
                    itemCount: _frpService.logs.length,
                    itemBuilder: (context, i) {
                      final line = _frpService.logs[i];
                      final isError =
                          line.contains('失败') ||
                          line.contains('错误') ||
                          line.contains('断开') ||
                          line.contains('fail') ||
                          line.contains('Fail') ||
                          line.contains('error') ||
                          line.contains('Error');
                      final isOk =
                          line.contains('成功') ||
                          line.contains('就绪') ||
                          line.contains('桥接') ||
                          line.contains('success') ||
                          line.contains('Success') ||
                          line.contains('ready') ||
                          line.contains('Ready') ||
                          line.contains('bridge');
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

  Color _statusColor(FrpTunnelStatus s) {
    switch (s) {
      case FrpTunnelStatus.running:
        return AppColors.primary;
      case FrpTunnelStatus.connecting:
        return Colors.orange;
      case FrpTunnelStatus.error:
        return AppColors.red;
      case FrpTunnelStatus.idle:
        return AppColors.textMuted;
    }
  }

  String _statusLabel(FrpTunnelStatus s) {
    switch (s) {
      case FrpTunnelStatus.running:
        return S.frpStatusRunning;
      case FrpTunnelStatus.connecting:
        return S.frpStatusConnecting;
      case FrpTunnelStatus.error:
        return S.frpStatusError;
      case FrpTunnelStatus.idle:
        return S.frpStatusIdle;
    }
  }
}

// ---------------------------------------------------------------------------
// 编辑 / 新建 — 独立弹窗
// ---------------------------------------------------------------------------

class _FrpProfileEditorDialog extends StatefulWidget {
  const _FrpProfileEditorDialog({
    required this.profile,
    required this.defaultLocalPort,
    required this.frpService,
    required this.activeProfileId,
    required this.onSaved,
  });

  /// null 表示新建
  final FrpProfile? profile;
  final int defaultLocalPort;
  final FrpClientService frpService;

  /// 当前隧道对应的配置 id；仅当编辑这条且隧道在跑时锁定表单
  final int? activeProfileId;
  final Future<void> Function() onSaved;

  @override
  State<_FrpProfileEditorDialog> createState() =>
      _FrpProfileEditorDialogState();
}

class _FrpProfileEditorDialogState extends State<_FrpProfileEditorDialog> {
  final _db = DatabaseHelper();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _serverAddrCtrl;
  late final TextEditingController _serverPortCtrl;
  late final TextEditingController _tokenCtrl;
  late final TextEditingController _proxyNameCtrl;
  late final TextEditingController _remotePortCtrl;
  late final TextEditingController _localAddrCtrl;
  late final TextEditingController _localPortCtrl;
  late final TextEditingController _versionCtrl;

  bool _useTcpMux = true;
  FrpAuthMode _authMode = FrpAuthMode.md5;
  int? _editingId;
  Timer? _saveDebounce;
  bool _suspendAutosave = false;

  bool get _isNew => _editingId == null;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _editingId = p?.id;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _serverAddrCtrl = TextEditingController(text: p?.serverAddr ?? '');
    _serverPortCtrl = TextEditingController(
      text: (p?.serverPort ?? 7000).toString(),
    );
    _tokenCtrl = TextEditingController(text: p?.token ?? '');
    _proxyNameCtrl = TextEditingController(text: p?.proxyName ?? 'shell');
    _remotePortCtrl = TextEditingController(
      text: (p?.remotePort ?? 6000).toString(),
    );
    _localAddrCtrl = TextEditingController(text: p?.localAddr ?? '127.0.0.1');
    _localPortCtrl = TextEditingController(
      text: (p?.localPort ?? widget.defaultLocalPort).toString(),
    );
    _versionCtrl = TextEditingController(text: p?.version ?? '');
    if (p != null) {
      _useTcpMux = p.useTcpMux;
      _authMode = p.authMode;
    }

    if (_isNew) {
      scheduleMicrotask(() {
        _suspendAutosave = false;
        _schedulePersist();
      });
    }
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _nameCtrl.dispose();
    _serverAddrCtrl.dispose();
    _serverPortCtrl.dispose();
    _tokenCtrl.dispose();
    _proxyNameCtrl.dispose();
    _remotePortCtrl.dispose();
    _localAddrCtrl.dispose();
    _localPortCtrl.dispose();
    _versionCtrl.dispose();
    super.dispose();
  }

  void _maybePersist() {
    if (_suspendAutosave) return;
    _schedulePersist();
  }

  void _schedulePersist() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 450), _persistDraft);
  }

  Map<String, dynamic> _readFormForDb() {
    final serverPort = int.tryParse(_serverPortCtrl.text.trim()) ?? 7000;
    final remotePort = int.tryParse(_remotePortCtrl.text.trim()) ?? 6000;
    final localPort = int.tryParse(_localPortCtrl.text.trim()) ?? 4444;
    var name = _nameCtrl.text.trim();
    if (name.isEmpty) name = S.frpUnnamedConfig;
    return {
      'name': name,
      'serverAddr': _serverAddrCtrl.text.trim(),
      'serverPort': serverPort,
      'token': _tokenCtrl.text.trim(),
      'proxyName': _proxyNameCtrl.text.trim().isEmpty
          ? 'shell'
          : _proxyNameCtrl.text.trim(),
      'remotePort': remotePort,
      'localAddr': _localAddrCtrl.text.trim().isEmpty
          ? '127.0.0.1'
          : _localAddrCtrl.text.trim(),
      'localPort': localPort,
      'version': _versionCtrl.text.trim(),
      'useTcpMux': _useTcpMux,
      'authMode': _authMode,
    };
  }

  Future<void> _persistDraft() async {
    if (!mounted || _suspendAutosave) return;

    final m = _readFormForDb();
    final name = m['name'] as String;
    final serverAddr = m['serverAddr'] as String;
    final serverPort = m['serverPort'] as int;
    final token = m['token'] as String;
    final proxyName = m['proxyName'] as String;
    final remotePort = m['remotePort'] as int;
    final localAddr = m['localAddr'] as String;
    final localPort = m['localPort'] as int;
    final version = m['version'] as String;
    final useTcpMux = m['useTcpMux'] as bool;
    final authMode = m['authMode'] as FrpAuthMode;

    try {
      if (_editingId == null) {
        final created = await _db.createFrpProfile(
          name: name,
          serverAddr: serverAddr,
          serverPort: serverPort,
          token: token,
          proxyName: proxyName,
          remotePort: remotePort,
          localAddr: localAddr,
          localPort: localPort,
          version: version,
          useTcpMux: useTcpMux,
          authMode: authMode,
        );
        if (!mounted) return;
        setState(() => _editingId = created.id);
      } else {
        await _db.updateFrpProfile(
          id: _editingId!,
          name: name,
          serverAddr: serverAddr,
          serverPort: serverPort,
          token: token,
          proxyName: proxyName,
          remotePort: remotePort,
          localAddr: localAddr,
          localPort: localPort,
          version: version,
          useTcpMux: useTcpMux,
          authMode: authMode,
        );
      }
      await widget.onSaved();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.frpSaveFailed(e)),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// 正在跑隧道且编辑的是当前在用的那条 → 禁止改参数（避免与连接不一致）
  bool get _formLocked {
    final p = widget.profile;
    if (p == null) return false;
    final s = widget.frpService.status;
    final up = s == FrpTunnelStatus.running || s == FrpTunnelStatus.connecting;
    if (!up) return false;
    return p.id == widget.activeProfileId;
  }

  @override
  Widget build(BuildContext context) {
    final locked = _formLocked;
    final mq = MediaQuery.sizeOf(context);
    final maxH = mq.height * 0.92;
    final dialogW = mq.width >= 560 ? 520.0 : mq.width - 40;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: SizedBox(
        width: dialogW,
        height: maxH,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _isNew ? S.frpNewConfigTitle : S.frpEditConfigTitle,
                      style: AppTextStyles.heading(
                        size: 17,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (locked)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text(
                        S.frpRunningNoEdit,
                        style: AppTextStyles.caption(
                          size: 10,
                          color: Colors.orange,
                        ),
                      ),
                    )
                  else
                    Text(
                      S.frpAutoSave,
                      style: AppTextStyles.caption(
                        size: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 22),
                    color: AppColors.textMuted,
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: S.tooltipClose,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _editorField(
                      controller: _nameCtrl,
                      label: S.frpConfigName,
                      hint: S.frpConfigNameHint,
                      enabled: !locked,
                      onChanged: _maybePersist,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      S.frpServerSection,
                      style: AppTextStyles.caption(
                        size: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: _editorField(
                            controller: _serverAddrCtrl,
                            label: S.frpServerAddr,
                            hint: S.frpServerAddrHint,
                            enabled: !locked,
                            onChanged: _maybePersist,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _editorField(
                            controller: _serverPortCtrl,
                            label: S.frpPort,
                            hint: '7000',
                            enabled: !locked,
                            numeric: true,
                            onChanged: _maybePersist,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _editorTokenField(
                      enabled: !locked,
                      onChanged: _maybePersist,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      S.frpProxySection,
                      style: AppTextStyles.caption(
                        size: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _editorField(
                            controller: _proxyNameCtrl,
                            label: S.frpProxyName,
                            hint: 'shell',
                            enabled: !locked,
                            onChanged: _maybePersist,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _editorField(
                            controller: _remotePortCtrl,
                            label: S.frpRemotePort,
                            hint: '6000',
                            enabled: !locked,
                            numeric: true,
                            onChanged: _maybePersist,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: _editorField(
                            controller: _localAddrCtrl,
                            label: S.frpLocalAddr,
                            hint: '127.0.0.1',
                            enabled: !locked,
                            onChanged: _maybePersist,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _editorField(
                            controller: _localPortCtrl,
                            label: S.frpLocalPort,
                            hint: '4444',
                            enabled: !locked,
                            numeric: true,
                            onChanged: _maybePersist,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(
                        S.frpAdvanced,
                        style: AppTextStyles.caption(
                          size: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                      children: [
                        const SizedBox(height: 6),
                        _editorField(
                          controller: _versionCtrl,
                          label: S.frpVersionLabel,
                          hint: S.frpVersionHint,
                          enabled: !locked,
                          onChanged: _maybePersist,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Switch(
                              value: _useTcpMux,
                              onChanged: locked
                                  ? null
                                  : (v) {
                                      setState(() => _useTcpMux = v);
                                      _maybePersist();
                                    },
                              activeThumbColor: AppColors.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                S.frpTcpMux,
                                style: AppTextStyles.caption(
                                  size: 12,
                                  color: AppColors.textSecondary,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Switch(
                              value: widget.frpService.autoReconnect,
                              onChanged: (v) {
                                setState(
                                  () => widget.frpService.autoReconnect = v,
                                );
                              },
                              activeThumbColor: AppColors.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                S.frpAutoReconnect,
                                style: AppTextStyles.caption(
                                  size: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text(
                              S.frpAuthAlgorithm,
                              style: AppTextStyles.caption(
                                size: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            DropdownButton<FrpAuthMode>(
                              value: _authMode,
                              isDense: true,
                              dropdownColor: AppColors.bgCard,
                              style: AppTextStyles.terminal(
                                size: 12,
                                color: AppColors.textPrimary,
                              ),
                              onChanged: locked
                                  ? null
                                  : (v) {
                                      if (v != null) {
                                        setState(() => _authMode = v);
                                        _maybePersist();
                                      }
                                    },
                              items: [
                                DropdownMenuItem(
                                  value: FrpAuthMode.md5,
                                  child: Text(S.frpAuthMd5Label),
                                ),
                                DropdownMenuItem(
                                  value: FrpAuthMode.hmacSha1,
                                  child: Text(S.frpAuthHmacSha1Label),
                                ),
                                DropdownMenuItem(
                                  value: FrpAuthMode.hmacSha256,
                                  child: Text(S.frpAuthHmacSha256Label),
                                ),
                                DropdownMenuItem(
                                  value: FrpAuthMode.rawToken,
                                  child: Text(S.frpAuthRawTokenLabel),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _editorTokenField({bool enabled = true, VoidCallback? onChanged}) {
    return TextField(
      controller: _tokenCtrl,
      enabled: enabled,
      autocorrect: false,
      enableSuggestions: false,
      onChanged: onChanged != null ? (_) => onChanged() : null,
      style: AppTextStyles.terminal(size: 13, color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: S.frpToken,
        labelStyle: AppTextStyles.caption(size: 12, color: AppColors.textMuted),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.bgCard),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: AppColors.primary.withValues(alpha: 0.25),
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: AppColors.bgCard.withValues(alpha: 0.5),
          ),
        ),
        filled: true,
        fillColor: AppColors.bgDark,
      ),
    );
  }

  Widget _editorField({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool enabled = true,
    bool numeric = false,
    bool obscure = false,
    VoidCallback? onChanged,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      obscureText: obscure,
      keyboardType: numeric ? TextInputType.number : TextInputType.text,
      onChanged: onChanged != null ? (_) => onChanged() : null,
      style: AppTextStyles.terminal(size: 13, color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: AppTextStyles.caption(size: 12, color: AppColors.textMuted),
        hintStyle: AppTextStyles.caption(size: 12, color: AppColors.textMuted),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.bgCard),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: AppColors.primary.withValues(alpha: 0.25),
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: AppColors.bgCard.withValues(alpha: 0.5),
          ),
        ),
        filled: true,
        fillColor: AppColors.bgDark,
      ),
    );
  }
}
