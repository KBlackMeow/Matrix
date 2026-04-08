import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../services/dirsearch_service.dart';
import '../services/dirscan_background_service.dart';
import '../services/scan_session_service.dart';
import '../theme/app_theme.dart';

/// 复刻 [dirsearch](https://github.com/maurosoria/dirsearch) 的路径爆破 UI
/// 支持后台运行、结果自动保存、退出再进入恢复状态
class DirsearchCard extends StatefulWidget {
  final int? projectId;
  final String? initialUrl;

  const DirsearchCard({super.key, this.projectId, this.initialUrl});

  @override
  State<DirsearchCard> createState() => _DirsearchCardState();
}

class _DirsearchCardState extends State<DirsearchCard> {
  final _urlController = TextEditingController();
  final _extensionsController = TextEditingController();
  final _threadsController = TextEditingController();
  final _timeoutController = TextEditingController();
  final _statusIncludeController = TextEditingController();
  final _maxRecurseDepthController = TextEditingController();
  final _resultsScrollController = ScrollController();

  List<DirsearchResult> _results = [];
  String _statusMessage = '';
  int _progressCurrent = 0;
  int _progressTotal = 0;
  bool _running = false;
  bool _recursiveScan = true;
  // 递归模式：'standard' | 'deep' | 'force'
  String _recursiveMode = 'standard';

  int? _sessionId;
  StreamSubscription<DirscanProgress>? _progressSubscription;
  StreamSubscription<DirscanFoundEvent>? _foundSubscription;
  Timer? _pollTimer;
  final _scanSession = ScanSessionService();
  final _bgService = DirscanBackgroundService();
  final Set<String> _resultKeys = <String>{};

  @override
  void initState() {
    super.initState();
    if (widget.initialUrl != null) _urlController.text = widget.initialUrl!;
    _loadSession();
  }

  Future<void> _loadSession() async {
    if (widget.projectId == null) return;
    final meta = await _scanSession.loadSessionWithMeta(widget.projectId!, 'dir_scan');
    if (meta != null && mounted) {
      setState(() {
        if (meta.target != null) _urlController.text = meta.target!;
        if (meta.log.isNotEmpty) {
          _results = _parseResultsFromLog(meta.log);
          _rebuildResultKeys();
        }
        if (meta.status == 'running') {
          _running = true;
          _sessionId = meta.id;
          _startPolling();
          _subscribeProgress();
          _subscribeFound();
        }
      });
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _refreshFromDb());
  }

  void _subscribeProgress() {
    _progressSubscription?.cancel();
    final sid = _sessionId;
    if (sid == null) return;
    _progressSubscription = _bgService.progress.listen((p) {
      if (!mounted || p.sessionId != sid) return;
      setState(() {
        _progressCurrent = p.current;
        _progressTotal = p.total;
        if (p.status == 'completed' || p.status == 'cancelled') {
          _running = false;
          _stopPolling();
          _setStatus(p.status == 'cancelled'
              ? '已取消'
              : '扫描完成，发现 ${p.resultsCount} 个有效路径');
        } else if (p.status == 'error') {
          _running = false;
          _stopPolling();
          _setStatus('[!] ${p.message ?? "异常"}');
        } else if (p.status == 'empty_dict') {
          _running = false;
          _stopPolling();
          _setStatus('[!] 字典为空或加载失败');
        }
      });
      if (p.status == 'completed' || p.status == 'cancelled') {
        _refreshFromDb();
      }
    });
  }

