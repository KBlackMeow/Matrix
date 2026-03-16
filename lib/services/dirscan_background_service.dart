import 'dart:async';

import 'dirsearch_service.dart';
import 'scan_session_service.dart';

/// 目录扫描后台服务：扫描与 UI 解耦，离开页面后继续运行
class DirscanBackgroundService {
  static final DirscanBackgroundService _instance = DirscanBackgroundService._internal();
  factory DirscanBackgroundService() => _instance;
  DirscanBackgroundService._internal();

  final _scanSession = ScanSessionService();

  /// 当前运行中的 sessionId -> 取消标记
  final _cancelFlags = <int, bool>{};

  /// 当前运行中的 sessionId -> DirsearchService 实例（用于立即中止 HTTP 请求）
  final _activeSvcs = <int, DirsearchService>{};

  /// 进度流：供 UI 订阅（可选，UI 销毁后不再监听，扫描照常进行）
  final _progressController = StreamController<DirscanProgress>.broadcast();
  Stream<DirscanProgress> get progress => _progressController.stream;

  /// 启动后台扫描（与 widget 生命周期无关）
  /// 返回 sessionId，扫描在后台继续执行
  Future<int> startScan({
    required int projectId,
    required String baseUrl,
    List<String> extensions = const ['php', 'html', 'js', 'txt', 'asp', 'aspx', 'jsp'],
    int threads = 5,
    int timeoutSec = 8,
    Set<int> statusCodes = const {200, 201, 301, 302, 401, 403},
    bool recursiveScan = true,
    int maxRecurseDepth = 0,
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
      maxRecurseDepth: maxRecurseDepth,
    ));
    return sessionId;
  }

  Future<void> _runScan({
    required int sessionId,
    required String baseUrl,
    required List<String> extensions,
    required int threads,
    required int timeoutSec,
    required Set<int> statusCodes,
    required bool recursiveScan,
    required int maxRecurseDepth,
  }) async {
    void notifyProgress(DirscanProgress p) {
      if (!_progressController.isClosed) {
        _progressController.add(p);
      }
    }

    try {
      final (:basePaths, :paths) =
          await DirsearchService.loadAndExpandWordlistAsync('dicc.txt', extensions);
      if (paths.isEmpty) {
        notifyProgress(DirscanProgress(sessionId: sessionId, status: 'empty_dict'));
        await _scanSession.finishSession(sessionId, status: 'completed');
        return;
      }

      notifyProgress(DirscanProgress(
        sessionId: sessionId,
        current: 0,
        total: paths.length,
        resultsCount: 0,
        status: 'running',
      ));

      final svc = DirsearchService(
        baseUrl: baseUrl,
        threads: threads.clamp(1, 50),
        timeout: Duration(seconds: timeoutSec.clamp(1, 60)),
        includeStatus: statusCodes,
      );
      _activeSvcs[sessionId] = svc;

      final scannedPaths = <String>{};
      var totalCompletedBefore = 0;
      var totalPlanned = paths.length;
      var roundPaths = paths;
      var depth = 0;
      var resultsCount = 0;

      while (roundPaths.isNotEmpty && !(_cancelFlags[sessionId] ?? false)) {
        final toScan = roundPaths.where((p) => !scannedPaths.contains(p)).toList();
        scannedPaths.addAll(toScan);
        if (toScan.isEmpty) break;

        final found = await svc.scan(
          paths: toScan,
          onFound: (r) {
            _scanSession.appendLog(sessionId, '${r.path}|${r.statusCode}|${r.contentLength}');
            resultsCount++;
          },
          onProgress: (cur, total) {
            notifyProgress(DirscanProgress(
              sessionId: sessionId,
              current: totalCompletedBefore + cur,
              total: totalPlanned,
              resultsCount: resultsCount,
              status: 'running',
            ));
          },
          isCancelled: () => _cancelFlags[sessionId] ?? false,
        );

        totalCompletedBefore += toScan.length;

        if (!recursiveScan || depth >= maxRecurseDepth) break;

        final dirs200 = found
            .where((r) =>
                r.statusCode == 200 && DirsearchService.looksLikeDirectory(r.path))
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
      }

      notifyProgress(DirscanProgress(
        sessionId: sessionId,
        current: totalPlanned,
        total: totalPlanned,
        resultsCount: resultsCount,
        status: _cancelFlags[sessionId] == true ? 'cancelled' : 'completed',
      ));
    } catch (e) {
      notifyProgress(DirscanProgress(sessionId: sessionId, status: 'error', message: '$e'));
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

  void cancelSession(int sessionId) {
    _cancelFlags[sessionId] = true;
    _activeSvcs[sessionId]?.cancel();
  }

  void dispose() {
    _progressController.close();
  }
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
