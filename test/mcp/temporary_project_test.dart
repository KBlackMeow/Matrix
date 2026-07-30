import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/mcp/db.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('MCP shell additions use the existing temporary project', () async {
    McpDatabase.initFfi();
    final tmpDir = Directory.systemTemp.createTempSync('matrix_mcp_test_');
    addTearDown(() => tmpDir.deleteSync(recursive: true));
    final dbPath = p.join(tmpDir.path, 'matrix.db');
    final rawDb = await openDatabase(dbPath);
    await rawDb.execute('''
      CREATE TABLE projects (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        domain TEXT NOT NULL,
        description TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await rawDb.execute(
      'CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
    await rawDb.insert('projects', {
      'id': 7,
      'name': '临时项目',
      'domain': '',
      'description': null,
      'created_at': 0,
      'updated_at': 0,
    });
    await rawDb.insert('meta', {'key': 'temporary_project_id', 'value': '7'});
    await rawDb.close();

    final db = McpDatabase(dbPath);
    addTearDown(db.close);
    final projectId = await db.temporaryProjectId();
    final project = (await db.database).query(
      'projects',
      where: 'id = ?',
      whereArgs: [projectId],
    );

    expect((await project).single['name'], '临时项目');
    expect(await db.temporaryProjectId(), projectId);
  });
}