  void _subscribeFound() {
    _foundSubscription?.cancel();
    final sid = _sessionId;
    if (sid == null) return;
    _foundSubscription = _bgService.foundEvents.listen((event) {
      if (!mounted || event.sessionId != sid) return;
      final key = _resultKey(event.result);
      if (_resultKeys.contains(key)) return;
      setState(() {
        _results.add(event.result);
        _resultKeys.add(key);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_resultsScrollController.hasClients) return;
        _resultsScrollController.jumpTo(_resultsScrollController.position.maxScrollExtent);
      });
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _refreshFromDb() async {
    if (widget.projectId == null || !mounted) return;
    final meta = await _scanSession.loadSessionWithMeta(widget.projectId!, 'dir_scan');
    if (meta == null || !mounted) return;
    setState(() {
      _results = _parseResultsFromLog(meta.log);
      _rebuildResultKeys();
      if (meta.status != 'running') {
        _running = false;
        _stopPolling();
      }
    });
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    _foundSubscription?.cancel();
    _stopPolling();
    _urlController.dispose();
    _extensionsController.dispose();
    _threadsController.dispose();
    _timeoutController.dispose();
    _statusIncludeController.dispose();
    _maxRecurseDepthController.dispose();
    _resultsScrollController.dispose();
    super.dispose();
  }

  Future<void> _clearResults() async {
    setState(() {
      _results = [];
      _resultKeys.clear();
      _statusMessage = '';
      _progressCurrent = 0;
      _progressTotal = 0;
    });
    if (_sessionId != null) {
      await _scanSession.clearSessionLog(_sessionId!);
    }
  }

  void _setStatus(String msg) {
    if (mounted) setState(() => _statusMessage = msg);
  }

  Future<void> _startScan() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      _setStatus('[!] 请输入目标 URL');
      return;
    }
    Uri? parsed;
    try {
      parsed = Uri.parse(url);
      if (!parsed.hasScheme) parsed = Uri.parse('https://$url');
    } catch (_) {
      _setStatus('[!] URL 格式错误');
      return;
    }

    final baseUrl = parsed.toString();
    if (!baseUrl.startsWith('http')) {
      _setStatus('[!] 请使用 http:// 或 https://');
      return;
    }

    if (widget.projectId == null) {
      _setStatus('[!] 需要项目上下文以支持后台扫描');
      return;
    }

    _setStatus('加载字典...');
    final extStr = _extensionsController.text.trim();
    final defaultExt = 'php,html,js,txt,asp,aspx,jsp';
    final extensions = extStr.isEmpty
        ? defaultExt.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()
        : extStr
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();

    final threads = int.tryParse(_threadsController.text.trim()) ?? 5;
    final timeoutSec = int.tryParse(_timeoutController.text.trim()) ?? 8;
    final statusStr = _statusIncludeController.text.trim();
    final defaultStatus = '200,201,301,302,401,403';
    final statusCodes = statusStr.isEmpty
        ? defaultStatus.split(',').map((e) => int.tryParse(e.trim())).whereType<int>().toSet()
        : statusStr
              .split(',')
              .map((e) => int.tryParse(e.trim()))
              .whereType<int>()
              .toSet();
    if (statusCodes.isEmpty) statusCodes.addAll([200, 301, 302, 401, 403]);

    final maxRecurseDepth =
        (int.tryParse(_maxRecurseDepthController.text.trim()) ?? 0).clamp(0, 10);

    try {
      _sessionId = await _bgService.startScan(
        projectId: widget.projectId!,
        baseUrl: baseUrl,
        extensions: extensions,
        threads: threads,
        timeoutSec: timeoutSec,
        statusCodes: statusCodes,
        recursiveScan: _recursiveScan,
        deepRecursive: _recursiveMode == 'deep',
        forceRecursive: _recursiveMode == 'force',
        maxRecurseDepth: maxRecurseDepth,
        recursionStatusCodes: const {200, 301, 302},
      );
    } catch (e) {
      _setStatus('[!] 启动失败: $e');
      return;
    }

    setState(() {
      _running = true;
      _results = [];
      _resultKeys.clear();
      _statusMessage = '后台扫描已启动，离开页面后继续运行';
      _progressCurrent = 0;
      _progressTotal = 0;
    });
    _startPolling();
    _subscribeProgress();
    _subscribeFound();
  }

