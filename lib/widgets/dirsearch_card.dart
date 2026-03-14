import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../services/dirsearch_service.dart';
import '../theme/app_theme.dart';

/// 复刻 [dirsearch](https://github.com/maurosoria/dirsearch) 的路径爆破 UI
class DirsearchCard extends StatefulWidget {
  final String? initialUrl;

  const DirsearchCard({super.key, this.initialUrl});

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

  static const String _dictFile = 'dicc.txt';
  List<DirsearchResult> _results = [];
  String _statusMessage = '';
  int _progressCurrent = 0;
  int _progressTotal = 0;
  bool _running = false;
  bool _cancelled = false;
  bool _recursiveScan = true;

  /// 节流进度更新（毫秒时间戳），避免过于频繁的 setState
  int _lastProgressUpdateMs = 0;
  /// 发现结果异步展示：累积后定时刷新（每 250ms 或满 15 条），降低 setState 频率避免主线程阻塞
  static const int _resultFlushIntervalMs = 250;
  static const int _resultFlushBatchSize = 15;
  int _lastResultFlushMs = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialUrl != null) _urlController.text = widget.initialUrl!;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _extensionsController.dispose();
    _threadsController.dispose();
    _timeoutController.dispose();
    _statusIncludeController.dispose();
    _maxRecurseDepthController.dispose();
    _resultsScrollController.dispose();
    super.dispose();
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

    setState(() {
      _running = true;
      _cancelled = false;
      _results = [];
      _statusMessage = '';
      _progressCurrent = 0;
      _progressTotal = 0;
      _lastProgressUpdateMs = 0;
    });

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

    final (:basePaths, :paths) =
        await DirsearchService.loadAndExpandWordlistAsync(_dictFile, extensions);
    if (paths.isEmpty) {
      _setStatus('[!] 字典为空或加载失败');
      setState(() => _running = false);
      return;
    }
    setState(() => _progressTotal = paths.length);

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

    final svc = DirsearchService(
      baseUrl: baseUrl,
      threads: threads.clamp(1, 50),
      timeout: Duration(seconds: timeoutSec.clamp(1, 60)),
      includeStatus: statusCodes,
    );

    try {
      final maxRecurseDepth =
          (int.tryParse(_maxRecurseDepthController.text.trim()) ?? 0).clamp(
            0,
            10,
          );
      final scannedPaths = <String>{};
      var totalCompletedBefore = 0;
      var totalPlanned = paths.length;
      var roundPaths = paths;
      var depth = 0;

      while (roundPaths.isNotEmpty && !_cancelled) {
        final toScan = roundPaths
            .where((p) => !scannedPaths.contains(p))
            .toList();
        scannedPaths.addAll(toScan);
        if (toScan.isEmpty) break;

        if (mounted) setState(() => _progressTotal = totalPlanned);

        var foundBatch = <DirsearchResult>[];
        final found = await svc.scan(
          paths: toScan,
          onFound: (r) {
            foundBatch.add(r);
            if (!mounted) return;
            final now = DateTime.now().millisecondsSinceEpoch;
            final shouldFlush = foundBatch.isNotEmpty &&
                (foundBatch.length >= _resultFlushBatchSize || now - _lastResultFlushMs >= _resultFlushIntervalMs);
            if (shouldFlush) {
              _lastResultFlushMs = now;
              setState(() {
                _results = List.from(_results)..addAll(foundBatch);
              });
              foundBatch = [];
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_resultsScrollController.hasClients) {
                  _resultsScrollController.animateTo(
                    _resultsScrollController.position.maxScrollExtent,
                    duration: const Duration(milliseconds: 80),
                    curve: Curves.easeOut,
                  );
                }
              });
            }
          },
          onProgress: (cur, total) {
            if (!mounted) return;
            final now = DateTime.now().millisecondsSinceEpoch;
            final isLast = cur == total;
            if (isLast || now - _lastProgressUpdateMs >= 200) {
              _lastProgressUpdateMs = now;
              setState(() => _progressCurrent = totalCompletedBefore + cur);
            }
          },
          isCancelled: () => _cancelled,
        );

        totalCompletedBefore += toScan.length;

        if (foundBatch.isNotEmpty && mounted) {
          setState(() => _results = List.from(_results)..addAll(foundBatch));
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_resultsScrollController.hasClients) {
              _resultsScrollController.animateTo(
                _resultsScrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 80),
                curve: Curves.easeOut,
              );
            }
          });
        }

        if (!_recursiveScan || depth >= maxRecurseDepth) break;

        final dirs200 = found
            .where(
              (r) =>
                  r.statusCode == 200 &&
                  DirsearchService.looksLikeDirectory(r.path),
            )
            .map((r) => r.path)
            .toList();

        roundPaths = await DirsearchService.computeNextRoundPaths(
          dirs200: dirs200,
          basePaths: basePaths,
          extensions: extensions,
          scannedPaths: scannedPaths,
          maxPathsPerRound: 50000,
        );
        totalPlanned += roundPaths.length;
        depth++;
        if (roundPaths.isNotEmpty && mounted) {
          _setStatus('递归深度 $depth，下一轮 ${roundPaths.length} 个路径');
        }
      }

      if (mounted) {
        _setStatus('扫描完成，发现 ${_results.length} 个有效路径');
        setState(() => _running = false);
      }
    } catch (e) {
      if (mounted) {
        _setStatus('[!] 异常: $e');
        setState(() => _running = false);
      }
    }
  }

  void _stopScan() {
    setState(() => _cancelled = true);
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
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
                        Row(
                          children: [
                            Checkbox(
                              value: _recursiveScan,
                              onChanged: _running ? null : (v) => setState(() => _recursiveScan = v ?? true),
                              activeColor: AppColors.primary,
                              fillColor: WidgetStateProperty.resolveWith(
                                (_) => AppColors.primary.withValues(alpha: 0.3),
                              ),
                            ),
                            Text('递归扫描 200 目录 深度', style: AppTextStyles.body(size: 12, color: AppColors.textPrimary)),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 56,
                              child: TextField(
                                controller: _maxRecurseDepthController,
                                enabled: !_running,
                                keyboardType: TextInputType.number,
                                style: AppTextStyles.body(size: 12, color: AppColors.textPrimary),
                                decoration: _inputDecoration('', '0'),
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
                              onPressed: _results.isEmpty
                                  ? null
                                  : () async {
                                      final text = _results
                                          .map((r) => '${r.statusCode}  ${_fmtSize(r.contentLength)}  ${r.path}')
                                          .join('\n');
                                      await Clipboard.setData(ClipboardData(text: text));
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
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
