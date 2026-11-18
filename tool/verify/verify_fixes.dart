// ignore_for_file: avoid_print

/// 纯 Dart 自检脚本：不依赖 Flutter，可直接 `dart run tool/verify/verify_fixes.dart`。
///
/// 覆盖本次审计修复中可脱离 UI 验证的部分：
///   1. SerialQueue 的互斥、FIFO、异常不阻塞
///   2. 按 key 共享队列
///   3. MCP 日志脱敏
///   4. 本地数据文件权限收敛
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../lib/database/io/credential_migration.dart';
import '../../lib/exp/vulhub/services/exp_result.dart';
import '../../lib/exp/vulhub/services/rce_encoder.dart';

import '../../lib/core/async/serial_queue.dart';
import '../../lib/core/async/ttl_cache.dart';
import '../../lib/core/crypto/credential_cipher.dart';
import '../../lib/database/storage_permissions.dart';
import '../../lib/mcp/log_redaction.dart';
import '../../lib/services/remote_write_lock.dart';

int _failed = 0;
int _passed = 0;

void _check(bool ok, String name, [Object? detail]) {
  if (ok) {
    _passed++;
    print('  PASS  $name');
  } else {
    _failed++;
    print('  FAIL  $name${detail == null ? '' : '  → $detail'}');
  }
}

Future<void> main() async {
  print('== SerialQueue ==');
  await _testSerialQueue();
  await _testKeyedQueue();
  await _testExceptionDoesNotStall();

  print('== TtlCache ==');
  await _testTtlCache();

  print('== Log redaction ==');
  _testRedaction();

  print('== Storage permissions ==');

  await _testPermissions();

  print('== Remote write lock ==');
  await _testWriteLock();

  print('== RCE payload encoders ==');
  _testRceEncoder();

  print('== ExpResult semantics ==');
  _testExpResult();

  print('== Credential cipher ==');
  _testCipher();

  print('== Legacy credential migration ==');
  await _testCredentialMigration();

  print('\npassed=$_passed failed=$_failed');
  if (_failed > 0) exitCode = 1;
}

Future<void> _testSerialQueue() async {
  final queue = SerialQueue();
  var inFlight = 0;
  var maxInFlight = 0;
  final order = <int>[];
  final random = Random(7);

  final futures = <Future<void>>[];
  for (var i = 0; i < 20; i++) {
    futures.add(
      queue.run(() async {
        inFlight++;
        maxInFlight = max(maxInFlight, inFlight);
        await Future<void>.delayed(Duration(milliseconds: random.nextInt(5)));
        order.add(i);
        inFlight--;
      }),
    );
  }
  await Future.wait(futures);

  _check(maxInFlight == 1, '任务不重叠（maxInFlight=$maxInFlight）');
  _check(
    order.join(',') == List<int>.generate(20, (i) => i).join(','),
    '严格 FIFO',
    order.join(','),
  );
  _check(queue.pending == 0, '队列排空后 pending=0');
}

Future<void> _testKeyedQueue() async {
  final a = SerialQueue.forKey('https://target/shell.php');
  final b = SerialQueue.forKey('https://target/shell.php');
  final c = SerialQueue.forKey('https://other/shell.php');
  _check(identical(a, b), '同一 key 共享队列');
  _check(!identical(a, c), '不同 key 独立队列');
}

Future<void> _testExceptionDoesNotStall() async {
  final queue = SerialQueue();
  var reached = false;
  final failing = queue.run<void>(() async => throw StateError('boom'));
  await failing.then((_) {}, onError: (_) {});
  await queue.run(() async => reached = true);
  _check(reached, '前一个任务抛错后队列继续执行');
}

void _testRedaction() {
  final line = describeToolArguments(<String, dynamic>{
    'name': 'web1',
    'url': 'https://target/shell.php',
    'password': 'mAtrix_911',
    'secret_key': 'key',
    'token': 'frp-token',
    'content': 'A' * 5000,
  });
  _check(!line.contains('mAtrix_911'), 'password 不出现在日志', line);
  _check(!line.contains('secret_key=key'), 'secret_key 被遮蔽', line);
  _check(!line.contains('frp-token'), 'token 被遮蔽', line);
  _check(line.contains('content=<5000 chars>'), 'content 仅记长度', line);
  _check(line.contains('name=web1'), '普通字段保留', line);
  _check(isSensitiveArgument('Secret_Key'), '大小写不敏感');
}

