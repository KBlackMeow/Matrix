import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';

import '../models/project.dart';
import '../models/webshell.dart';

/// 桌面/移动端 SQLite 实现
class DatabaseHelperIo {
  static final DatabaseHelperIo _instance = DatabaseHelperIo._internal();
  static Database? _database;

  factory DatabaseHelperIo() => _instance;

  DatabaseHelperIo._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, 'matrix.db');

    return openDatabase(
      path,
      version: 3,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE projects (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        domain TEXT NOT NULL,
        description TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE info_collection (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        project_id INTEGER,
        title TEXT NOT NULL,
        content TEXT,
        type TEXT,
        source TEXT,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (project_id) REFERENCES projects (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE webshells (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        project_id INTEGER,
        name TEXT NOT NULL,
        url TEXT NOT NULL,
        password TEXT,
        type TEXT NOT NULL DEFAULT 'php',
        method TEXT,
        status INTEGER DEFAULT 1,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (project_id) REFERENCES projects (id)
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_info_project ON info_collection(project_id)',
    );
    await db.execute(
      'CREATE INDEX idx_webshell_project ON webshells(project_id)',
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
          'ALTER TABLE projects ADD COLUMN domain TEXT NOT NULL DEFAULT ""');
    }
    if (oldVersion < 3) {
      await db.execute(
          "ALTER TABLE webshells ADD COLUMN type TEXT NOT NULL DEFAULT 'php'");
    }
  }

  Future<Project> createProject(String name, {required String domain, String? description}) async {
    final db = await database;
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
    final db = await database;
    final maps = await db.query('projects', orderBy: 'updated_at DESC');
    return maps.map((m) => Project.fromMap(m)).toList();
  }

  Future<Project?> getProjectById(int id) async {
    final db = await database;
    final maps = await db.query('projects', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Project.fromMap(maps.first);
  }

  Future<int> updateProject(Project project) async {
    final db = await database;
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
    final db = await database;
    return db.delete('projects', where: 'id = ?', whereArgs: [id]);
  }

  Future<Webshell> createWebshell(
    int projectId, {
    required String name,
    required String url,
    String? password,
    String method = 'POST',
    String type = 'php',
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await db.insert('webshells', {
      'project_id': projectId,
      'name': name,
      'url': url,
      'password': password,
      'type': type,
      'method': method,
      'status': 1,
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
      createdAt: DateTime.fromMillisecondsSinceEpoch(now),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(now),
    );
  }

  Future<List<Webshell>> getWebshellsByProject(int projectId) async {
    final db = await database;
    final maps = await db.query(
      'webshells',
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'updated_at DESC',
    );
    return maps.map((m) => Webshell.fromMap(m)).toList();
  }

  Future<int> updateWebshell(Webshell webshell) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.update(
      'webshells',
      {
        'name': webshell.name,
        'url': webshell.url,
        'password': webshell.password,
        'method': webshell.method,
        'status': webshell.status,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [webshell.id],
    );
  }

  Future<int> deleteWebshell(int id) async {
    final db = await database;
    return db.delete('webshells', where: 'id = ?', whereArgs: [id]);
  }
}

final _io = DatabaseHelperIo();

Future<Project> createProject(String name, {required String domain, String? description}) =>
    _io.createProject(name, domain: domain, description: description);

Future<List<Project>> getAllProjects() => _io.getAllProjects();

Future<Project?> getProjectById(int id) => _io.getProjectById(id);

Future<int> updateProject(Project project) => _io.updateProject(project);

Future<int> deleteProject(int id) => _io.deleteProject(id);

Future<Webshell> createWebshell(
  int projectId, {
  required String name,
  required String url,
  String? password,
  String method = 'POST',
  String type = 'php',
}) =>
    _io.createWebshell(
      projectId,
      name: name,
      url: url,
      password: password,
      method: method,
      type: type,
    );

Future<List<Webshell>> getWebshellsByProject(int projectId) =>
    _io.getWebshellsByProject(projectId);

Future<int> updateWebshell(Webshell webshell) => _io.updateWebshell(webshell);

Future<int> deleteWebshell(int id) => _io.deleteWebshell(id);
