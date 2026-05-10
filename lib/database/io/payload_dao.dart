import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../../models/payload.dart';

class PayloadDao {
  PayloadDao(
    this._databaseProvider, {
    required Future<Directory> Function() payloadsDirProvider,
    required String Function(int id, String name) hashedFileName,
  }) : _payloadsDirProvider = payloadsDirProvider,
       _hashedFileName = hashedFileName;

  final Future<Database> Function() _databaseProvider;
  final Future<Directory> Function() _payloadsDirProvider;
  final String Function(int id, String name) _hashedFileName;

  Future<Payload> createPayload({
    required String name,
    required String type,
    required String content,
    bool isDefault = false,
    String? description,
    String? tags,
  }) async {
    final db = await _databaseProvider();
    final now = DateTime.now().millisecondsSinceEpoch;

    final id = await db.insert('payloads', {
      'name': name,
      'type': type,
      'file_path': '',
      'is_default': isDefault ? 1 : 0,
      'description': description,
      'tags': tags,
      'created_at': now,
      'updated_at': now,
    });

    final dir = await _payloadsDirProvider();
    final file = File('${dir.path}/${_hashedFileName(id, name)}');
    await file.writeAsString(content);

    await db.update(
      'payloads',
      {'file_path': file.path},
      where: 'id = ?',
      whereArgs: [id],
    );

    return Payload(
      id: id,
      name: name,
      type: type,
      content: content,
      filePath: file.path,
      isDefault: isDefault,
      description: description,
      tags: tags,
      createdAt: DateTime.fromMillisecondsSinceEpoch(now),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(now),
    );
  }

  Future<List<Payload>> getAllPayloads() async {
    final db = await _databaseProvider();
    final maps = await db.query(
      'payloads',
      orderBy: 'is_default DESC, updated_at DESC',
    );
    final result = <Payload>[];
    for (final m in maps) {
      final filePath = (m['file_path'] as String?) ?? '';
      String content = '';
      if (filePath.isNotEmpty) {
        try {
          content = await File(filePath).readAsString();
        } catch (_) {
          content = '// 文件丢失: $filePath';
        }
      }
      result.add(
        Payload(
          id: m['id'] as int,
          name: m['name'] as String,
          type: (m['type'] as String?) ?? 'php',
          content: content,
          filePath: filePath,
          isDefault: (m['is_default'] as int? ?? 0) == 1,
          description: m['description'] as String?,
          tags: m['tags'] as String?,
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            m['created_at'] as int,
          ),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(
            m['updated_at'] as int,
          ),
        ),
      );
    }
    return result;
  }

  Future<int> updatePayload(Payload payload) async {
    final db = await _databaseProvider();
    final now = DateTime.now().millisecondsSinceEpoch;
    if (payload.filePath.isNotEmpty) {
      try {
        await File(payload.filePath).writeAsString(payload.content);
      } catch (_) {}
    }
    return db.update(
      'payloads',
      {
        'name': payload.name,
        'type': payload.type,
        'description': payload.description,
        'tags': payload.tags,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [payload.id],
    );
  }

  Future<int> deletePayload(int id) async {
    final db = await _databaseProvider();
    final rows = await db.query(
      'payloads',
      columns: ['file_path'],
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isNotEmpty) {
      final fp = rows.first['file_path'] as String? ?? '';
      if (fp.isNotEmpty) {
        try {
          await File(fp).delete();
        } catch (_) {}
      }
    }
    return db.delete('payloads', where: 'id = ?', whereArgs: [id]);
  }
}
