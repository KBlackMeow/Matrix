import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/webshell.dart';

/// MCP Server 专用的最小化数据库帮助类。
///
/// 使用 sqflite_common_ffi（不依赖 Flutter），打开 Matrix 桌面应用
/// 的 SQLite 数据库以读取/写入 WebShell 配置。
class McpDatabase {
  final String path;

  McpDatabase(this.path);

  Database? _db;

  /// 初始化 FFI 并打开数据库。
  static void initFfi() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  static String defaultPath() {
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '/tmp';
    // macOS sandboxed first, then unsandboxed
    final candidates = [
      p.join(
        home,
        'Library',
        'Containers',
        'com.example.matrix',
        'Data',
        'Documents',
        'matrix.db',
      ),
      p.join(home, 'Documents', 'matrix.db'),
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return candidates.last;
  }

  Future<Database> get database async {
    if (_db != null) return _db!;
    if (!File(path).existsSync()) {
      throw StateError(
        'Matrix 数据库不存在: $path\n'
        '请通过 --db-path 参数指定正确的数据库路径，'
        '或先启动 Matrix 桌面应用以创建数据库。\n'
        '默认搜索位置:\n'
        '  - macOS Sandbox: ~/Library/Containers/com.example.matrix/Data/Documents/matrix.db\n'
        '  - macOS/Linux:   ~/Documents/matrix.db',
      );
    }
    // MCP must not share sqflite's path-level singleton with the Flutter app:
    // closing this connection during server shutdown must leave the app database open.
    _db = await openDatabase(path, version: 13, singleInstance: false);
    return _db!;
  }

  // ── WebShell CRUD ──────────────────────────────────────────────────────────

  Future<List<Webshell>> listWebshells() async {
    final db = await database;
    final maps = await db.query('webshells', orderBy: 'updated_at DESC');
    return maps.map((m) => Webshell.fromMap(m)).toList();
  }

  Future<List<Map<String, dynamic>>> listWebshellsWithProject(
    int projectId,
  ) async {
    final db = await database;
    return db.rawQuery(
      '''
      SELECT w.*, p.name as project_name
      FROM webshells w
      LEFT JOIN projects p ON w.project_id = p.id
      WHERE w.project_id = ?
      ORDER BY w.updated_at DESC
    ''',
      [projectId],
    );
  }

  Future<Webshell?> getWebshell(int id, {required int projectId}) async {
    final db = await database;
    final maps = await db.query(
      'webshells',
      where: 'id = ? AND project_id = ?',
      whereArgs: [id, projectId],
    );
    if (maps.isEmpty) return null;
    return Webshell.fromMap(maps.first);
  }

  Future<int> deleteWebshell(int id, {required int projectId}) async {
    final db = await database;
    return db.delete(
      'webshells',
      where: 'id = ? AND project_id = ?',
      whereArgs: [id, projectId],
    );
  }

  Future<Webshell> createWebshell({
    required int projectId,
    required String name,
    required String url,
    String? password,
    String method = 'POST',
    String type = 'php',
    String connectorType = 'php_eval',
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

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
