import 'package:sqflite/sqflite.dart';

import '../../models/suo5_profile.dart';

class Suo5ProfileDao {
  Suo5ProfileDao(this._databaseProvider);

  final Future<Database> Function() _databaseProvider;

  Future<Suo5Profile> createSuo5Profile({
    required int projectId,
    required String name,
    required String targetUrl,
    required String listenHost,
    required int listenPort,
  }) async {
    final db = await _databaseProvider();
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await db.insert('suo5_profiles', {
      'project_id': projectId,
      'name': name,
      'target_url': targetUrl,
      'listen_host': listenHost,
      'listen_port': listenPort,
      'created_at': now,
      'updated_at': now,
    });
    return Suo5Profile(
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

  Future<List<Suo5Profile>> getSuo5ProfilesByProject(int projectId) async {
    final db = await _databaseProvider();
    final maps = await db.query(
      'suo5_profiles',
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'updated_at DESC',
    );
    return maps
        .map((m) => Suo5Profile.fromMap(m.map((k, v) => MapEntry(k, v))))
        .toList();
  }

  Future<Suo5Profile?> updateSuo5Profile(Suo5Profile profile) async {
    final db = await _databaseProvider();
    final now = DateTime.now().millisecondsSinceEpoch;
    final n = await db.update(
      'suo5_profiles',
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
      'suo5_profiles',
      where: 'id = ?',
      whereArgs: [profile.id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Suo5Profile.fromMap(maps.first.map((k, v) => MapEntry(k, v)));
  }

  Future<int> deleteSuo5Profile(int id) async {
    final db = await _databaseProvider();
    return db.delete('suo5_profiles', where: 'id = ?', whereArgs: [id]);
  }
}
