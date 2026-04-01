import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../../models/dictionary.dart';

class DictionaryDao {
  DictionaryDao(
    this._databaseProvider, {
    required Future<Directory> Function() payloadsDirProvider,
    required String Function(int id, String name) hashedDictFileName,
  })  : _payloadsDirProvider = payloadsDirProvider,
        _hashedDictFileName = hashedDictFileName;

  final Future<Database> Function() _databaseProvider;
  final Future<Directory> Function() _payloadsDirProvider;
  final String Function(int id, String name) _hashedDictFileName;

  Future<Dictionary> createDictionary({
    required String name,
    required String category,
    required List<int> bytes,
    bool isDefault = false,
    String? description,
    String? tags,
  }) async {
    final db = await _databaseProvider();
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await db.insert('dictionaries', {
      'name': name,
      'category': category,
      'file_path': '',
      'line_count': 0,
      'file_size': 0,
      'is_default': isDefault ? 1 : 0,
      'description': description,
      'tags': tags,
      'created_at': now,
      'updated_at': now,
    });

    final dir = await _payloadsDirProvider();
    final file = File('${dir.path}/${_hashedDictFileName(id, name)}');
    await file.writeAsBytes(bytes);

    final lineCount =
        bytes.where((b) => b == 10).length + (bytes.isNotEmpty && bytes.last != 10 ? 1 : 0);
    final fileSize = bytes.length;

    await db.update(
      'dictionaries',
      {'file_path': file.path, 'line_count': lineCount, 'file_size': fileSize},
      where: 'id = ?',
      whereArgs: [id],
    );

    return Dictionary(
      id: id,
      name: name,
      category: category,
      filePath: file.path,
      lineCount: lineCount,
      fileSize: fileSize,
      isDefault: isDefault,
      description: description,
      tags: tags,
      createdAt: DateTime.fromMillisecondsSinceEpoch(now),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(now),
    );
  }

  Future<List<Dictionary>> getAllDictionaries() async {
    final db = await _databaseProvider();
    final maps = await db.query('dictionaries', orderBy: 'is_default DESC, updated_at DESC');
    return maps.map((m) => Dictionary.fromMap(m)).toList();
  }

  Future<void> updateDictionaryContent(Dictionary dict, List<int> bytes) async {
    if (dict.filePath.isEmpty) return;
    final file = File(dict.filePath);
    await file.writeAsBytes(bytes);
    final lineCount =
        bytes.where((b) => b == 10).length + (bytes.isNotEmpty && bytes.last != 10 ? 1 : 0);
    final fileSize = bytes.length;
    final db = await _databaseProvider();
    await db.update(
      'dictionaries',
      {
        'line_count': lineCount,
        'file_size': fileSize,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [dict.id],
    );
  }

  Future<String> readDictionaryPreview(String filePath, {int maxLines = 300}) async {
    if (filePath.isEmpty) return '';
    try {
      final lines = <String>[];
      await File(filePath)
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .take(maxLines)
          .forEach(lines.add);
      return lines.join('\n');
    } catch (_) {
      return '// 文件丢失: $filePath';
    }
  }

  Future<int> deleteDictionary(int id) async {
    final db = await _databaseProvider();
    final rows = await db.query(
      'dictionaries',
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
    return db.delete('dictionaries', where: 'id = ?', whereArgs: [id]);
  }
}
