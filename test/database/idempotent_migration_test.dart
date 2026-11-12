import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/database/database_helper_io.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 回归：库里列已存在但 user_version 仍偏低时，升级不能因为
/// `duplicate column name` 反复失败（真实用户库出现过）。
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('ensureColumn 对已存在的列是空操作', () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);

    await db.execute('CREATE TABLE webshells (id INTEGER PRIMARY KEY)');

    await DatabaseHelperIo.ensureColumn(
      db,
      'webshells',
      'secret_key',
      "TEXT NOT NULL DEFAULT 'key'",
    );
    expect(await DatabaseHelperIo.columnExists(db, 'webshells', 'secret_key'),
        isTrue);

    // 第二次（模拟半升级状态下的重试）不应抛异常。
    await DatabaseHelperIo.ensureColumn(
      db,
      'webshells',
      'secret_key',
      "TEXT NOT NULL DEFAULT 'key'",
    );

    await db.insert('webshells', {'id': 1});
    final rows = await db.query('webshells');
    expect(rows.single['secret_key'], 'key');
  });

  test('ensureColumn 会补上缺失的 cryption 列', () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);

    await db.execute('''
      CREATE TABLE webshells (
        id INTEGER PRIMARY KEY,
        secret_key TEXT NOT NULL DEFAULT 'key'
      )
    ''');

    await DatabaseHelperIo.ensureColumn(
      db,
      'webshells',
      'cryption',
      "TEXT NOT NULL DEFAULT ''",
    );
    expect(await DatabaseHelperIo.columnExists(db, 'webshells', 'cryption'),
        isTrue);
  });

  test('旧 Godzilla 连接器拆分：不覆盖已有 cryption', () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);

    await db.execute('''
      CREATE TABLE webshells (
        id INTEGER PRIMARY KEY,
        connector_type TEXT NOT NULL DEFAULT '',
        cryption TEXT NOT NULL DEFAULT ''
      )
    ''');
    await db.insert('webshells', {
      'id': 1,
      'connector_type': 'jsp_godzilla_raw',
      'cryption': '',
    });
    await db.insert('webshells', {
      'id': 2,
      'connector_type': 'jsp_godzilla',
      'cryption': 'JAVA_AES_RAW',
    });
    await db.insert('webshells', {
      'id': 3,
      'connector_type': 'asp_godzilla_plainraw',
      'cryption': '',
    });

    await DatabaseHelperIo.migrateLegacyGodzillaConnectorTypes(db);

    final rows = {
      for (final r in await db.query('webshells'))
        r['id'] as int: (
          connector: r['connector_type'] as String,
          cryption: r['cryption'] as String,
        ),
    };
    expect(rows[1]!.connector, 'jsp_godzilla');
    expect(rows[1]!.cryption, 'JAVA_AES_RAW');
    expect(rows[2]!.connector, 'jsp_godzilla');
    // 已存在的 cryption 不被清空。
    expect(rows[2]!.cryption, 'JAVA_AES_RAW');
    expect(rows[3]!.connector, 'asp_godzilla');
    expect(rows[3]!.cryption, 'ASP_RAW');
  });
}
