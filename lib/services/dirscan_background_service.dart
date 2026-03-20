import 'dart:async';

import 'dirsearch_service.dart';
import 'scan_session_service.dart';

/// 目录扫描后台服务：扫描与 UI 解耦，离开页面后继续运行
class DirscanBackgroundService {
  static final DirscanBackgroundService _instance =
      DirscanBackgroundService._internal();
  factory DirscanBackgroundService() => _instance;
  DirscanBackgroundService._internal();

  final _scanSession = ScanSessionService();

  /// sessionId -> 取消标记
  final _cancelFlags = <int, bool>{};

  /// sessionId -> DirsearchService 实例（用于立即中止 HTTP 请求）
  final _activeSvcs = <int, DirsearchService>{};

  /// 进度流：供 UI 订阅
  final _progressController = StreamController<DirscanProgress>.broadcast();
  Stream<DirscanProgress> get progress => _progressController.stream;

  // ── 启动扫描 ─────────────────────────────────────────────────────────────

  Future<int> startScan({
    required int projectId,
    required String baseUrl,
    List<String> extensions = const ['php', 'html', 'js', 'txt', 'asp', 'aspx', 'jsp'],
    int threads = 5,
    int timeoutSec = 8,
    Set<int> statusCodes = const {200, 201, 301, 302, 401, 403},
    // 递归模式（对应 dirsearch --recursive / --deep-recursive / --force-recursive）
    bool recursiveScan = true,
    bool deepRecursive = false,
    bool forceRecursive = false,
    int maxRecurseDepth = 0, // 0 = 不限制
    // 触发递归的状态码（对应 --recursion-status，dirsearch 默认 {200}）
    Set<int> recursionStatusCodes = const {200},
    // 高级过滤器
    List<String> excludeTexts = const [],
    String? excludeRegex,
    String? excludeRedirect,
    int minResponseSize = 0,
    int maxResponseSize = 0,
    int filterThreshold = 0,
  }) async {
    final sessionId = await _scanSession.createSession(
      projectId: projectId,
      scanType: 'dir_scan',
      target: baseUrl,
    );
    _cancelFlags[sessionId] = false;
    unawaited(_runScan(
      sessionId: sessionId,
      baseUrl: baseUrl,
      extensions: extensions,
      threads: threads,
      timeoutSec: timeoutSec,
      statusCodes: statusCodes,
      recursiveScan: recursiveScan,
      deepRecursive: deepRecursive,
      forceRecursive: forceRecursive,
      maxRecurseDepth: maxRecurseDepth,
      recursionStatusCodes: recursionStatusCodes,
      excludeTexts: excludeTexts,
      excludeRegex: excludeRegex,
      excludeRedirect: excludeRedirect,
      minResponseSize: minResponseSize,
      maxResponseSize: maxResponseSize,
      filterThreshold: filterThreshold,
    ));
    return sessionId;
  }

  // ── 内部扫描循环 ──────────────────────────────────────────────────────────

