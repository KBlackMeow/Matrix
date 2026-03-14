import 'dart:async';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../services/fscan_service.dart';
import '../services/port_scan_background_service.dart';
import '../services/scan_session_service.dart';
import '../theme/app_theme.dart';

/// 纯 Dart 实现的端口扫描（复刻 fscan 端口扫描功能，无需外部二进制）
/// 支持后台运行、结果自动保存、退出再进入恢复状态
class PortScanCard extends StatefulWidget {
  final int? projectId;
  final String? initialTarget;

  const PortScanCard({super.key, this.projectId, this.initialTarget});

  @override
  State<PortScanCard> createState() => _PortScanCardState();
}

class _PortScanCardState extends State<PortScanCard> {
  final _targetController = TextEditingController();
  final _portsController = TextEditingController();
  final _timeoutController = TextEditingController();
  final _threadsController = TextEditingController();
  final _logScrollController = ScrollController();

  String _log = '';
  bool _running = false;
  bool _enableProbe = true;
  bool _skipPing = true;
  bool _enableNetbios = false;
  bool _enableMs17010 = false;
  bool _enableBrute = false;

  int? _sessionId;
  StreamSubscription<PortScanLogEvent>? _logSubscription;
  Timer? _pollTimer;
  final _scanSession = ScanSessionService();
  final _bgService = PortScanBackgroundService();

  @override
  void initState() {
    super.initState();
    _portsController.text = '1-10000';
    _timeoutController.text = '3';
    _threadsController.text = '200';
    if (widget.initialTarget != null) _targetController.text = widget.initialTarget!;
    _loadSession();
  }

