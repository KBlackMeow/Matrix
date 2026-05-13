import 'package:sqflite/sqflite.dart';

import '../../models/suo6_profile.dart';

class Suo6ProfileDao {
  Suo6ProfileDao(this._databaseProvider);

  final Future<Database> Function() _databaseProvider;

  Future<Suo6Profile> createSuo6Profile({
    required int projectId,
    required String name,
    required String targetUrl,
    required String listenHost,
    required int listenPort,
  }) async {
    final db = await _databaseProvider();
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await db.insert('suo6_profiles', {
      'project_id': projectId,
      'name': name,
      'target_url': targetUrl,
      'listen_host': listenHost,
      'listen_port': listenPort,
      'created_at': now,
      'updated_at': now,
    });
    return Suo6Profile(
      id: id,
      projectId: projectId,
      name: name,
      targetUrl: targetUrl,
      listenHost: listenHost,
      listenPort: listenPort,
      createdAt: DateTime.fromMillisecondsSinceEpoch(now),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(now),
    );
  }

  Future<List<Suo6Profile>> getSuo6ProfilesByProject(int projectId) async {
    final db = await _databaseProvider();
    final maps = await db.query(
      'suo6_profiles',
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'updated_at DESC',
    );
    return maps
        .map((m) => Suo6Profile.fromMap(m.map((k, v) => MapEntry(k, v))))
        .toList();
  }

  Future<Suo6Profile?> updateSuo6Profile(Suo6Profile profile) async {
    final db = await _databaseProvider();
    final now = DateTime.now().millisecondsSinceEpoch;
    final n = await db.update(
      'suo6_profiles',
      {
        'name': profile.name,
        'target_url': profile.targetUrl,
        'listen_host': profile.listenHost,
        'listen_port': profile.listenPort,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [profile.id],
    );
    if (n == 0) return null;
    final maps = await db.query(
      'suo6_profiles',
      where: 'id = ?',
      whereArgs: [profile.id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Suo6Profile.fromMap(maps.first.map((k, v) => MapEntry(k, v)));
  }

  Future<int> deleteSuo6Profile(int id) async {
    final db = await _databaseProvider();
    return db.delete('suo6_profiles', where: 'id = ?', whereArgs: [id]);
  }
}
