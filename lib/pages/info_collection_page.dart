import 'dart:async';

import 'package:flutter/material.dart';

import '../models/project.dart';
import '../services/scan_session_service.dart';
import '../services/vulnerability_scan_background_service.dart';
import '../theme/app_theme.dart';
import '../widgets/dirsearch_card.dart';
import '../widgets/port_scan_card.dart';

/// 信息收集入口：4 种扫描类型
class InfoCollectionLandingPage extends StatelessWidget {
  final Project project;
  final VoidCallback onSwitchProject;

  const InfoCollectionLandingPage({
    super.key,
    required this.project,
    required this.onSwitchProject,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.primary.withValues(alpha: 0.2),
                        AppColors.primary.withValues(alpha: 0.08),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.4),
                      width: 1,
                    ),
                  ),
                  child: const Icon(Icons.search, color: AppColors.primary, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '信息收集 · ${project.name}',
                        style: AppTextStyles.heading(size: 13, color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        project.domain,
                        style: AppTextStyles.caption(size: 11, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: onSwitchProject,
                  icon: const Icon(Icons.swap_horiz, size: 16, color: AppColors.textSecondary),
                  label: const Text('切换项目'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 4.0,
              children: [
                _ScanTypeCard(
                  icon: Icons.network_check,
                  title: '端口扫描',
                  subtitle: 'TCP/UDP 端口探测，识别开放服务',
                  tag: 'Nmap',
                  onTap: () => _navigateTo(context, _PortScanPage(project: project)),
                ),
                _ScanTypeCard(
                  icon: Icons.folder_open,
                  title: '目录扫描',
                  subtitle: 'Web 路径爆破，发现隐藏目录与文件',
                  tag: 'dirsearch',
                  onTap: () => _navigateTo(context, _DirectoryScanPage(project: project)),
                ),
                _ScanTypeCard(
                  icon: Icons.fingerprint,
                  title: '指纹信息扫描',
                  subtitle: '识别 CMS、框架、中间件等组件',
                  tag: 'Wappalyzer',
                  onTap: () => _navigateTo(context, _FingerprintScanPage(project: project)),
                ),
                _ScanTypeCard(
                  icon: Icons.bug_report,
                  title: '漏洞扫描',
                  subtitle: '自动化漏洞检测与 PoC 验证',
                  tag: 'POC',
                  onTap: () => _navigateTo(context, _VulnerabilityScanPage(project: project)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _navigateTo(BuildContext context, Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: AppColors.bgDark,
          appBar: AppBar(
            backgroundColor: AppColors.bgElevated,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Text(
              '信息收集',
              style: AppTextStyles.heading(size: 14, color: AppColors.primary),
            ),
          ),
          body: page,
        ),
      ),
    );
  }
}

class _ScanTypeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String tag;
  final VoidCallback onTap;

  const _ScanTypeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tag,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
                ),
                child: Icon(icon, color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.heading(size: 13, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTextStyles.caption(size: 11, color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.bgElevated,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  tag,
                  style: AppTextStyles.caption(size: 10, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 目录扫描页
class _DirectoryScanPage extends StatelessWidget {
  final Project project;

  const _DirectoryScanPage({required this.project});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: DirsearchCard(
        projectId: project.id,
        initialUrl: project.domain.startsWith('http') ? project.domain : 'https://${project.domain}',
      ),
    );
  }
}

/// 端口扫描页（fscan）
class _PortScanPage extends StatelessWidget {
  final Project project;

  const _PortScanPage({required this.project});

  String _initialTarget() {
    final d = project.domain.trim();
    if (d.isEmpty) return '';
    try {
      final uri = Uri.tryParse(d);
      if (uri != null && uri.host.isNotEmpty) return uri.host;
    } catch (_) {}
    return d;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: PortScanCard(
        projectId: project.id,
        initialTarget: _initialTarget(),
      ),
    );
  }
}

/// 指纹扫描页（占位）
class _FingerprintScanPage extends StatelessWidget {
  final Project project;

  const _FingerprintScanPage({required this.project});

  @override
  Widget build(BuildContext context) {
    return _PlaceholderScanPage(
      icon: Icons.fingerprint,
      title: '指纹信息扫描',
      subtitle: 'CMS/框架识别功能开发中',
      project: project,
    );
  }
}

/// 漏洞扫描页：Shiro + ThinkPHP 检测，仅展示存在的漏洞
class _VulnerabilityScanPage extends StatefulWidget {
  final Project project;

  const _VulnerabilityScanPage({required this.project});

  @override
  State<_VulnerabilityScanPage> createState() => _VulnerabilityScanPageState();
}

class _VulnerabilityScanPageState extends State<_VulnerabilityScanPage> {
  late final TextEditingController _urlController;
  bool _running = false;
  final List<_FoundVuln> _foundVulns = [];
  int? _sessionId;
  StreamSubscription<VulnScanEvent>? _vulnSubscription;
  Timer? _pollTimer;
  final _scanSession = ScanSessionService();
  final _bgService = VulnerabilityScanBackgroundService();

  @override
  void initState() {
    super.initState();
    final initial = widget.project.domain.startsWith('http')
        ? widget.project.domain
        : 'https://${widget.project.domain}';
    _urlController = TextEditingController(text: initial);
    _loadSession();
  }

  Future<void> _loadSession() async {
    final meta = await _scanSession.loadSessionWithMeta(widget.project.id, 'vulnerability');
    if (meta != null && mounted) {
      setState(() {
        if (meta.target != null) _urlController.text = meta.target!;
        if (meta.log.isNotEmpty) {
          _foundVulns.clear();
          for (final line in meta.log.split('\n')) {
            if (line.contains('\t')) {
              final p = line.split('\t');
              if (p.length >= 3) {
                _foundVulns.add(_FoundVuln(
                  type: p[0],
                  name: p[1],
                  detail: p.sublist(2).join('\t'),
                ));
              }
            }
          }
        }
        if (meta.status == 'running') {
          _running = true;
          _sessionId = meta.id;
          _startPolling();
          _subscribeVulns();
        }
      });
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _refreshFromDb());
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _refreshFromDb() async {
    if (!mounted) return;
    final meta = await _scanSession.loadSessionWithMeta(widget.project.id, 'vulnerability');
    if (meta == null || !mounted) return;
    setState(() {
      _foundVulns.clear();
      for (final line in meta.log.split('\n')) {
        if (line.contains('\t')) {
          final p = line.split('\t');
          if (p.length >= 3) {
            _foundVulns.add(_FoundVuln(
              type: p[0],
              name: p[1],
              detail: p.sublist(2).join('\t'),
            ));
          }
        }
      }
      if (meta.status != 'running') {
        _running = false;
        _stopPolling();
      }
    });
  }

  void _subscribeVulns() {
    _vulnSubscription?.cancel();
    final sid = _sessionId;
    if (sid == null) return;
    _vulnSubscription = _bgService.vulnEvents.listen((event) {
      if (!mounted || event.sessionId != sid) return;
      setState(() => _foundVulns.add(_FoundVuln(
        type: event.type,
        name: event.name,
        detail: event.detail,
      )));
    });
  }

  @override
  void dispose() {
    _vulnSubscription?.cancel();
    _stopPolling();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _startScan() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    Uri? parsed;
    try {
      parsed = Uri.parse(url);
      if (!parsed.hasScheme) parsed = Uri.parse('https://$url');
    } catch (_) {
      return;
    }
    final baseUrl = parsed.toString();
    if (!baseUrl.startsWith('http')) return;

    try {
      _sessionId = await _bgService.startScan(
        projectId: widget.project.id,
        baseUrl: baseUrl,
      );
    } catch (e) {
      if (mounted) setState(() => _running = false);
      return;
    }

    setState(() {
      _running = true;
      _foundVulns.clear();
    });
    _startPolling();
    _subscribeVulns();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
                      ),
                      child: const Icon(Icons.bug_report, color: AppColors.primary, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        '漏洞扫描 · ${widget.project.name}',
                        style: AppTextStyles.heading(size: 14, color: AppColors.textPrimary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _urlController,
                  enabled: !_running,
                  style: AppTextStyles.body(size: 12, color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: '目标 URL',
                    hintText: 'https://target.com 或 https://target.com/login',
                    hintStyle: AppTextStyles.caption(size: 11, color: AppColors.textMuted),
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.6)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SizedBox(
                      height: 36,
                      child: ElevatedButton.icon(
                        onPressed: _running ? null : _startScan,
                        icon: _running
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.play_arrow, size: 18),
                        label: Text(_running ? '扫描中' : '开始扫描'),
                        style: ElevatedButton.styleFrom(
                          textStyle: const TextStyle(fontSize: 11),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.bgCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 3,
                        height: 14,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '发现的漏洞 (${_foundVulns.length})',
                        style: AppTextStyles.heading(size: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_foundVulns.isEmpty && !_running)
                    Expanded(
                      child: Center(
                        child: Text(
                          '点击「开始扫描」检测 Shiro、ThinkPHP 漏洞',
                          style: AppTextStyles.caption(size: 13, color: AppColors.textMuted),
                        ),
                      ),
                    )
                  else if (_foundVulns.isEmpty && _running)
                    Expanded(
                      child: Center(
                        child: Text(
                          '扫描中...',
                          style: AppTextStyles.caption(size: 13, color: AppColors.textMuted),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        itemCount: _foundVulns.length,
                        itemBuilder: (context, i) {
                          final v = _foundVulns[i];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.bgDark,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: (v.type == 'Shiro'
                                                ? Colors.orange
                                                : AppColors.primary)
                                            .withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: v.type == 'Shiro'
                                              ? Colors.orange.withValues(alpha: 0.6)
                                              : AppColors.primary.withValues(alpha: 0.6),
                                        ),
                                      ),
                                      child: Text(
                                        v.type,
                                        style: AppTextStyles.caption(
                                          size: 11,
                                          color: v.type == 'Shiro'
                                              ? Colors.orange
                                              : AppColors.primary,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        v.name,
                                        style: AppTextStyles.heading(size: 13, color: AppColors.textPrimary),
                                      ),
                                    ),
                                  ],
                                ),
                                if (v.detail.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    v.detail,
                                    style: AppTextStyles.caption(size: 11, color: AppColors.textSecondary),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FoundVuln {
  final String type;
  final String name;
  final String detail;

  _FoundVuln({required this.type, required this.name, required this.detail});
}

class _PlaceholderScanPage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Project project;

  const _PlaceholderScanPage({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.project,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: AppColors.textSecondary.withValues(alpha: 0.5)),
          const SizedBox(height: 24),
          Text(
            title,
            style: AppTextStyles.heading(size: 18, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: AppTextStyles.body(size: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            '目标: ${project.domain}',
            style: AppTextStyles.caption(size: 12, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