  Future<void> _loadSession() async {
    if (widget.projectId == null) return;
    final meta = await _scanSession.loadSessionWithMeta(widget.projectId!, 'port_scan');
    if (meta != null && mounted) {
      setState(() {
        _log = meta.log;
        if (meta.target != null) _targetController.text = meta.target!;
        if (meta.config != null) {
          try {
            final cfg = jsonDecode(meta.config!) as Map<String, dynamic>;
            if (cfg['ports'] != null) _portsController.text = cfg['ports'].toString();
            if (cfg['timeout'] != null) _timeoutController.text = cfg['timeout'].toString();
            if (cfg['threads'] != null) _threadsController.text = cfg['threads'].toString();
          } catch (_) {}
        }
        if (meta.status == 'running') {
          _running = true;
          _sessionId = meta.id;
          _startPolling();
          _subscribeLog();
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
    if (widget.projectId == null || !mounted) return;
    final meta = await _scanSession.loadSessionWithMeta(widget.projectId!, 'port_scan');
    if (meta == null || !mounted) return;
    setState(() {
      _log = meta.log;
      if (meta.status != 'running') {
        _running = false;
        _stopPolling();
      }
    });
  }

  void _subscribeLog() {
    _logSubscription?.cancel();
    final sid = _sessionId;
    if (sid == null) return;
    _logSubscription = _bgService.logEvents.listen((event) {
      if (!mounted || event.sessionId != sid) return;
      setState(() {
        final existing = _log.isEmpty ? <String>[] : _log.split('\n');
        existing.add(event.line);
        const maxLines = 500;
        final trimmed = existing.length > maxLines
            ? existing.sublist(existing.length - maxLines)
            : existing;
        _log = trimmed.join('\n');
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _logScrollController.hasClients) {
          _logScrollController.animateTo(
            _logScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 80),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }

  void _appendLogLocal(String line) {
    if (!mounted) return;
    setState(() {
      final existing = _log.isEmpty ? <String>[] : _log.split('\n');
      existing.add(line);
      const maxLines = 500;
      final trimmed = existing.length > maxLines
          ? existing.sublist(existing.length - maxLines)
          : existing;
      _log = trimmed.join('\n');
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 80),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _logSubscription?.cancel();
    _stopPolling();
    _targetController.dispose();
    _portsController.dispose();
    _timeoutController.dispose();
    _threadsController.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  Future<void> _startScan() async {
    final target = _targetController.text.trim();
    if (target.isEmpty) {
      _appendLogLocal('[!] 请输入目标 IP 或域名');
      return;
    }

    if (widget.projectId == null) {
      _appendLogLocal('[!] 需要项目上下文以支持后台扫描');
      return;
    }

    try {
      _sessionId = await _bgService.startScan(
        projectId: widget.projectId!,
        target: target,
        portsStr: _portsController.text.trim(),
        timeoutSec: int.tryParse(_timeoutController.text.trim()) ?? 3,
        threads: int.tryParse(_threadsController.text.trim()) ?? 200,
        skipPing: _skipPing,
        enableProbe: _enableProbe,
        enableNetbios: _enableNetbios,
        enableMs17010: _enableMs17010,
        enableBrute: _enableBrute,
      );
    } catch (e) {
      _appendLogLocal('[!] 启动失败: $e');
      return;
    }

    setState(() {
      _running = true;
      _log = '';
    });
    _startPolling();
    _subscribeLog();
  }

  void _stopScan() {
    if (_sessionId != null) {
      _bgService.cancelSession(_sessionId!);
    }
  }

  /// 日志行样式：重要信息凸显
  TextStyle _logLineStyle(String line) {
    final base = AppTextStyles.terminal(size: 12);
    final trimmed = line.trim();

    // 高危：警告、MS17-010
    if (trimmed.contains('[!]') || (trimmed.contains('MS17-010') && trimmed.contains('可能存在'))) {
      return base.copyWith(color: AppColors.red, fontWeight: FontWeight.w600);
    }

    // 漏洞：目标、漏洞类型、爆破成功（琥珀色加粗）
    if (trimmed.contains('爆破成功') ||
        (trimmed.contains('[SUCCESS]') && trimmed.contains('目标:')) ||
        trimmed.contains('漏洞类型:') ||
        trimmed.contains('poc-yaml-')) {
      return base.copyWith(color: AppColors.amber, fontWeight: FontWeight.w600);
    }

    // 成功发现：端口开放、服务识别、网站标题、NetBIOS
    if (trimmed.contains('[SUCCESS]')) {
      if (trimmed.contains('端口开放') ||
          trimmed.contains('服务识别') ||
          trimmed.contains('网站标题') ||
          trimmed.contains('NetBIOS')) {
        return base.copyWith(color: AppColors.cyan, fontWeight: FontWeight.w500);
      }
      return base.copyWith(color: AppColors.primary);
    }

    // 信息
    if (trimmed.contains('[INFO]')) {
      return base.copyWith(color: AppColors.textSecondary);
    }

    // POC 详情行（缩进，次要信息）
    if (trimmed.startsWith('  详细信息:') || trimmed.startsWith('        ')) {
      return base.copyWith(color: AppColors.textSecondary, fontSize: 11);
    }

    return base.copyWith(color: AppColors.textSecondary);
  }

  InputDecoration _inputDecoration(String label, String hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
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
    );
  }

  Widget _buildCheckRow(String label, bool value, void Function(bool) onChanged) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(
          value: value,
          onChanged: _running ? null : (v) => setState(() => onChanged(v ?? false)),
          activeColor: AppColors.primary,
          fillColor: WidgetStateProperty.resolveWith(
            (_) => AppColors.primary.withValues(alpha: 0.3),
          ),
        ),
        Text(label, style: AppTextStyles.body(size: 11, color: AppColors.textPrimary)),
      ],
    );
  }

  Future<void> _saveResult() async {
    if (_log.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final location = await getSaveLocation(suggestedName: 'fscan_result_${DateTime.now().millisecondsSinceEpoch}.txt');
      if (location == null) return;
      await FscanService.exportToFile(location.path, _log);
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('已保存到 ${location.path}'), duration: const Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('保存失败: $e'), duration: const Duration(seconds: 2)),
        );
      }
    }
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
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
          Text(title, style: AppTextStyles.heading(size: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.network_check, color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                '端口扫描',
                style: AppTextStyles.heading(size: 14, color: AppColors.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Flexible(
                  flex: 1,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _sectionTitle('目标配置'),
                        TextField(
                          controller: _targetController,
                          enabled: !_running,
                          style: AppTextStyles.body(size: 12, color: AppColors.textPrimary),
                          decoration: _inputDecoration('目标 IP/域名', '192.168.1.1 或 192.168.1.0/24'),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _portsController,
                          enabled: !_running,
                          style: AppTextStyles.body(size: 12, color: AppColors.textPrimary),
                          decoration: _inputDecoration(
                            '端口',
                            '21,22,80,443 或 1-1000，空则用默认',
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            _buildCheckRow('跳过存活探测', _skipPing, (v) => _skipPing = v),
                            _buildCheckRow('服务探测', _enableProbe, (v) => _enableProbe = v),
                            _buildCheckRow('NetBIOS', _enableNetbios, (v) => _enableNetbios = v),
                            _buildCheckRow('MS17-010', _enableMs17010, (v) => _enableMs17010 = v),
                            _buildCheckRow('密码爆破', _enableBrute, (v) => _enableBrute = v),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _timeoutController,
                                enabled: !_running,
                                keyboardType: TextInputType.number,
                                style: AppTextStyles.body(size: 12, color: AppColors.textPrimary),
                                decoration: _inputDecoration('超时(s)', '3'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _threadsController,
                                enabled: !_running,
                                keyboardType: TextInputType.number,
                                style: AppTextStyles.body(size: 12, color: AppColors.textPrimary),
                                decoration: _inputDecoration('线程数', '200'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _sectionTitle('操作'),
                        Row(
                          children: [
                            SizedBox(
                              height: 32,
                              child: ElevatedButton.icon(
                                onPressed: _running ? null : _startScan,
                                icon: const Icon(Icons.play_arrow, size: 16),
                                label: const Text('开始'),
                                style: ElevatedButton.styleFrom(
                                  textStyle: const TextStyle(fontSize: 11),
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              height: 32,
                              child: OutlinedButton.icon(
                                onPressed: _running ? _stopScan : null,
                                icon: const Icon(Icons.stop, size: 16),
                                label: const Text('停止'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.primary,
                                  side: BorderSide(color: AppColors.primary.withValues(alpha: 0.6)),
                                  textStyle: const TextStyle(fontSize: 11),
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Flexible(
                  flex: 1,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.bgDark,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _running ? AppColors.primary : AppColors.textMuted,
                              ),
                            ),
                            Text(
                              _running ? '扫描中' : '空闲',
                              style: AppTextStyles.caption(
                                size: 11,
                                color: _running ? AppColors.primary : AppColors.textSecondary,
                              ),
                            ),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: _log.isEmpty ? null : _saveResult,
                              icon: const Icon(Icons.save, size: 14),
                              label: const Text('保存'),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.textSecondary,
                                textStyle: const TextStyle(fontSize: 11),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _log.isEmpty
                                  ? null
                                  : () async {
                                      final messenger = ScaffoldMessenger.of(context);
                                      await Clipboard.setData(ClipboardData(text: _log));
                                      if (mounted) {
                                        messenger.showSnackBar(
                                          const SnackBar(
                                            content: Text('已复制到剪贴板'),
                                            duration: Duration(seconds: 1),
                                          ),
                                        );
                                      }
                                    },
                              icon: const Icon(Icons.copy, size: 14),
                              label: const Text('复制'),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.textSecondary,
                                textStyle: const TextStyle(fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 1, color: AppColors.border),
                        const SizedBox(height: 4),
                        Expanded(
                          child: _log.isEmpty
                              ? Center(
                                  child: Text(
                                    _running ? '扫描中...' : '结果将显示在此处',
                                    style: AppTextStyles.caption(size: 12, color: AppColors.textMuted),
                                  ),
                                )
                              : SelectionArea(
                                  child: ListView.builder(
                                    controller: _logScrollController,
                                    shrinkWrap: true,
                                    itemCount: _log.split('\n').length,
                                    itemBuilder: (context, i) {
                                      final line = _log.split('\n')[i];
                                      final t = line.trim();
                                      final isPocBlock = t.startsWith('目标:') ||
                                          t.startsWith('漏洞类型:') ||
                                          t.startsWith('漏洞名称:') ||
                                          t.startsWith('详细信息:') ||
                                          (line.startsWith('        ') && t.isNotEmpty);
                                      return Container(
                                        width: double.infinity,
                                        padding: isPocBlock
                                            ? const EdgeInsets.only(left: 8, top: 2, bottom: 2)
                                            : null,
                                        decoration: isPocBlock
                                            ? BoxDecoration(
                                                border: Border(
                                                  left: BorderSide(
                                                    color: AppColors.amber.withValues(alpha: 0.6),
                                                    width: 3,
                                                  ),
                                                ),
                                                color: AppColors.amber.withValues(alpha: 0.06),
                                              )
                                            : null,
                                        child: SelectableText(
                                          line,
                                          style: _logLineStyle(line),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                        ),
                      ],
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
}
