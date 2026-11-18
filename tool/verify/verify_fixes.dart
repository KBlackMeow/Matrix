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

import '../../lib/core/async/serial_queue.dart';
import '../../lib/database/storage_permissions.dart';
import '../../lib/mcp/log_redaction.dart';

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

  print('== Log redaction ==');
  _testRedaction();

  print('== Storage permissions ==');

  await _testPermissions();

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

Future<void> _testPermissions() async {
  final dir = await Directory.systemTemp.createTemp('matrix_perm_test');
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
