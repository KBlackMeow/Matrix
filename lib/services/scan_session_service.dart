import 'dart:async';

import '../database/database_helper.dart';

/// 扫描会话服务：持久化 + 后台运行
/// 扫描可后台进行，结果自动保存，退出再进入恢复状态
class ScanSessionService {
  static final ScanSessionService _instance = ScanSessionService._internal();
  factory ScanSessionService() => _instance;
  ScanSessionService._internal();

  final _db = DatabaseHelper();

  /// 创建新会话（开始新扫描时调用）
  Future<int> createSession({
    required int projectId,
    required String scanType,
    required String target,
    String? configJson,
  }) =>
      _db.createScanSession(
        projectId: projectId,
        scanType: scanType,
        target: target,
        configJson: configJson,
      );

  /// 获取或创建会话：返回 (sessionId, 已有 log, 是否正在运行)
  Future<({int id, String log, bool running})> getOrCreateSession({
    required int projectId,
    required String scanType,
    required String target,
    String? configJson,
  }) async {
    final existing = await _db.getLatestScanSession(projectId, scanType);
    if (existing != null) {
      final id = existing['id'] as int;
      final log = existing['log_text'] as String? ?? '';
      final status = existing['status'] as String? ?? 'completed';
      return (id: id, log: log, running: status == 'running');
    }
    final id = await _db.createScanSession(
      projectId: projectId,
      scanType: scanType,
      target: target,
      configJson: configJson,
    );
    return (id: id, log: '', running: false);
  }

  /// 追加日志（带节流，减少 DB 写入）
  String _pendingLog = '';
  int _pendingSessionId = 0;
  Timer? _flushTimer;
  static const _flushInterval = Duration(milliseconds: 300);

  void appendLog(int sessionId, String line) {
    if (_pendingSessionId != sessionId && _pendingSessionId != 0) {
      _flushNow();
    }
    _pendingSessionId = sessionId;
    _pendingLog = _pendingLog.isEmpty ? line : '$_pendingLog\n$line';
    _flushTimer ??= Timer(_flushInterval, _flushNow);
  }

  void _flushNow() {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_pendingSessionId == 0 || _pendingLog.isEmpty) return;
    final id = _pendingSessionId;
    final log = _pendingLog;
    _pendingSessionId = 0;
    _pendingLog = '';
    _db.appendScanLog(id, log);
  }

  /// 完成时调用，确保最后日志写入
  Future<void> finishSession(int sessionId, {String status = 'completed'}) async {
    _flushNow();
    await _db.updateScanSession(sessionId, status: status);
  }

  /// 加载最新会话
  Future<({String log, String? target, String? config})?> loadSession(
    int projectId,
    String scanType,
  ) async {
    final row = await _db.getLatestScanSession(projectId, scanType);
    if (row == null) return null;
    return (
      log: row['log_text'] as String? ?? '',
      target: row['target'] as String?,
      config: row['config_json'] as String?,
    );
  }

  /// 加载最新会话（含 id、status，用于后台扫描恢复）
  Future<({int id, String log, String? target, String? config, String status})?> loadSessionWithMeta(
    int projectId,
    String scanType,
  ) async {
    final row = await _db.getLatestScanSession(projectId, scanType);
    if (row == null) return null;
    return (
      id: row['id'] as int,
      log: row['log_text'] as String? ?? '',
      target: row['target'] as String?,
      config: row['config_json'] as String?,
      status: row['status'] as String? ?? 'completed',
    );
  }
}
