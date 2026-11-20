import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/mcp/db.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tmp;
  late String dbPath;
  late String payloadDir;

  setUp(() async {
    McpDatabase.initFfi();
    tmp = await Directory.systemTemp.createTemp('matrix_payload_db_');
    dbPath = p.join(tmp.path, 'matrix.db');
    payloadDir = p.join(tmp.path, 'mx_store');
    await Directory(payloadDir).create();

    final textFile = File(p.join(payloadDir, 'text.php'));
    await textFile.writeAsString('<?php echo 1;');
    final binaryFile = File(p.join(payloadDir, 'binary.bin'));
    await binaryFile.writeAsBytes([1, 2, 3]);

    final db = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 13,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE payloads (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              type TEXT NOT NULL DEFAULT 'php',
              file_path TEXT NOT NULL DEFAULT '',
              is_default INTEGER NOT NULL DEFAULT 0,
              description TEXT,
              tags TEXT,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
        },
      ),
    );

    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('payloads', {
      'name': 'text.php',
      'type': 'php',
      'file_path': textFile.path,
      'is_default': 1,
      'description': 'text payload',
      'tags': 'php,test',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('payloads', {
      'name': 'Binary.bin',
      'type': 'other',
      'file_path': binaryFile.path,
      'is_default': 0,
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('payloads', {
      'name': 'dup.php',
      'type': 'php',
      'file_path': '',
      'is_default': 0,
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('payloads', {
      'name': 'dup.php',
      'type': 'php',
      'file_path': '',
      'is_default': 1,
      'created_at': now,
      'updated_at': now,
    });

    await db.close();
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  test('lists payload metadata ordered by name', () async {
    final db = McpDatabase(dbPath);
    addTearDown(db.close);

    final rows = await db.listPayloadRows();

    expect(rows.map((row) => row['name']).toList(), [
      'Binary.bin',
      'dup.php',
      'dup.php',
      'text.php',
    ]);
    expect(rows.last['description'], 'text payload');
    expect(rows.last['tags'], 'php,test');
  });

  test('finds a payload by id', () async {
    final db = McpDatabase(dbPath);
    addTearDown(db.close);

    final rows = await db.listPayloadRows();
    final target = rows.firstWhere((row) => row['name'] == 'text.php');
    final row = await db.getPayloadRow(target['id'] as int);

    expect(row, isNotNull);
    final found = row!;
    expect(found['name'], 'text.php');
    expect(found['file_path'], isNotEmpty);
  });

  test('returns null for an unknown payload id', () async {
    final db = McpDatabase(dbPath);
    addTearDown(db.close);

    expect(await db.getPayloadRow(999), isNull);
  });

  test(
    'returns every row sharing a name so callers can reject ambiguity',
    () async {
      final db = McpDatabase(dbPath);
      addTearDown(db.close);

      final rows = await db.findPayloadRowsByName('dup.php');

      expect(rows, hasLength(2));
      expect(rows.map((row) => row['is_default']).toList(), [0, 1]);
    },
  );
}
