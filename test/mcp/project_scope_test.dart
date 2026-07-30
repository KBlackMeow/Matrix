import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/mcp/db.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test(
    'closing MCP database does not close the app database connection',
    () async {
      McpDatabase.initFfi();
      final tempDir = Directory.systemTemp.createTempSync('matrix_mcp_scope_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final dbPath = p.join(tempDir.path, 'matrix.db');
      final appDb = await openDatabase(dbPath);
      addTearDown(appDb.close);
      await appDb.execute('CREATE TABLE projects (id INTEGER PRIMARY KEY)');

      final mcpDb = McpDatabase(dbPath);
      await mcpDb.database;
      await mcpDb.close();

      expect(await appDb.query('projects'), isEmpty);
    },
  );

  test(
    'MCP database restricts WebShell access to the selected project',
    () async {
      McpDatabase.initFfi();
      final tempDir = Directory.systemTemp.createTempSync('matrix_mcp_scope_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final dbPath = p.join(tempDir.path, 'matrix.db');
      final rawDb = await openDatabase(dbPath);
      await rawDb.execute('''
      CREATE TABLE projects (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        domain TEXT NOT NULL,
        description TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
      await rawDb.execute('''
      CREATE TABLE webshells (
        id INTEGER PRIMARY KEY,
        project_id INTEGER,
        name TEXT NOT NULL,
        url TEXT NOT NULL,
        password TEXT,
        type TEXT NOT NULL,
        method TEXT,
        status INTEGER,
        connector_type TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
      await rawDb.insert('projects', {
        'id': 1,
        'name': 'one',
        'domain': '',
        'created_at': 0,
        'updated_at': 0,
      });
      await rawDb.insert('projects', {
        'id': 2,
        'name': 'two',
        'domain': '',
        'created_at': 0,
        'updated_at': 0,
      });
      for (final row in [
        {'id': 10, 'project_id': 1, 'name': 'one-shell'},
        {'id': 20, 'project_id': 2, 'name': 'two-shell'},
      ]) {
        await rawDb.insert('webshells', {
          ...row,
          'url': 'http://example.test',
          'type': 'php',
          'method': 'POST',
          'status': 1,
          'connector_type': 'php_eval',
          'created_at': 0,
          'updated_at': 0,
        });
      }
      await rawDb.close();

      final db = McpDatabase(dbPath);
      addTearDown(db.close);

      expect(await db.listWebshellsWithProject(1), hasLength(1));
      expect(await db.getWebshell(20, projectId: 1), isNull);
      expect(await db.deleteWebshell(20, projectId: 1), 0);
      expect(await db.getWebshell(20, projectId: 2), isNotNull);
    },
  );
}