Future<void> _testPermissions() async {  final dir = await Directory.systemTemp.createTemp('matrix_perm_test');
  try {
    final db = File('${dir.path}/matrix.db');
    await db.writeAsString('x');
    // 先放宽，确认收敛动作确实生效。
    await Process.run('chmod', ['777', dir.path]);
    await Process.run('chmod', ['666', db.path]);

    await hardenPermissions(
      dirPath: dir.path,
      fileNames: matrixDatabaseArtifacts,
    );

    final dirMode = (await dir.stat()).mode & 0x1FF;
    final dbMode = (await db.stat()).mode & 0x1FF;
    _check(dirMode == 0x1C0, '目录权限 700', dirMode.toRadixString(8));
    _check(dbMode == 0x180, '数据库权限 600', dbMode.toRadixString(8));

    // 文件不存在时不应抛错。
    await hardenPermissions(
      dirPath: dir.path,
      fileNames: const ['missing.db'],
    );
    _check(true, '缺失文件不抛错');
  } finally {
    await dir.delete(recursive: true);
  }
}

Future<void> _testWriteLock() async {
  final lock = RemoteWriteLockCoordinator();
  final order = <String>[];

  Future<void> op(String name, int delayMs) async {
    await lock.synchronize(
      // 不可解析的主机名：验证 DNS 失败不会阻断写操作（退化为主机名串行）。
      shellUrl: 'http://matrix.invalid/shell.php',
      remotePath: '/var/www/shell.php',
      operation: () async {
        order.add('$name-start');
        await Future<void>.delayed(Duration(milliseconds: delayMs));
        order.add('$name-end');
      },
    );
  }

  await Future.wait([op('a', 30), op('b', 5)]);
  _check(
    order.join(',') == 'a-start,a-end,b-start,b-end',
    '同 host+path 的写操作串行且不交叠',
    order.join(','),
  );

  var concurrent = 0;
  var maxConcurrent = 0;
  await Future.wait([
    lock.synchronize(
      shellUrl: 'http://matrix.invalid/shell.php',
      remotePath: '/var/www/other.php',
      operation: () async {
        concurrent++;
        maxConcurrent = max(maxConcurrent, concurrent);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        concurrent--;
      },
    ),
    lock.synchronize(
      shellUrl: 'http://matrix.invalid/shell.php',
      remotePath: '/var/www/shell.php',
      operation: () async {
        concurrent++;
        maxConcurrent = max(maxConcurrent, concurrent);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        concurrent--;
      },
    ),
  ]);
  _check(maxConcurrent == 2, '不同远端路径可并行', maxConcurrent);
}

void _testCipher() {
  final key = List<int>.generate(32, (i) => i);
  final cipher = CredentialCipher.withKey(key);

  final sealed = cipher.encrypt('mAtrix_911');
  _check(sealed.startsWith(CredentialCipher.prefix), '密文带 enc:v1: 前缀');
  _check(cipher.decrypt(sealed) == 'mAtrix_911', '可解密还原');
  _check(cipher.encrypt('same') != cipher.encrypt('same'), '随机 IV：同明文不同密文');
  _check(cipher.decrypt('legacy-plain') == 'legacy-plain', '历史明文直通');

  final other = CredentialCipher.withKey(List<int>.generate(32, (i) => 255 - i));
  _check(other.decrypt(sealed) == sealed, '错误密钥不返回明文');

  final tampered = '${sealed.substring(0, sealed.length - 6)}AAAA=';
  _check(cipher.decrypt(tampered) != 'mAtrix_911', '密文被篡改不返回明文');

  CredentialCipher.setInstance(null);
  _check(CredentialCipher.encryptIfReady('plain') == 'plain', '未初始化时直通');
  CredentialCipher.setInstance(cipher);
  final once = CredentialCipher.encryptIfReady('x');
  _check(CredentialCipher.encryptIfReady(once) == once, '密文二次加密幂等');
  CredentialCipher.setInstance(null);
}

