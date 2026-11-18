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
import 'io/suo5_profile_dao.dart';
import 'io/suo6_profile_dao.dart';
import 'io/meta_dao.dart';
import '../models/project.dart';
import '../models/webshell.dart';
import '../models/payload.dart';
import '../models/frp_profile.dart';
import '../models/suo5_profile.dart';
import '../models/suo6_profile.dart';
import '../services/frp_client_service.dart';
import 'legacy_sandbox_migrator.dart';
import 'matrix_storage.dart';
import 'storage_permissions.dart';
import 'io/credential_migration.dart';

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
  late final Suo5ProfileDao _suo5ProfileDao = Suo5ProfileDao(() => database);
  late final Suo6ProfileDao _suo6ProfileDao = Suo6ProfileDao(() => database);
  late final MetaDao _metaDao = MetaDao(() => database);

  /// 打开中的 Future：并发首次访问只打开一次数据库。
  ///
  /// 旧写法 `if (_database != null) ... _database = await _initDatabase();`
  /// 在启动阶段多个页面同时取库时会开出两个连接，导致迁移/种子并发、
  /// 甚至 `database is locked`。
  Future<Database>? _databaseFuture;

  Future<Database> get database {
    final opened = _database;
    if (opened != null) return Future<Database>.value(opened);
    return _databaseFuture ??= _initDatabase().then(
      (db) {
        _database = db;
        return db;
      },
      onError: (Object error, StackTrace stack) {
        // 打开失败允许下次重试，不缓存失败结果。
        _databaseFuture = null;
        return Future<Database>.error(error, stack);
      },
    );
  }

  Future<Database> _initDatabase() async {
    final storageDirectory = await getMatrixStorageDirectory();
    final path = join(storageDirectory.path, 'matrix.db');
    await _migrateLegacySandboxData(storageDirectory.path, path);
    // 打开前先收敛目录权限，打开后再收敛 db/WAL/SHM 文件权限。
    await hardenPermissions(
      dirPath: storageDirectory.path,
      fileNames: matrixDatabaseArtifacts,
    );

    final db = await openDatabase(
      path,
      version: 15,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    // 打开后再次收敛：此时 WAL/SHM 伴随文件已存在。
    await hardenPermissions(
      dirPath: storageDirectory.path,
      fileNames: matrixDatabaseArtifacts,
    );
    return db;
  }

  Future<void> _migrateLegacySandboxData(
    String documentsPath,
    String databasePath,
  ) async {
    if (!Platform.isMacOS) return;
    final homePath = Platform.environment['HOME'];
    if (homePath == null || homePath.isEmpty) return;
    final legacyDocumentsPath = join(
      homePath,
      'Library',
      'Containers',
      'com.example.matrix',
      'Data',
      'Documents',
    );
    final destinationExists = await File(databasePath).exists();
    final canReplaceDestination =
        destinationExists && await _isPristineDestination(databasePath);
    final oldDocumentsPath = (await getApplicationDocumentsDirectory()).path;
    for (final sourcePath in [legacyDocumentsPath, oldDocumentsPath]) {
      if (normalize(sourcePath) == normalize(documentsPath)) continue;
      final migrated = await LegacySandboxMigrator.migrateFrom(
        sourceDirectory: sourcePath,
        destinationDirectory: documentsPath,
        replaceDestination: canReplaceDestination,
      );
      if (migrated) return;
    }
  }

  Future<bool> _isPristineDestination(String databasePath) async {
    Database? database;
    try {
      database = await openDatabase(databasePath, readOnly: true);
      const userDataTables = [
        'projects',
        'webshells',
        'frp_profiles',
        'suo5_profiles',
        'suo6_profiles',
      ];
      for (final table in userDataTables) {
        final rows = await database.rawQuery('SELECT 1 FROM $table LIMIT 1');
        if (rows.isNotEmpty) return false;
      }
      final userPayloads = await database.rawQuery(
        'SELECT 1 FROM payloads WHERE is_default = 0 LIMIT 1',
      );
      return userPayloads.isEmpty;
    } catch (_) {
      return false;
    } finally {
      await database?.close();
    }
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
        secret_key TEXT NOT NULL DEFAULT 'key',
        cryption TEXT NOT NULL DEFAULT '',
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

    await db.execute('''
      CREATE TABLE suo5_profiles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        project_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        target_url TEXT NOT NULL,
        listen_host TEXT NOT NULL DEFAULT '127.0.0.1',
        listen_port INTEGER NOT NULL DEFAULT 1080,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (project_id) REFERENCES projects (id)
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_suo5_project ON suo5_profiles(project_id)',
    );

    await db.execute('''
      CREATE TABLE suo6_profiles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        project_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        target_url TEXT NOT NULL,
        listen_host TEXT NOT NULL DEFAULT '127.0.0.1',
        listen_port INTEGER NOT NULL DEFAULT 1080,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (project_id) REFERENCES projects (id)
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_suo6_project ON suo6_profiles(project_id)',
    );
  }

  /// 幂等加列：列已存在则跳过。
  ///
  /// 历史遗留：某些用户的库里列已经存在，但 `user_version` 仍停在旧值
  /// （升级中途崩溃 / 手改过库），直接 `ALTER TABLE` 会报
  /// `duplicate column name` 并让启动循环失败。
  static Future<bool> columnExists(
    Database db,
    String table,
    String column,
  ) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.any((row) => (row['name'] as String?) == column);
  }

  static Future<void> ensureColumn(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    if (await columnExists(db, table, column)) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  }


  /// 把旧的“连接器类型 = 加密器”（如 `php_godzilla_raw`）拆成
  /// “架构连接器 + 独立加密器”。
  ///
  /// 只处理带 `_godzilla_` 后缀的旧类型，且不会覆盖已有的 `cryption`，
  /// 避免把用户已经选好的加密器清空。
  static Future<void> migrateLegacyGodzillaConnectorTypes(Database db) async {
    await db.execute(r'''
      UPDATE webshells
      SET cryption = CASE connector_type
            WHEN 'php_godzilla_raw' THEN 'PHP_XOR_RAW'
            WHEN 'php_godzilla_eval' THEN 'PHP_EVAL_XOR_BASE64'
            WHEN 'jsp_godzilla_raw' THEN 'JAVA_AES_RAW'
            WHEN 'aspx_godzilla_raw' THEN 'CSHAP_AES_RAW'
            WHEN 'asp_godzilla_raw' THEN 'ASP_XOR_RAW'
            WHEN 'asp_godzilla_b64' THEN 'ASP_BASE64'
            WHEN 'asp_godzilla_plainraw' THEN 'ASP_RAW'
            ELSE cryption
          END,
          connector_type = substr(
            connector_type,
            1,
            instr(connector_type, '_godzilla_') + 8
          )
      WHERE instr(connector_type, '_godzilla_') > 0
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await ensureColumn(
        db,
        'projects',
        'domain',
        'TEXT NOT NULL DEFAULT ""',
      );
    }
    if (oldVersion < 3) {
      await ensureColumn(
        db,
        'webshells',
        'type',
        "TEXT NOT NULL DEFAULT 'php'",
      );
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
        'SELECT id, name, type, content, description, tags, created_at, updated_at FROM payloads',
      );

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

      final storageDir = await getMatrixStorageDirectory();
      final payloadsDir = Directory('${storageDir.path}/mx_store');
      if (!payloadsDir.existsSync()) await payloadsDir.create(recursive: true);

      for (final row in rows) {
        final id = row['id'] as int;
        final name = row['name'] as String;
        final content = (row['content'] as String?) ?? '';
        final file = File('${payloadsDir.path}/${_hashedFileName(id, name)}');
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
        'CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );
      await ensureColumn(
        db,
        'payloads',
        'is_default',
        'INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 8) {
      await ensureColumn(
        db,
        'webshells',
        'connector_type',
        "TEXT NOT NULL DEFAULT 'php_eval'",
      );
      // 旧 JSP 类型自动映射到 jsp_classloader
      await db.execute(
        "UPDATE webshells SET connector_type = 'jsp_classloader' WHERE type = 'jsp'",
      );
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
    if (oldVersion < 12) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS suo5_profiles (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          project_id INTEGER NOT NULL,
          name TEXT NOT NULL,
          target_url TEXT NOT NULL,
          listen_host TEXT NOT NULL DEFAULT '127.0.0.1',
          listen_port INTEGER NOT NULL DEFAULT 1080,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          FOREIGN KEY (project_id) REFERENCES projects (id)
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_suo5_project ON suo5_profiles(project_id)',
      );
    }
    if (oldVersion < 13) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS suo6_profiles (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          project_id INTEGER NOT NULL,
          name TEXT NOT NULL,
          target_url TEXT NOT NULL,
          listen_host TEXT NOT NULL DEFAULT '127.0.0.1',
          listen_port INTEGER NOT NULL DEFAULT 1080,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          FOREIGN KEY (project_id) REFERENCES projects (id)
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_suo6_project ON suo6_profiles(project_id)',
      );
    }
    if (oldVersion < 14) {
      await ensureColumn(
        db,
        'webshells',
        'secret_key',
        "TEXT NOT NULL DEFAULT 'key'",
      );
    }
    if (oldVersion < 15) {
      await ensureColumn(
        db,
        'webshells',
        'cryption',
        "TEXT NOT NULL DEFAULT ''",
      );
      await migrateLegacyGodzillaConnectorTypes(db);
    }
  }

  Future<Project> createProject(
    String name, {
    required String domain,
    String? description,
  }) async {
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
    final storageDir = await getMatrixStorageDirectory();
    final dir = Directory('${storageDir.path}/mx_store');
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
    String secretKey = 'key',
    String cryption = '',
    String method = 'POST',
    String type = 'php',
    String connectorType = 'php_eval',
  }) async {
    return _webshellDao.createWebshell(
      projectId,
      name: name,
      url: url,
      password: password,
      secretKey: secretKey,
      cryption: cryption,
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

  // ── Suo5 Profiles ────────────────────────────────────────────────────────────

  Future<Suo5Profile> createSuo5Profile({
    required int projectId,
    required String name,
    required String targetUrl,
    required String listenHost,
    required int listenPort,
  }) => _suo5ProfileDao.createSuo5Profile(
    projectId: projectId,
    name: name,
    targetUrl: targetUrl,
    listenHost: listenHost,
    listenPort: listenPort,
  );

  Future<List<Suo5Profile>> getSuo5ProfilesByProject(int projectId) =>
      _suo5ProfileDao.getSuo5ProfilesByProject(projectId);

  Future<Suo5Profile?> updateSuo5Profile(Suo5Profile profile) =>
      _suo5ProfileDao.updateSuo5Profile(profile);

  Future<int> deleteSuo5Profile(int id) =>
      _suo5ProfileDao.deleteSuo5Profile(id);

  // ── Suo6 Profiles ────────────────────────────────────────────────────────────

  Future<Suo6Profile> createSuo6Profile({
    required int projectId,
    required String name,
    required String targetUrl,
    required String listenHost,
    required int listenPort,
  }) => _suo6ProfileDao.createSuo6Profile(
    projectId: projectId,
    name: name,
    targetUrl: targetUrl,
    listenHost: listenHost,
    listenPort: listenPort,
  );

  Future<List<Suo6Profile>> getSuo6ProfilesByProject(int projectId) =>
      _suo6ProfileDao.getSuo6ProfilesByProject(projectId);

  Future<Suo6Profile?> updateSuo6Profile(Suo6Profile profile) =>
      _suo6ProfileDao.updateSuo6Profile(profile);

  Future<int> deleteSuo6Profile(int id) =>
      _suo6ProfileDao.deleteSuo6Profile(id);
}

final _io = DatabaseHelperIo();

/// 把历史明文凭据就地加密（幂等）；加密器未就绪时直接返回 0。
Future<int> encryptLegacyCredentials() async {
  final db = await _io.database;
  return encryptLegacyCredentialsIn(db);
}

Future<Project> createProject(
  String name, {
  required String domain,
  String? description,
}) => _io.createProject(name, domain: domain, description: description);

Future<List<Project>> getAllProjects() => _io.getAllProjects();

Future<Project?> getProjectById(int id) => _io.getProjectById(id);

Future<int> updateProject(Project project) => _io.updateProject(project);

Future<int> deleteProject(int id) => _io.deleteProject(id);

Future<Webshell> createWebshell(
  int projectId, {
  required String name,
  required String url,
  String? password,
  String secretKey = 'key',
  String cryption = '',
  String method = 'POST',
  String type = 'php',
  String connectorType = 'php_eval',
}) => _io.createWebshell(
  projectId,
  name: name,
  url: url,
  password: password,
  secretKey: secretKey,
  cryption: cryption,
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
}) => _io.createPayload(
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
}) => _io.createFrpProfile(
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
}) => _io.updateFrpProfile(
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

// Suo5 Profiles 顶层方法
Future<Suo5Profile> createSuo5Profile({
  required int projectId,
  required String name,
  required String targetUrl,
  required String listenHost,
  required int listenPort,
}) => _io.createSuo5Profile(
  projectId: projectId,
  name: name,
  targetUrl: targetUrl,
  listenHost: listenHost,
  listenPort: listenPort,
);

Future<List<Suo5Profile>> getSuo5ProfilesByProject(int projectId) =>
    _io.getSuo5ProfilesByProject(projectId);

Future<Suo5Profile?> updateSuo5Profile(Suo5Profile profile) =>
    _io.updateSuo5Profile(profile);

Future<int> deleteSuo5Profile(int id) => _io.deleteSuo5Profile(id);

// Suo6 Profiles 顶层方法
Future<Suo6Profile> createSuo6Profile({
  required int projectId,
  required String name,
  required String targetUrl,
  required String listenHost,
  required int listenPort,
}) => _io.createSuo6Profile(
  projectId: projectId,
  name: name,
  targetUrl: targetUrl,
  listenHost: listenHost,
  listenPort: listenPort,
);

Future<List<Suo6Profile>> getSuo6ProfilesByProject(int projectId) =>
    _io.getSuo6ProfilesByProject(projectId);

Future<Suo6Profile?> updateSuo6Profile(Suo6Profile profile) =>
    _io.updateSuo6Profile(profile);

Future<int> deleteSuo6Profile(int id) => _io.deleteSuo6Profile(id);
