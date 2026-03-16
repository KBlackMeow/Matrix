import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
// ConflictAlgorithm is exported by sqflite
import 'package:path_provider/path_provider.dart';

import '../models/project.dart';
import '../models/webshell.dart';
import '../models/payload.dart';
import '../models/dictionary.dart';

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
      version: 9,
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
        connector_type TEXT NOT NULL DEFAULT 'php_eval',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (project_id) REFERENCES projects (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

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

    await db.execute('''
      CREATE TABLE dictionaries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        category TEXT NOT NULL DEFAULT 'custom',
        file_path TEXT NOT NULL DEFAULT '',
        line_count INTEGER NOT NULL DEFAULT 0,
        file_size INTEGER NOT NULL DEFAULT 0,
        is_default INTEGER NOT NULL DEFAULT 0,
        description TEXT,
        tags TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_info_project ON info_collection(project_id)',
    );
    await db.execute(
      'CREATE INDEX idx_webshell_project ON webshells(project_id)',
    );

    await db.execute('''
      CREATE TABLE scan_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        project_id INTEGER,
        scan_type TEXT NOT NULL,
        target TEXT NOT NULL,
        config_json TEXT,
        log_text TEXT,
        status TEXT NOT NULL DEFAULT 'running',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (project_id) REFERENCES projects (id)
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_scan_sessions_project_type ON scan_sessions(project_id, scan_type)',
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
    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS payloads (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          type TEXT NOT NULL DEFAULT 'php',
          content TEXT NOT NULL,
          description TEXT,
          tags TEXT,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
    }
    if (oldVersion < 5) {
      // 读取旧版所有 payload 的内容，迁移到本地文件
      final rows = await db.rawQuery(
          'SELECT id, name, type, content, description, tags, created_at, updated_at FROM payloads');

      // 创建新表（用 file_path 替换 content）
      await db.execute('''
        CREATE TABLE payloads_v5 (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          type TEXT NOT NULL DEFAULT 'php',
          file_path TEXT NOT NULL DEFAULT '',
          description TEXT,
          tags TEXT,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');

      final docsDir = await getApplicationDocumentsDirectory();
      final payloadsDir = Directory('${docsDir.path}/mx_store');
      if (!payloadsDir.existsSync()) await payloadsDir.create(recursive: true);

      for (final row in rows) {
        final id = row['id'] as int;
        final name = row['name'] as String;
        final content = (row['content'] as String?) ?? '';
        final file = File(
            '${payloadsDir.path}/${_hashedFileName(id, name)}');
        await file.writeAsString(content);

        await db.insert('payloads_v5', {
          'id': id,
          'name': name,
          'type': (row['type'] as String?) ?? 'php',
          'file_path': file.path,
          'description': row['description'],
          'tags': row['tags'],
          'created_at': row['created_at'] as int,
          'updated_at': row['updated_at'] as int,
        });
      }

      await db.execute('DROP TABLE payloads');
      await db.execute('ALTER TABLE payloads_v5 RENAME TO payloads');
    }
    if (oldVersion < 6) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS dictionaries (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          category TEXT NOT NULL DEFAULT 'custom',
          file_path TEXT NOT NULL DEFAULT '',
          line_count INTEGER NOT NULL DEFAULT 0,
          file_size INTEGER NOT NULL DEFAULT 0,
          description TEXT,
          tags TEXT,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
    }
    if (oldVersion < 7) {
      await db.execute(
          'CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
      await db.execute(
          'ALTER TABLE payloads ADD COLUMN is_default INTEGER NOT NULL DEFAULT 0');
      await db.execute(
          'ALTER TABLE dictionaries ADD COLUMN is_default INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 8) {
      await db.execute(
          "ALTER TABLE webshells ADD COLUMN connector_type TEXT NOT NULL DEFAULT 'php_eval'");
      // 旧 JSP 类型自动映射到 jsp_classloader
      await db.execute(
          "UPDATE webshells SET connector_type = 'jsp_classloader' WHERE type = 'jsp'");
    }
    if (oldVersion < 9) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS scan_sessions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          project_id INTEGER,
          scan_type TEXT NOT NULL,
          target TEXT NOT NULL,
          config_json TEXT,
          log_text TEXT,
          status TEXT NOT NULL DEFAULT 'running',
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          FOREIGN KEY (project_id) REFERENCES projects (id)
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_scan_sessions_project_type ON scan_sessions(project_id, scan_type)',
      );
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
    await db.delete('info_collection', where: 'project_id = ?', whereArgs: [id]);
    await db.delete('webshells', where: 'project_id = ?', whereArgs: [id]);
    await db.delete('scan_sessions', where: 'project_id = ?', whereArgs: [id]);
    return db.delete('projects', where: 'id = ?', whereArgs: [id]);
  }

  // ── Scan Sessions（扫描会话持久化）────────────────────────────────────────────

  Future<int> createScanSession({
    required int projectId,
    required String scanType,
    required String target,
    String? configJson,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.insert('scan_sessions', {
      'project_id': projectId,
      'scan_type': scanType,
      'target': target,
      'config_json': configJson,
      'log_text': '',
      'status': 'running',
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<Map<String, dynamic>?> getLatestScanSession(int projectId, String scanType) async {
    final db = await database;
    final rows = await db.query(
      'scan_sessions',
      where: 'project_id = ? AND scan_type = ?',
      whereArgs: [projectId, scanType],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first.map((k, v) => MapEntry(k.toString(), v));
  }

  Future<void> updateScanSession(int id, {String? logText, String? status}) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final updates = <String, dynamic>{'updated_at': now};
    if (logText != null) updates['log_text'] = logText;
    if (status != null) updates['status'] = status;
    await db.update('scan_sessions', updates, where: 'id = ?', whereArgs: [id]);
  }

  /// 启动时清理遗留的 running 会话（强制退出时未能更新状态）
  Future<void> resetStaleRunningSessions() async {
    final db = await database;
    await db.update(
      'scan_sessions',
      {'status': 'interrupted', 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'status = ?',
      whereArgs: ['running'],
    );
  }

  Future<void> appendScanLog(int id, String text) async {
    final db = await database;
    final rows = await db.query('scan_sessions', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return;
    final current = rows.first['log_text'] as String? ?? '';
    final updated = current.isEmpty ? text : '$current\n$text';
    await db.update(
      'scan_sessions',
      {'log_text': updated, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ── Payload 文件目录 ────────────────────────────────────────────────────────

  // 盐值：用于混淆文件名，不对外暴露
  static const _kSalt = 'mx_payload_s3cr3t_2026';
  static const _kDictSalt = 'mx_dict_s3cr3t_2026';

  Future<Directory> _payloadsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/mx_store');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  /// Payload 文件名：MD5(盐 + id + originalName)
  static String _hashedFileName(int id, String name) {
    final input = utf8.encode('$_kSalt$id$name');
    return md5.convert(input).toString();
  }

  /// Dictionary 文件名：MD5(字典盐 + id + originalName)
  static String _hashedDictFileName(int id, String name) {
    final input = utf8.encode('$_kDictSalt$id$name');
    return md5.convert(input).toString();
  }

  // ── Payload CRUD ────────────────────────────────────────────────────────────

  // ── Meta 键值对 ─────────────────────────────────────────────────────────────

  Future<String?> getMetaValue(String key) async {
    final db = await database;
    final rows =
        await db.query('meta', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setMetaValue(String key, String value) async {
    final db = await database;
    await db.insert('meta', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Payload> createPayload({
    required String name,
    required String type,
    required String content,
    bool isDefault = false,
    String? description,
    String? tags,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;

    // 先插入行拿到自增 ID，file_path 暂时为空
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

    // 写入本地文件（MD5 混淆文件名）
    final dir = await _payloadsDir();
    final file = File('${dir.path}/${_hashedFileName(id, name)}');
    await file.writeAsString(content);

    // 更新 file_path
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
    final db = await database;
    // 默认项置顶，其余按更新时间倒序
    final maps = await db.query('payloads',
        orderBy: 'is_default DESC, updated_at DESC');
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
      result.add(Payload(
        id: m['id'] as int,
        name: m['name'] as String,
        type: (m['type'] as String?) ?? 'php',
        content: content,
        filePath: filePath,
        isDefault: (m['is_default'] as int? ?? 0) == 1,
        description: m['description'] as String?,
        tags: m['tags'] as String?,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int),
      ));
    }
    return result;
  }

  Future<int> updatePayload(Payload payload) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    // 同步更新文件内容
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
    final db = await database;
    // 先查询 file_path 再删文件
    final rows = await db.query('payloads',
        columns: ['file_path'], where: 'id = ?', whereArgs: [id]);
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

  // ── Dictionary CRUD ─────────────────────────────────────────────────────────

  Future<Dictionary> createDictionary({
    required String name,
    required String category,
    required List<int> bytes,
    bool isDefault = false,
    String? description,
    String? tags,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;

    // 先插入占位行拿到自增 ID
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

    // 写入哈希文件
    final dir = await _payloadsDir();
    final file = File('${dir.path}/${_hashedDictFileName(id, name)}');
    await file.writeAsBytes(bytes);

    // 统计行数和大小
    final lineCount = bytes.where((b) => b == 10).length +
        (bytes.isNotEmpty && bytes.last != 10 ? 1 : 0);
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
    final db = await database;
    // 默认项置顶
    final maps = await db.query('dictionaries',
        orderBy: 'is_default DESC, updated_at DESC');
    return maps.map((m) => Dictionary.fromMap(m)).toList();
  }

  /// 更新字典内容（用于内置字典与 asset 同步）
  Future<void> updateDictionaryContent(Dictionary dict, List<int> bytes) async {
    if (dict.filePath.isEmpty) return;
    final file = File(dict.filePath);
    await file.writeAsBytes(bytes);
    final lineCount = bytes.where((b) => b == 10).length +
        (bytes.isNotEmpty && bytes.last != 10 ? 1 : 0);
    final fileSize = bytes.length;
    final db = await database;
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

  /// 读取字典前 [maxLines] 行作为预览
  Future<String> readDictionaryPreview(String filePath,
      {int maxLines = 300}) async {
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
    final db = await database;
    final rows = await db.query('dictionaries',
        columns: ['file_path'], where: 'id = ?', whereArgs: [id]);
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

  Future<Webshell> createWebshell(
    int projectId, {
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
        'type': webshell.type,
        'method': webshell.method,
        'status': webshell.status,
        'connector_type': webshell.connectorType,
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
  String connectorType = 'php_eval',
}) =>
    _io.createWebshell(
      projectId,
      name: name,
      url: url,
      password: password,
      method: method,
      type: type,
      connectorType: connectorType,
    );

Future<List<Webshell>> getWebshellsByProject(int projectId) =>
    _io.getWebshellsByProject(projectId);

Future<int> updateWebshell(Webshell webshell) => _io.updateWebshell(webshell);

Future<int> deleteWebshell(int id) => _io.deleteWebshell(id);

// Meta 顶层方法
Future<String?> getMetaValue(String key) => _io.getMetaValue(key);
Future<void> setMetaValue(String key, String value) =>
    _io.setMetaValue(key, value);

// Payload 相关顶层方法

Future<Payload> createPayload({
  required String name,
  required String type,
  required String content,
  bool isDefault = false,
  String? description,
  String? tags,
}) =>
    _io.createPayload(
      name: name,
      type: type,
      content: content,
      isDefault: isDefault,
      description: description,
      tags: tags,
    );

Future<List<Payload>> getAllPayloads() => _io.getAllPayloads();

Future<int> updatePayload(Payload payload) => _io.updatePayload(payload);

Future<int> deletePayload(int id) => _io.deletePayload(id);

// Dictionary 相关顶层方法

Future<Dictionary> createDictionary({
  required String name,
  required String category,
  required List<int> bytes,
  bool isDefault = false,
  String? description,
  String? tags,
}) =>
    _io.createDictionary(
      name: name,
      category: category,
      bytes: bytes,
      isDefault: isDefault,
      description: description,
      tags: tags,
    );

Future<List<Dictionary>> getAllDictionaries() => _io.getAllDictionaries();

Future<void> updateDictionaryContent(Dictionary dict, List<int> bytes) =>
    _io.updateDictionaryContent(dict, bytes);

Future<String> readDictionaryPreview(String filePath, {int maxLines = 300}) =>
    _io.readDictionaryPreview(filePath, maxLines: maxLines);

Future<int> deleteDictionary(int id) => _io.deleteDictionary(id);

// Scan Sessions 顶层方法
Future<int> createScanSession({
  required int projectId,
  required String scanType,
  required String target,
  String? configJson,
}) =>
    _io.createScanSession(
      projectId: projectId,
      scanType: scanType,
      target: target,
      configJson: configJson,
    );

Future<Map<String, dynamic>?> getLatestScanSession(int projectId, String scanType) =>
    _io.getLatestScanSession(projectId, scanType);

Future<void> updateScanSession(int id, {String? logText, String? status}) =>
    _io.updateScanSession(id, logText: logText, status: status);

Future<void> appendScanLog(int id, String line) => _io.appendScanLog(id, line);

Future<void> resetStaleRunningSessions() => _io.resetStaleRunningSessions();
