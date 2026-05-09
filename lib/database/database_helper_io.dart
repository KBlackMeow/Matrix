import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
// ConflictAlgorithm is exported by sqflite
import 'package:path_provider/path_provider.dart';

import 'io/project_dao.dart';
import 'io/payload_dao.dart';
import 'io/webshell_dao.dart';
import 'io/frp_profile_dao.dart';
import 'io/meta_dao.dart';
import '../models/project.dart';
import '../models/webshell.dart';
import '../models/payload.dart';
import '../models/frp_profile.dart';
import '../services/frp_client_service.dart';

/// 桌面/移动端 SQLite 实现
class DatabaseHelperIo {
  static final DatabaseHelperIo _instance = DatabaseHelperIo._internal();
  static Database? _database;

  factory DatabaseHelperIo() => _instance;

  DatabaseHelperIo._internal();

  late final ProjectDao _projectDao = ProjectDao(() => database);
  late final WebshellDao _webshellDao = WebshellDao(() => database);
  late final PayloadDao _payloadDao = PayloadDao(
        () => database,
        payloadsDirProvider: _payloadsDir,
        hashedFileName: _hashedFileName,
      );
  late final FrpProfileDao _frpProfileDao = FrpProfileDao(() => database);
  late final MetaDao _metaDao = MetaDao(() => database);

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
      version: 11,
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

    await db.execute(
      'CREATE INDEX idx_webshell_project ON webshells(project_id)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX idx_payloads_name_is_default_unique ON payloads(name, is_default)',
    );

