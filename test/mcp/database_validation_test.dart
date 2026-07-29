import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/mcp/db.dart';
import 'package:path/path.dart' as p;

void main() {
  group('McpDatabase validation', () {
    test('non-existent path throws clear error, does not create empty db', () async {
      McpDatabase.initFfi();

      final tmpDir = Directory.systemTemp.createTempSync('matrix_mcp_test_');
      addTearDown(() => tmpDir.deleteSync(recursive: true));

      final dbPath = p.join(tmpDir.path, 'nonexistent_matrix.db');

      // 确认路径确实不存在
      expect(File(dbPath).existsSync(), isFalse);

      final db = McpDatabase(dbPath);
      final ex = await exTo(() => db.database);
      expect(ex, isNotNull, reason: '不存在的数据库应抛出异常');
      expect('$ex', contains('数据库不存在'));
      expect('$ex', contains(dbPath));

      // 确认路径未被静默创建
      expect(File(dbPath).existsSync(), isFalse,
          reason: '不可用的空 SQLite 文件不应被创建');

      await db.close();
    });
  });
}

/// 将 [fn] 可能抛出的异常捕获返回，没抛则返回 null。
Future<Object?> exTo(Future<void> Function() fn) async {
  try {
    await fn();
    return null;
  } catch (e) {
    return e;
  }
}
