import 'package:sqflite/sqflite.dart';

import '../../models/webshell.dart';

class WebshellDao {
  WebshellDao(this._databaseProvider);

  final Future<Database> Function() _databaseProvider;

  Future<Webshell> createWebshell(
    int projectId, {
    required String name,
    required String url,
    String? password,
    String method = 'POST',
    String type = 'php',
    String connectorType = 'php_eval',
  }) async {
    final db = await _databaseProvider();
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await db.insert('webshells', {
      'project_id': projectId,
      'name': name,
      'url': url,
      'password': password,
      'type': type,
      'method': method,
      'status': 1,
      'connector_type': connectorType,
      'created_at': now,
      'updated_at': now,
    });
    return Webshell(
      id: id,
      projectId: projectId,
      name: name,
      url: url,
      password: password,
      type: type,
      method: method,
      connectorType: connectorType,
      createdAt: DateTime.fromMillisecondsSinceEpoch(now),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(now),
    );
  }

  Future<List<Webshell>> getWebshellsByProject(int projectId) async {
    final db = await _databaseProvider();
    final maps = await db.query(
      'webshells',
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'updated_at DESC',
    );
    return maps.map((m) => Webshell.fromMap(m)).toList();
  }

  Future<int> updateWebshell(Webshell webshell) async {
    final db = await _databaseProvider();
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.update(
      'webshells',
      {
        'name': webshell.name,
        'url': webshell.url,
        'password': webshell.password,
        'type': webshell.type,
        'method': webshell.method,
        'status': webshell.status,
        'connector_type': webshell.connectorType,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [webshell.id],
    );
  }

  Future<int> deleteWebshell(int id) async {
    final db = await _databaseProvider();
    return db.delete('webshells', where: 'id = ?', whereArgs: [id]);
  }
}