    await db.execute('''
      CREATE TABLE frp_profiles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        server_addr TEXT NOT NULL,
        server_port INTEGER NOT NULL DEFAULT 7000,
        token TEXT NOT NULL DEFAULT '',
        proxy_name TEXT NOT NULL DEFAULT 'shell',
        remote_port INTEGER NOT NULL DEFAULT 6000,
        local_addr TEXT NOT NULL DEFAULT '127.0.0.1',
        local_port INTEGER NOT NULL DEFAULT 4444,
        version TEXT NOT NULL DEFAULT '',
        use_tcp_mux INTEGER NOT NULL DEFAULT 1,
        auth_mode TEXT NOT NULL DEFAULT 'md5',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
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
    if (oldVersion < 7) {
      await db.execute(
          'CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
      await db.execute(
          'ALTER TABLE payloads ADD COLUMN is_default INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 8) {
      await db.execute(
          "ALTER TABLE webshells ADD COLUMN connector_type TEXT NOT NULL DEFAULT 'php_eval'");
      // 旧 JSP 类型自动映射到 jsp_classloader
      await db.execute(
          "UPDATE webshells SET connector_type = 'jsp_classloader' WHERE type = 'jsp'");
    }
    if (oldVersion < 10) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS frp_profiles (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          server_addr TEXT NOT NULL,
          server_port INTEGER NOT NULL DEFAULT 7000,
          token TEXT NOT NULL DEFAULT '',
          proxy_name TEXT NOT NULL DEFAULT 'shell',
          remote_port INTEGER NOT NULL DEFAULT 6000,
          local_addr TEXT NOT NULL DEFAULT '127.0.0.1',
          local_port INTEGER NOT NULL DEFAULT 4444,
          version TEXT NOT NULL DEFAULT '',
          use_tcp_mux INTEGER NOT NULL DEFAULT 1,
          auth_mode TEXT NOT NULL DEFAULT 'md5',
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
    }
    if (oldVersion < 11) {
      // 先清理历史重复，避免创建唯一索引失败
      await db.execute('''
        DELETE FROM payloads
        WHERE id NOT IN (
          SELECT MAX(id)
          FROM payloads
          GROUP BY name, is_default
        )
      ''');
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_payloads_name_is_default_unique ON payloads(name, is_default)',
      );
    }
  }

  Future<Project> createProject(String name, {required String domain, String? description}) async {
    return _projectDao.createProject(
      name,
      domain: domain,
      description: description,
    );
  }

  Future<List<Project>> getAllProjects() async {
    return _projectDao.getAllProjects();
  }

  Future<Project?> getProjectById(int id) async {
    return _projectDao.getProjectById(id);
  }

  Future<int> updateProject(Project project) async {
    return _projectDao.updateProject(project);
  }

  Future<int> deleteProject(int id) async {
    return _projectDao.deleteProject(id);
  }

  // ── Payload 文件目录 ────────────────────────────────────────────────────────

  // 盐值：用于混淆文件名，不对外暴露
  static const _kSalt = 'mx_payload_s3cr3t_2026';

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

  // ── Payload CRUD ────────────────────────────────────────────────────────────

  // ── Meta 键值对 ─────────────────────────────────────────────────────────────

  Future<String?> getMetaValue(String key) async {
    return _metaDao.getMetaValue(key);
  }

  Future<void> setMetaValue(String key, String value) async {
    return _metaDao.setMetaValue(key, value);
  }

  Future<Payload> createPayload({
    required String name,
    required String type,
    required String content,
    bool isDefault = false,
    String? description,
    String? tags,
  }) async {
    return _payloadDao.createPayload(
      name: name,
      type: type,
      content: content,
      isDefault: isDefault,
      description: description,
      tags: tags,
    );
  }

  Future<List<Payload>> getAllPayloads() async {
    return _payloadDao.getAllPayloads();
  }

  Future<int> updatePayload(Payload payload) async {
    return _payloadDao.updatePayload(payload);
  }

  Future<int> deletePayload(int id) async {
    return _payloadDao.deletePayload(id);
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
    return _webshellDao.createWebshell(
      projectId,
      name: name,
      url: url,
      password: password,
      method: method,
      type: type,
      connectorType: connectorType,
    );
  }

  Future<List<Webshell>> getWebshellsByProject(int projectId) async {
    return _webshellDao.getWebshellsByProject(projectId);
  }

  Future<int> updateWebshell(Webshell webshell) async {
    return _webshellDao.updateWebshell(webshell);
  }

  Future<int> deleteWebshell(int id) async {
    return _webshellDao.deleteWebshell(id);
  }

  // ── FRP Profiles ─────────────────────────────────────────────────────────────

  Future<FrpProfile> createFrpProfile({
    required String name,
    required String serverAddr,
    required int serverPort,
    required String token,
    required String proxyName,
    required int remotePort,
    required String localAddr,
    required int localPort,
    required String version,
    required bool useTcpMux,
    required FrpAuthMode authMode,
  }) async {
    return _frpProfileDao.createFrpProfile(
      name: name,
      serverAddr: serverAddr,
      serverPort: serverPort,
      token: token,
      proxyName: proxyName,
      remotePort: remotePort,
      localAddr: localAddr,
      localPort: localPort,
      version: version,
      useTcpMux: useTcpMux,
      authMode: authMode,
    );
  }

  Future<FrpProfile?> updateFrpProfile({
    required int id,
    required String name,
    required String serverAddr,
    required int serverPort,
    required String token,
    required String proxyName,
    required int remotePort,
    required String localAddr,
    required int localPort,
    required String version,
    required bool useTcpMux,
    required FrpAuthMode authMode,
  }) async {
    return _frpProfileDao.updateFrpProfile(
      id: id,
      name: name,
      serverAddr: serverAddr,
      serverPort: serverPort,
      token: token,
      proxyName: proxyName,
      remotePort: remotePort,
      localAddr: localAddr,
      localPort: localPort,
      version: version,
      useTcpMux: useTcpMux,
      authMode: authMode,
    );
  }

  Future<List<FrpProfile>> getAllFrpProfiles() async {
    return _frpProfileDao.getAllFrpProfiles();
  }

  Future<int> deleteFrpProfile(int id) async {
    return _frpProfileDao.deleteFrpProfile(id);
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

// FRP Profiles 顶层方法
Future<FrpProfile> createFrpProfile({
  required String name,
  required String serverAddr,
  required int serverPort,
  required String token,
  required String proxyName,
  required int remotePort,
  required String localAddr,
  required int localPort,
  required String version,
  required bool useTcpMux,
  required FrpAuthMode authMode,
}) =>
    _io.createFrpProfile(
      name: name,
      serverAddr: serverAddr,
      serverPort: serverPort,
      token: token,
      proxyName: proxyName,
      remotePort: remotePort,
      localAddr: localAddr,
      localPort: localPort,
      version: version,
      useTcpMux: useTcpMux,
      authMode: authMode,
    );

Future<List<FrpProfile>> getAllFrpProfiles() => _io.getAllFrpProfiles();

Future<FrpProfile?> updateFrpProfile({
  required int id,
  required String name,
  required String serverAddr,
  required int serverPort,
  required String token,
  required String proxyName,
  required int remotePort,
  required String localAddr,
  required int localPort,
  required String version,
  required bool useTcpMux,
  required FrpAuthMode authMode,
}) =>
    _io.updateFrpProfile(
      id: id,
      name: name,
      serverAddr: serverAddr,
      serverPort: serverPort,
      token: token,
      proxyName: proxyName,
      remotePort: remotePort,
      localAddr: localAddr,
      localPort: localPort,
      version: version,
      useTcpMux: useTcpMux,
      authMode: authMode,
    );

Future<int> deleteFrpProfile(int id) => _io.deleteFrpProfile(id);
