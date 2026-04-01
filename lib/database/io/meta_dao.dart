import 'package:sqflite/sqflite.dart';

class MetaDao {
  MetaDao(this._databaseProvider);

  final Future<Database> Function() _databaseProvider;

  Future<String?> getMetaValue(String key) async {
    final db = await _databaseProvider();
    final rows = await db.query('meta', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setMetaValue(String key, String value) async {
    final db = await _databaseProvider();
    await db.insert(
      'meta',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
