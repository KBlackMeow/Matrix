import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../database/database_helper.dart';
import '../models/frp_profile.dart';
import '../services/frp_client_service.dart';
import '../services/reverse_shell_service.dart';
import '../theme/app_theme.dart';

/// FRP 客户端隧道页面
///
/// 填写服务端参数后，点击「启动隧道」即可将远端端口转发到本地的反弹 Shell 监听端口。
class FrpTunnelPage extends StatefulWidget {
  const FrpTunnelPage({super.key});

  @override
  State<FrpTunnelPage> createState() => _FrpTunnelPageState();
}

class _FrpTunnelPageState extends State<FrpTunnelPage> {
  final _frpService = FrpClientService();
  final _shellService = ReverseShellService();

  // 表单控制器
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

  final _db = DatabaseHelper();
  List<FrpProfile> _profiles = [];

  final ScrollController _logScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _serverAddrCtrl = TextEditingController();
    _serverPortCtrl = TextEditingController(text: '7000');
    _tokenCtrl = TextEditingController();
    _proxyNameCtrl = TextEditingController(text: 'shell');
    _remotePortCtrl = TextEditingController(text: '6000');
    _localAddrCtrl = TextEditingController(text: '127.0.0.1');
    // 默认本地端口跟随反弹 Shell 监听配置
    _shellService.loadConfig().then((_) {
      if (mounted) {
        _localPortCtrl.text = _shellService.lport.toString();
      }
    });
    _localPortCtrl = TextEditingController(text: _shellService.lport.toString());
    _versionCtrl = TextEditingController();