  void _stopScan() {
    if (_sessionId != null) {
      _bgService.cancelSession(_sessionId!);
    }
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  List<DirsearchResult> _parseResultsFromLog(String log) {
    return log
        .split('\n')
        .where((l) => l.contains('|'))
        .map((l) {
          final p = l.split('|');
          if (p.length >= 3) {
            return DirsearchResult(
              path: p[0],
              statusCode: int.tryParse(p[1]) ?? 0,
              contentLength: int.tryParse(p[2]) ?? 0,
            );
          }
          return null;
        })
        .whereType<DirsearchResult>()
        .toList();
  }

  String _resultKey(DirsearchResult r) => '${r.path}|${r.statusCode}|${r.contentLength}';

  void _rebuildResultKeys() {
    _resultKeys
      ..clear()
      ..addAll(_results.map(_resultKey));
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
                child: const Icon(Icons.folder_open, color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                'Web 路径扫描 (dirsearch)',
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
                          controller: _urlController,
                          style: AppTextStyles.body(size: 12, color: AppColors.textPrimary),
                          decoration: _inputDecoration('目标 URL', 'https://target.com'),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _extensionsController,
                                style: AppTextStyles.body(size: 12, color: AppColors.textPrimary),
                                decoration: _inputDecoration('扩展名', 'php,html,js,txt,asp,aspx,jsp'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _threadsController,
                                keyboardType: TextInputType.number,
                                style: AppTextStyles.body(size: 12, color: AppColors.textPrimary),
                                decoration: _inputDecoration('线程', '5'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _timeoutController,
                                keyboardType: TextInputType.number,
                                style: AppTextStyles.body(size: 12, color: AppColors.textPrimary),
                                decoration: _inputDecoration('超时', '8'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _statusIncludeController,
                          style: AppTextStyles.body(size: 12, color: AppColors.textPrimary),
                          decoration: _inputDecoration('包含状态码', '200,201,301,302,401,403'),
                        ),
                        const SizedBox(height: 8),
                        // ── 递归开关 + 深度 ────────────────────────────────
                        Row(
                          children: [
                            Checkbox(
                              value: _recursiveScan,
                              onChanged: _running
                                  ? null
                                  : (v) => setState(() => _recursiveScan = v ?? true),
                              activeColor: AppColors.primary,
                              fillColor: WidgetStateProperty.resolveWith(
                                (_) => AppColors.primary.withValues(alpha: 0.3),
                              ),
                            ),
                            Text('递归扫描  深度',
                                style: AppTextStyles.body(size: 12, color: AppColors.textPrimary)),
                            const SizedBox(width: 6),
                            SizedBox(
                              width: 48,
                              child: TextField(
                                controller: _maxRecurseDepthController,
                                enabled: !_running && _recursiveScan,
                                keyboardType: TextInputType.number,
                                style: AppTextStyles.body(size: 12, color: AppColors.textPrimary),
                                decoration: _inputDecoration('', '0'),
                              ),
                            ),
                          ],
                        ),
                        // ── 递归模式选择（仅递归开启时可用）─────────────────
                        if (_recursiveScan) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const SizedBox(width: 4),
                              Text('模式：',
                                  style: AppTextStyles.caption(
                                      size: 11, color: AppColors.textSecondary)),
                              const SizedBox(width: 6),
                              SegmentedButton<String>(
                                segments: const [
                                  ButtonSegment(value: 'standard', label: Text('标准')),
                                  ButtonSegment(value: 'deep',     label: Text('深度')),
                                  ButtonSegment(value: 'force',    label: Text('强制')),
                                ],
                                selected: {_recursiveMode},
                                onSelectionChanged: _running
                                    ? null
                                    : (v) => setState(
                                        () => _recursiveMode = v.first),
                                style: ButtonStyle(
                                  textStyle: WidgetStateProperty.all(
                                      const TextStyle(fontSize: 11)),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            ],
                          ),
                        ],
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
                            Text(
                              _progressTotal > 0 ? '$_progressCurrent / $_progressTotal' : '等待扫描',
                              style: AppTextStyles.caption(size: 11, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                        const Divider(height: 1, color: AppColors.border),
                        const SizedBox(height: 4),
                        if (_statusMessage.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: SelectableText(
                              _statusMessage,
                              style: AppTextStyles.caption(size: 11, color: AppColors.textMuted),
                              maxLines: 2,
                            ),
                          ),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _progressTotal > 0 ? _progressCurrent / _progressTotal : 0.0,
                            minHeight: 6,
                            backgroundColor: AppColors.border,
                            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Container(
                              width: 3,
                              height: 14,
                              decoration: BoxDecoration(
                                color: AppColors.cyan.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '发现 (${_results.length})',
                              style: AppTextStyles.heading(size: 12, color: AppColors.textSecondary),
                            ),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: (_running || _results.isEmpty) ? null : _clearResults,
                              icon: const Icon(Icons.delete_outline, size: 14),
                              label: const Text('清空'),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.red,
                                textStyle: const TextStyle(fontSize: 11),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _results.isEmpty
                                  ? null
                                  : () async {
                                      final text = _results
                                          .map((r) => '${r.statusCode}  ${_fmtSize(r.contentLength)}  ${r.path}')
                                          .join('\n');
                                      final messenger = ScaffoldMessenger.of(context);
                                      await Clipboard.setData(ClipboardData(text: text));
                                      if (mounted) {
                                        messenger.showSnackBar(
                                          const SnackBar(content: Text('已复制到剪贴板'), duration: Duration(seconds: 1)),
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
                        const SizedBox(height: 6),
                        Expanded(
                          child: _results.isEmpty
                              ? Center(
                                  child: Text(
                                    _running ? '扫描中...' : '结果将显示在此处',
                                    style: AppTextStyles.caption(size: 12, color: AppColors.textMuted),
                                  ),
                                )
                              : ListView.builder(
                                  controller: _resultsScrollController,
                                  itemCount: _results.length,
                                  itemBuilder: (context, i) {
                                    final r = _results[i];
                                    final color = r.statusCode == 200
                                        ? AppColors.cyan
                                        : r.statusCode >= 300 && r.statusCode < 400
                                            ? AppColors.primary
                                            : r.statusCode == 401
                                                ? Colors.orange
                                                : r.statusCode == 403
                                                    ? Colors.amber
                                                    : AppColors.textSecondary;
                                    return SelectableText(
                                      '${r.statusCode}  ${_fmtSize(r.contentLength).padRight(8)}  ${r.path}',
                                      style: AppTextStyles.terminal(size: 12, color: color),
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
          ),
        ],
      ),
    );
  }
}
