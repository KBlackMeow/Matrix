import 'package:sqflite/sqflite.dart';

import '../../models/project.dart';

class ProjectDao {
  ProjectDao(this._databaseProvider);

  final Future<Database> Function() _databaseProvider;

  Future<Project> createProject(
    String name, {
    required String domain,
    String? description,
  }) async {
    final db = await _databaseProvider();
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await db.insert('projects', {
      'name': name,
      'domain': domain,
      'description': description,
      'created_at': now,
      'updated_at': now,
    });
    return Project(
      id: id,
      name: name,
      domain: domain,
      description: description,
      createdAt: DateTime.fromMillisecondsSinceEpoch(now),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(now),
    );
  }

  Future<List<Project>> getAllProjects() async {
    final db = await _databaseProvider();
    final maps = await db.query('projects', orderBy: 'updated_at DESC');
    return maps.map((m) => Project.fromMap(m)).toList();
  }

  Future<Project?> getProjectById(int id) async {
    final db = await _databaseProvider();
    final maps = await db.query('projects', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Project.fromMap(maps.first);
  }

  Future<int> updateProject(Project project) async {
    final db = await _databaseProvider();
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.update(
      'projects',
      {
        'name': project.name,
        'domain': project.domain,
        'description': project.description,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [project.id],
    );
  }

  Future<int> deleteProject(int id) async {
    final db = await _databaseProvider();
    await db.delete('webshells', where: 'project_id = ?', whereArgs: [id]);
    return db.delete('projects', where: 'id = ?', whereArgs: [id]);
  }
}