  Future<void> _runScan({
    required int sessionId,
    required String baseUrl,
    required List<String> extensions,
    required int threads,
    required int timeoutSec,
    required Set<int> statusCodes,
    required bool recursiveScan,
    required bool deepRecursive,
    required bool forceRecursive,
    required int maxRecurseDepth,
    required Set<int> recursionStatusCodes,
    required List<String> excludeTexts,
    required String? excludeRegex,
    required String? excludeRedirect,
    required int minResponseSize,
    required int maxResponseSize,
    required int filterThreshold,
  }) async {
    void notifyProgress(DirscanProgress p) {
      if (!_progressController.isClosed) _progressController.add(p);
    }

    try {
      // ── 加载并展开字典 ────────────────────────────────────────────────────
      final (:basePaths, :paths) =
          await DirsearchService.loadAndExpandWordlistAsync('dicc.txt', extensions);
      if (paths.isEmpty) {
        notifyProgress(DirscanProgress(sessionId: sessionId, status: 'empty_dict'));
        await _scanSession.finishSession(sessionId, status: 'completed');
        return;
      }

      // ── 创建 Service 实例 ─────────────────────────────────────────────────
      final svc = DirsearchService(
        baseUrl: baseUrl,
        threads: threads.clamp(1, 50),
        timeout: Duration(seconds: timeoutSec.clamp(1, 60)),
        includeStatus: statusCodes,
        extensions: extensions,
        excludeTexts: excludeTexts,
        excludeRegex: excludeRegex,
        excludeRedirect: excludeRedirect,
        minResponseSize: minResponseSize,
        maxResponseSize: maxResponseSize,
        filterThreshold: filterThreshold,
      );
      _activeSvcs[sessionId] = svc;

      // ── 目录队列（对应 dirsearch Controller.directories） ─────────────────
      // 每个元素：(dirPath, depth)
      // dirPath = "" 表示根路径，"admin/" 表示子目录
      final directoryQueue = <_DirEntry>[_DirEntry('', 0)];
      // 已访问的完整 URL，防止重复扫描
      final passedUrls = <String>{_normaliseBase(baseUrl)};
      // 全局已扫描路径集合
      final scannedPaths = <String>{};

      var totalPlanned = 0;
      var totalCompleted = 0;
      var resultsCount = 0;

      notifyProgress(DirscanProgress(
        sessionId: sessionId,
        current: 0,
        total: paths.length,
        resultsCount: 0,
        status: 'running',
      ));

      // ── 目录队列循环（对应 dirsearch Controller.start()） ─────────────────
      while (directoryQueue.isNotEmpty &&
          !(_cancelFlags[sessionId] ?? false)) {
        final entry = directoryQueue.removeAt(0);
        final currentDir = entry.path;  // e.g. "" or "admin/"
        final currentDepth = entry.depth;

        // 为当前目录重新初始化 wildcard scanners
        // （对应 dirsearch fuzzer.set_base_path(dir) + setup_scanners()）
        await svc.initScannersForBase(currentDir);

        // 为当前目录生成路径列表
        final dirPaths = _pathsForDirectory(
          rootPaths: paths,
          basePaths: basePaths,
          dirPath: currentDir,
          extensions: extensions,
          scannedPaths: scannedPaths,
        );
        if (dirPaths.isEmpty) continue;

        scannedPaths.addAll(dirPaths);
        totalPlanned += dirPaths.length;

        notifyProgress(DirscanProgress(
          sessionId: sessionId,
          current: totalCompleted,
          total: totalPlanned,
          resultsCount: resultsCount,
          status: 'running',
        ));

        final found = await svc.scan(
          paths: dirPaths,
          onFound: (r) {
            _scanSession.appendLog(
                sessionId, '${r.path}|${r.statusCode}|${r.contentLength}');
            resultsCount++;
          },
          onProgress: (cur, _) {
            notifyProgress(DirscanProgress(
              sessionId: sessionId,
              current: totalCompleted + cur,
              total: totalPlanned,
              resultsCount: resultsCount,
              status: 'running',
            ));
          },
          isCancelled: () => _cancelFlags[sessionId] ?? false,
        );

        totalCompleted += dirPaths.length;

        // ── 递归处理（对应 dirsearch Controller.match_callback + recur()） ──
        if (!recursiveScan) continue;

        for (final r in found) {
          if (!recursionStatusCodes.contains(r.statusCode)) continue;

          final cleanPath = r.path.startsWith('/')
              ? r.path.substring(1)
              : r.path;

          // redirect-based recursion: "/admin" → "/admin/" 时加入队列
          // (对应 dirsearch recur_for_redirect)
          if (r.redirect != null) {
            final redirectPath = _extractPath(r.redirect!);
            if (redirectPath != null &&
                redirectPath == '/$cleanPath/') {
              _enqueue(
                directoryQueue,
                passedUrls,
                baseUrl: baseUrl,
                path: cleanPath.endsWith('/') ? cleanPath : '$cleanPath/',
                parentDepth: currentDepth,
                maxDepth: maxRecurseDepth,
              );
            }
            continue; // redirect 路径已处理，跳过普通递归
          }

          if (deepRecursive) {
            // deep-recursive: 对路径每个 "/" 组件都入队
            // 如 "a/b/c/" → "a/" "a/b/" "a/b/c/" 都加入
            var i = 0;
            final slashCount = cleanPath.split('/').length - 1;
            for (var s = 0; s < slashCount; s++) {
              i = cleanPath.indexOf('/', i) + 1;
              _enqueue(
                directoryQueue,
                passedUrls,
                baseUrl: baseUrl,
                path: cleanPath.substring(0, i),
                parentDepth: currentDepth,
                maxDepth: maxRecurseDepth,
              );
            }
          } else if (forceRecursive) {
            // force-recursive: 强制在所有路径末尾加 "/" 后入队
            final forced =
                cleanPath.endsWith('/') ? cleanPath : '$cleanPath/';
            _enqueue(
              directoryQueue,
              passedUrls,
              baseUrl: baseUrl,
              path: forced,
              parentDepth: currentDepth,
              maxDepth: maxRecurseDepth,
            );
          } else {
            // standard recursive: 仅对以 "/" 结尾且无扩展名的路径递归
            if (cleanPath.endsWith('/') && !_hasExtension(cleanPath)) {
              _enqueue(
                directoryQueue,
                passedUrls,
                baseUrl: baseUrl,
                path: cleanPath,
                parentDepth: currentDepth,
                maxDepth: maxRecurseDepth,
              );
            }
          }
        }
      }

      notifyProgress(DirscanProgress(
        sessionId: sessionId,
        current: totalCompleted,
        total: totalPlanned > 0 ? totalPlanned : paths.length,
        resultsCount: resultsCount,
        status: _cancelFlags[sessionId] == true ? 'cancelled' : 'completed',
      ));
    } catch (e) {
      notifyProgress(
          DirscanProgress(sessionId: sessionId, status: 'error', message: '$e'));
    } finally {
      final cancelled = _cancelFlags[sessionId] == true;
      _cancelFlags.remove(sessionId);
      _activeSvcs.remove(sessionId);
      await _scanSession.finishSession(
        sessionId,
        status: cancelled ? 'cancelled' : 'completed',
      );
    }
  }

