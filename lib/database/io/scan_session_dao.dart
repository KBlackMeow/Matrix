import 'package:sqflite/sqflite.dart';

class ScanSessionDao {
  ScanSessionDao(this._databaseProvider);

  final Future<Database> Function() _databaseProvider;

  Future<int> createScanSession({
    required int projectId,
    required String scanType,
    required String target,
    String? configJson,
  }) async {
    final db = await _databaseProvider();
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.insert('scan_sessions', {
      'project_id': projectId,
      'scan_type': scanType,
      'target': target,
      'config_json': configJson,
      'log_text': '',
      'status': 'running',
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<Map<String, dynamic>?> getLatestScanSession(
    int projectId,
    String scanType,
  ) async {
    final db = await _databaseProvider();
    final rows = await db.query(
      'scan_sessions',
      where: 'project_id = ? AND scan_type = ?',
      whereArgs: [projectId, scanType],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first.map((k, v) => MapEntry(k.toString(), v));
  }

  Future<void> updateScanSession(int id, {String? logText, String? status}) async {
    final db = await _databaseProvider();
    final now = DateTime.now().millisecondsSinceEpoch;
    final updates = <String, dynamic>{'updated_at': now};
    if (logText != null) updates['log_text'] = logText;
    if (status != null) updates['status'] = status;
    await db.update('scan_sessions', updates, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> resetStaleRunningSessions() async {
    final db = await _databaseProvider();
    await db.update(
      'scan_sessions',
      {'status': 'interrupted', 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'status = ?',
      whereArgs: ['running'],
    );
  }

  Future<void> appendScanLog(int id, String text) async {
    final db = await _databaseProvider();
    final rows = await db.query('scan_sessions', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return;
    final current = rows.first['log_text'] as String? ?? '';
    final updated = current.isEmpty ? text : '$current\n$text';
    await db.update(
      'scan_sessions',
      {'log_text': updated, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