Future<void> _testCredentialMigration() async {
  final cipher = CredentialCipher.withKey(List<int>.generate(32, (i) => 7 + i));
  CredentialCipher.setInstance(cipher);
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  try {
    await db.execute(
      'CREATE TABLE webshells (id INTEGER PRIMARY KEY, password TEXT, secret_key TEXT)',
    );
    await db.execute(
      'CREATE TABLE frp_profiles (id INTEGER PRIMARY KEY, token TEXT)',
    );
    await db.insert('webshells', <String, Object?>{
      'id': 1,
      'password': 'p@ss',
      'secret_key': 'key',
    });
    await db.insert('webshells', <String, Object?>{
      'id': 2,
      'password': null,
      'secret_key': 'k2',
    });
    await db.insert('frp_profiles', <String, Object?>{
      'id': 1,
      'token': 'frp-token',
    });

    final changed = await encryptLegacyCredentialsIn(db);
    _check(changed == 3, '迁移 3 条记录', changed);

    final ws = await db.query('webshells', orderBy: 'id');
    _check(
      (ws[0]['password'] as String).startsWith(CredentialCipher.prefix),
      'password 已加密',
    );
    _check(
      CredentialCipher.decryptIfReady(ws[0]['password'] as String) == 'p@ss',
      'password 可还原',
    );
    _check(ws[1]['password'] == null, 'NULL 保持 NULL');
    _check(
      CredentialCipher.decryptIfReady(ws[1]['secret_key'] as String) == 'k2',
      'secret_key 可还原',
    );
    final frp = await db.query('frp_profiles');
    _check(
      CredentialCipher.decryptIfReady(frp[0]['token'] as String) == 'frp-token',
      'token 可还原',
    );

    final again = await encryptLegacyCredentialsIn(db);
    _check(again == 0, '重复迁移幂等', again);
  } finally {
    await db.close();
    CredentialCipher.setInstance(null);
  }
}

Future<void> _testTtlCache() async {
  final cache = TtlCache<String, int>(const Duration(milliseconds: 40));
  _check(cache.get('k') == null, '未命中返回 null');
  cache.put('k', 1);
  _check(cache.get('k') == 1, '命中返回值');
  _check(await cache.fetch('k', () async => 2) == 1, 'fetch 命中不调用 loader');
  await Future<void>.delayed(const Duration(milliseconds: 60));
  _check(cache.get('k') == null, '过期后失效');
  cache.put('a', 9);
  cache.invalidate('a');
  _check(cache.get('a') == null, 'invalidate 生效');
  cache.put('x', 1);
  cache.clear();
  _check(cache.length == 0, 'clear 清空');
}

void _testRceEncoder() {
  // PHP 单引号串不做变量插值：$ 必须原样保留，只有 \ 和 ' 需要转义。
  _check(
    RceEncoder.phpSingleQuoted(r'echo $HOME') == r'echo $HOME',
    'phpSingleQuoted 保留 \$',
  );
  _check(
    RceEncoder.phpSingleQuoted("it's") == r"it\'s",
    'phpSingleQuoted 转义单引号',
    RceEncoder.phpSingleQuoted("it's"),
  );
  _check(
    RceEncoder.phpSingleQuoted(r'a\b') == r'a\\b',
    'phpSingleQuoted 转义反斜杠',
    RceEncoder.phpSingleQuoted(r'a\b'),
  );
  _check(
    RceEncoder.escapeDoubleQuoted('a"b') == r'a\"b',
    'escapeDoubleQuoted 转义双引号',
  );
  _check(
    RceEncoder.escapeDoubleQuoted(r'a\b') == r'a\\b',
    'escapeDoubleQuoted 转义反斜杠',
  );
}

void _testExpResult() {
  const vuln = ExpResult(true, 'CVE-X', 'hit');
  const miss = ExpResult(false, 'CVE-X', '');
  const fail = ExpResult.probeFailed('CVE-X', 'timeout');

  _check(vuln.vulnerable && !vuln.failed, '命中：vulnerable=true/failed=false');
  _check(!miss.vulnerable && !miss.failed, '未命中不等于探测失败');
  _check(!fail.vulnerable && fail.failed, '探测失败是独立状态');
}