  // ── 辅助：为当前目录生成扫描路径 ─────────────────────────────────────────

  /// 根目录 (dirPath="") 使用 rootPaths；子目录用 basePaths 拼接。
  static List<String> _pathsForDirectory({
    required List<String> rootPaths,
    required List<String> basePaths,
    required String dirPath,
    required List<String> extensions,
    required Set<String> scannedPaths,
  }) {
    if (dirPath.isEmpty) {
      return rootPaths.where((p) => !scannedPaths.contains(p)).toList();
    }
    return DirsearchService.childPathsForDirectory(
      dirPath: dirPath.endsWith('/') ? dirPath : '$dirPath/',
      basePaths: basePaths,
      extensions: extensions,
    ).where((p) => !scannedPaths.contains(p)).toList();
  }

  // ── 辅助：加入目录队列（对应 dirsearch add_directory()）─────────────────

  static void _enqueue(
    List<_DirEntry> queue,
    Set<String> passedUrls, {
    required String baseUrl,
    required String path,
    required int parentDepth,
    required int maxDepth,
  }) {
    final newDepth = parentDepth + 1;
    // 深度限制（0 = 不限制，对应 dirsearch --recursion-depth 0 = unlimited）
    if (maxDepth > 0 && newDepth > maxDepth) return;

    final normalBase = _normaliseBase(baseUrl);
    final fullUrl = '$normalBase$path';
    if (passedUrls.contains(fullUrl)) return;

    passedUrls.add(fullUrl);
    queue.add(_DirEntry(path, newDepth));
  }

  // ── 辅助 ──────────────────────────────────────────────────────────────────

  static String _normaliseBase(String url) =>
      url.endsWith('/') ? url : '$url/';

  /// 路径是否有文件扩展名（用于 recursive 模式判断是否为目录）
  static bool _hasExtension(String path) =>
      RegExp(r'\w+\.[a-zA-Z0-9]{2,5}(/)?$').hasMatch(path);

  /// 从完整 URL 或相对路径中提取 path 部分
  static String? _extractPath(String urlOrPath) {
    final uri = Uri.tryParse(urlOrPath);
    if (uri != null && uri.hasScheme) return uri.path;
    return urlOrPath.startsWith('/') ? urlOrPath : '/$urlOrPath';
  }

  // ── 取消 / 释放 ───────────────────────────────────────────────────────────

  void cancelSession(int sessionId) {
    _cancelFlags[sessionId] = true;
    _activeSvcs[sessionId]?.cancel();
  }

  void dispose() {
    _progressController.close();
  }
}

// ── 数据结构 ──────────────────────────────────────────────────────────────────

class _DirEntry {
  final String path;
  final int depth;
  const _DirEntry(this.path, this.depth);
}

class DirscanProgress {
  final int sessionId;
  final int current;
  final int total;
  final int resultsCount;
  final String status; // running, completed, cancelled, error, empty_dict
  final String? message;

  DirscanProgress({
    required this.sessionId,
    this.current = 0,
    this.total = 0,
    this.resultsCount = 0,
    this.status = 'running',
    this.message,
  });
}