    _frpService.onChanged = () {
      if (mounted) {
        setState(() {});
        _scrollLogsToBottom();
      }
    };

    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    final list = await _db.getAllFrpProfiles();
    if (mounted) setState(() => _profiles = list);
  }

  void _applyProfile(FrpProfile p) {
    setState(() {
      _serverAddrCtrl.text = p.serverAddr;
      _serverPortCtrl.text = p.serverPort.toString();
      _tokenCtrl.text = p.token;
      _proxyNameCtrl.text = p.proxyName;
      _remotePortCtrl.text = p.remotePort.toString();
      _localAddrCtrl.text = p.localAddr;
      _localPortCtrl.text = p.localPort.toString();
      _versionCtrl.text = p.version;
      _useTcpMux = p.useTcpMux;
      _authMode = p.authMode;
    });
  }

  Future<void> _promptSaveProfile() async {
    final nameCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: Text('保存配置', style: AppTextStyles.heading(size: 16)),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          style: AppTextStyles.terminal(size: 13, color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: '配置名称',
            hintStyle: AppTextStyles.caption(size: 12, color: AppColors.textMuted),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消', style: AppTextStyles.caption(size: 13, color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('保存', style: AppTextStyles.caption(size: 13, color: AppColors.primary)),
          ),
        ],
      ),
    );
    nameCtrl.dispose();
    if (confirmed != true) return;

    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;

    final serverPort = int.tryParse(_serverPortCtrl.text.trim()) ?? 7000;
    final remotePort = int.tryParse(_remotePortCtrl.text.trim()) ?? 6000;
    final localPort = int.tryParse(_localPortCtrl.text.trim()) ?? 4444;

    await _db.createFrpProfile(
      name: name,
      serverAddr: _serverAddrCtrl.text.trim(),
      serverPort: serverPort,
      token: _tokenCtrl.text.trim(),
      proxyName: _proxyNameCtrl.text.trim(),
      remotePort: remotePort,
      localAddr: _localAddrCtrl.text.trim().isEmpty ? '127.0.0.1' : _localAddrCtrl.text.trim(),
      localPort: localPort,
      version: _versionCtrl.text.trim(),
      useTcpMux: _useTcpMux,
      authMode: _authMode,
    );
    await _loadProfiles();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已保存「$name」'), duration: const Duration(seconds: 2)),
      );
    }
  }

  Future<void> _deleteProfile(FrpProfile p) async {
    await _db.deleteFrpProfile(p.id);
    await _loadProfiles();
  }

  @override
  void dispose() {
    _serverAddrCtrl.dispose();
    _serverPortCtrl.dispose();
    _tokenCtrl.dispose();
    _proxyNameCtrl.dispose();
    _remotePortCtrl.dispose();
    _localAddrCtrl.dispose();
    _localPortCtrl.dispose();
    _versionCtrl.dispose();
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

  Future<void> _toggleTunnel() async {
    if (_frpService.status == FrpTunnelStatus.running ||
        _frpService.status == FrpTunnelStatus.connecting) {
      await _frpService.stop();
      return;
    }

    final serverAddr = _serverAddrCtrl.text.trim();
    final serverPort = int.tryParse(_serverPortCtrl.text.trim());
    final remotePort = int.tryParse(_remotePortCtrl.text.trim());
    final localPort = int.tryParse(_localPortCtrl.text.trim());
    final proxyName = _proxyNameCtrl.text.trim();
    final localAddr = _localAddrCtrl.text.trim();

    if (serverAddr.isEmpty ||
        serverPort == null ||
        remotePort == null ||
        localPort == null ||
        proxyName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写完整参数')),
      );
      return;
    }

    final config = FrpTunnelConfig(
      serverAddr: serverAddr,
      serverPort: serverPort,
      token: _tokenCtrl.text.trim(),
      proxyName: proxyName,
      remotePort: remotePort,
      localAddr: localAddr.isEmpty ? '127.0.0.1' : localAddr,
      localPort: localPort,
      version: _versionCtrl.text.trim(),
      useTcpMux: _useTcpMux,
      authMode: _authMode,
    );

    await _frpService.start(config);
  }

  @override
  Widget build(BuildContext context) {
    final status = _frpService.status;
    final isActive = status == FrpTunnelStatus.running ||
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
                    constraints: BoxConstraints(minWidth: 280),
                    child: _buildConfigColumn(status, isActive),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 1,
                child: _buildLogSection(),
              ),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
        // ---- 头部信息卡 ----
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
              Icon(Icons.alt_route, color: _statusColor(status), size: 32),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'FRP 隧道客户端',
                      style: AppTextStyles.heading(
                          size: 18, color: _statusColor(status)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _statusLabel(status),
                      style: AppTextStyles.caption(
                          size: 13, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              // 保存配置按钮
              IconButton(
                tooltip: '保存当前配置',
                icon: const Icon(Icons.bookmark_add_outlined, size: 20),
                color: AppColors.textMuted,
                onPressed: isActive ? null : _promptSaveProfile,
              ),
              const SizedBox(width: 4),
              // 状态指示灯
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _statusColor(status),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: _statusColor(status).withValues(alpha: 0.6),
                            blurRadius: 8,
                          )
                        ]
                      : null,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ---- 已保存配置 ----
        if (_profiles.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('已保存配置',
                    style: AppTextStyles.caption(
                        size: 12, color: AppColors.textMuted)),
                const SizedBox(height: 8),
                ...List.generate(_profiles.length, (i) {
                  final p = _profiles[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.bookmark_outline,
                            size: 14, color: AppColors.textMuted),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(p.name,
                                  style: AppTextStyles.terminal(
                                      size: 12,
                                      color: AppColors.textPrimary),
                                  overflow: TextOverflow.ellipsis),
                              Text(
                                '${p.serverAddr}:${p.serverPort}  →  ${p.localAddr}:${p.localPort}',
                                style: AppTextStyles.caption(
                                    size: 11,
                                    color: AppColors.textMuted),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(40, 28),
                              tapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap),
                          onPressed:
                              isActive ? null : () => _applyProfile(p),
                          child: Text('加载',
                              style: AppTextStyles.caption(
                                  size: 11, color: AppColors.primary)),
                        ),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () => _deleteProfile(p),
                          child: const Icon(Icons.close,
                              size: 14, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),

        if (_profiles.isNotEmpty) const SizedBox(height: 16),

        // ---- 参数表单 ----
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('服务端配置',
                  style: AppTextStyles.caption(
                      size: 12, color: AppColors.textMuted)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: _field(
                      controller: _serverAddrCtrl,
                      label: 'frp 服务器地址',
                      hint: '例如 1.2.3.4',
                      enabled: !isActive,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _field(
                      controller: _serverPortCtrl,
                      label: '端口',
                      hint: '7000',
                      enabled: !isActive,
                      numeric: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _tokenField(enabled: !isActive),
              const SizedBox(height: 16),
              Text('代理配置',
                  style: AppTextStyles.caption(
                      size: 12, color: AppColors.textMuted)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _field(
                      controller: _proxyNameCtrl,
                      label: '代理名称',
                      hint: 'shell',
                      enabled: !isActive,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _field(
                      controller: _remotePortCtrl,
                      label: '远端端口',
                      hint: '6000',
                      enabled: !isActive,
                      numeric: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: _field(
                      controller: _localAddrCtrl,
                      label: '本地地址',
                      hint: '127.0.0.1',
                      enabled: !isActive,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _field(
                      controller: _localPortCtrl,
                      label: '本地端口',
                      hint: '4444',
                      enabled: !isActive,
                      numeric: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // 高级选项
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                dense: true,
                title: Text('高级选项',
                    style: AppTextStyles.caption(
                        size: 12, color: AppColors.textMuted)),
                children: [
                  const SizedBox(height: 6),
                  _field(
                    controller: _versionCtrl,
                    label: '客户端版本号（留空则不携带）',
                    hint: '例如 0.51.3 / 0.61.1',
                    enabled: !isActive,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Switch(
                        value: _useTcpMux,
                        onChanged: isActive
                            ? null
                            : (v) => setState(() => _useTcpMux = v),
                        activeThumbColor: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'TCPMux（yamux 多路复用，frp 默认开启，关闭则退回直连模式）',
                          style: AppTextStyles.caption(
                              size: 12, color: AppColors.textSecondary),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Switch(
                        value: _frpService.autoReconnect,
                        onChanged: (v) =>
                            setState(() => _frpService.autoReconnect = v),
                        activeThumbColor: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '断开后自动重连（5 秒后重试）',
                          style: AppTextStyles.caption(
                              size: 12, color: AppColors.textSecondary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text('认证算法：',
                          style: AppTextStyles.caption(
                              size: 12, color: AppColors.textSecondary)),
                      const SizedBox(width: 8),
                      DropdownButton<FrpAuthMode>(
                        value: _authMode,
                        isDense: true,
                        dropdownColor: AppColors.bgCard,
                        style: AppTextStyles.terminal(
                            size: 12, color: AppColors.textPrimary),
                        onChanged: isActive
                            ? null
                            : (v) {
                                if (v != null) setState(() => _authMode = v);
                              },
                        items: const [
                          DropdownMenuItem(
                              value: FrpAuthMode.md5,
                              child: Text('MD5 (官方默认)')),
                          DropdownMenuItem(
                              value: FrpAuthMode.hmacSha1,
                              child: Text('HMAC-SHA1')),
                          DropdownMenuItem(
                              value: FrpAuthMode.hmacSha256,
                              child: Text('HMAC-SHA256')),
                          DropdownMenuItem(
                              value: FrpAuthMode.rawToken,
                              child: Text('Raw Token')),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 启动/停止按钮
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: status == FrpTunnelStatus.connecting
                      ? null
                      : _toggleTunnel,
                  icon: Icon(
                    isActive ? Icons.stop : Icons.play_arrow,
                    size: 18,
                  ),
                  label: Text(_buttonLabel(status)),
                  style: FilledButton.styleFrom(
                    backgroundColor: isActive
                        ? AppColors.red.withValues(alpha: 0.8)
                        : AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
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
                    const Icon(Icons.terminal,
                        size: 14, color: AppColors.textMuted),
                    const SizedBox(width: 6),
                    Text('运行日志',
                        style: AppTextStyles.caption(
                            size: 12, color: AppColors.textMuted)),
                    const Spacer(),
                    if (_frpService.logs.isNotEmpty) ...[
                      GestureDetector(
                        onTap: () async {
                          final text = _frpService.logs.join('\n');
                          await Clipboard.setData(ClipboardData(text: text));
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('日志已复制到剪贴板'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        child: Text('复制',
                            style: AppTextStyles.caption(
                                size: 11, color: AppColors.primary)),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: () => setState(() => _frpService.logs),
                        child: Text('清空',
                            style: AppTextStyles.caption(
                                size: 11, color: AppColors.textMuted)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _frpService.logs.isEmpty
                      ? Center(
                          child: Text(
                            '> 尚无日志',
                            style: AppTextStyles.terminal(
                                size: 13, color: AppColors.textMuted),
                          ),
                        )
                      : ListView.builder(
                          controller: _logScroll,
                          itemCount: _frpService.logs.length,
                          itemBuilder: (context, i) {
                            final line = _frpService.logs[i];
                            final isError = line.contains('失败') ||
                                line.contains('错误') ||
                                line.contains('断开');
                            final isOk = line.contains('成功') ||
                                line.contains('就绪') ||
                                line.contains('桥接');
                            final color = isError
                                ? AppColors.red
                                : isOk
                                    ? AppColors.primary
                                    : AppColors.textSecondary;
                            return Text(
                              line,
                              style: AppTextStyles.terminal(
                                  size: 12, color: color),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
  }

  /// Token 专用输入框：明文显示 + 禁用自动更正/智能标点，避免 macOS IME 替换字符
  Widget _tokenField({bool enabled = true}) {
    return TextField(
      controller: _tokenCtrl,
      enabled: enabled,
      autocorrect: false,
      enableSuggestions: false,
      style: AppTextStyles.terminal(size: 13, color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: 'Token（可留空）',
        labelStyle: AppTextStyles.caption(size: 12, color: AppColors.textMuted),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.bgCard),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              BorderSide(color: AppColors.primary.withValues(alpha: 0.25)),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              BorderSide(color: AppColors.bgCard.withValues(alpha: 0.5)),
        ),
        filled: true,
        fillColor: AppColors.bgDark,
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool enabled = true,
    bool numeric = false,
    bool obscure = false,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      obscureText: obscure,
      keyboardType: numeric ? TextInputType.number : TextInputType.text,
      style: AppTextStyles.terminal(size: 13, color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: AppTextStyles.caption(size: 12, color: AppColors.textMuted),
        hintStyle: AppTextStyles.caption(size: 12, color: AppColors.textMuted),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.bgCard),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
              color: AppColors.primary.withValues(alpha: 0.25)),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.bgCard.withValues(alpha: 0.5)),
        ),
        filled: true,
        fillColor: AppColors.bgDark,
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
        return '隧道运行中 · 远端流量将转发到本地';
      case FrpTunnelStatus.connecting:
        return '正在连接...';
      case FrpTunnelStatus.error:
        return '连接出错，请检查参数或日志';
      case FrpTunnelStatus.idle:
        return '就绪 · 填写参数后启动隧道';
    }
  }

  String _buttonLabel(FrpTunnelStatus s) {
    switch (s) {
      case FrpTunnelStatus.running:
        return '停止隧道';
      case FrpTunnelStatus.connecting:
        return '连接中...';
      case FrpTunnelStatus.error:
      case FrpTunnelStatus.idle:
        return '启动隧道';
    }
  }
}
