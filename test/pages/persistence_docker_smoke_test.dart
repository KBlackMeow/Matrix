// Docker smoke test: validates the Linux persistence command templates end-to-end
// against a target container (default `upload_train`, override with the
// PERSIST_SMOKE_CONTAINER env var). Self-skips when docker or the container is
// absent, so it never breaks a normal `flutter test` run.
//
//   PERSIST_SMOKE_CONTAINER=upload_train flutter test test/pages/persistence_docker_smoke_test.dart
//
// Invariant: when a method's check reports its prerequisites are met
// (an `EXPLOIT:OK:` line and no `EXPLOIT:FAIL:` line), the deploy must emit
// `DEPLOY_OK` and the verify must emit a recognized success marker.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/pages/persistence_engine.dart';
import 'package:matrix/pages/persistence_methods.dart';

String get _container => Platform.environment['PERSIST_SMOKE_CONTAINER'] ?? 'upload_train';

Future<String> exec(String cmd) async {
  final r = await Process.run('docker', ['exec', _container, 'sh', '-c', cmd]);
  return '${r.stdout}${r.stderr}'.trim();
}

Future<bool> _containerUp() async {
  try {
    final r = await Process.run('docker', ['exec', _container, 'true']);
    return r.exitCode == 0;
  } on ProcessException {
    return false;
  }
}

void main() {
  test('docker smoke: Linux persistence templates', () async {
    if (!await _containerUp()) {
      markTestSkipped('docker container "$_container" not available');
      return;
    }

    // Safe overrides: avoid mutating real system accounts during the run.
    const overrides = <String, Map<String, String>>{
      'root_user': {'username': 'mxtest', 'password': 'TestP@ss1', 'salt': 'AA'},
    };

    String sub(PersistMethod m, String t) {
      var s = t;
      for (final p in m.params) {
        s = s.replaceAll('{${p.id}}', overrides[m.id]?[p.id] ?? p.defaultValue);
      }
      return s;
    }

    final failures = <String>[];
    for (final m in allPersistMethods.where((m) => !m.isWindows)) {
      final ck = await exec(m.checkCommand);
      final prereqsMet = ck.contains('EXPLOIT:OK:') && !ck.contains('EXPLOIT:FAIL:');

      final dep = sub(m, m.deployTemplate);
      final dr = await exec(dep);
      final deployOk = parseDeploySuccess(dr);

      var verifyOk = false;
      if (deployOk) {
        verifyOk = parseVerifySuccess(await exec(sub(m, m.verifyTemplate)));
      }

      // Clean up regardless of outcome.
      if (m.rollbackTemplate != null) {
        await exec(sub(m, m.rollbackTemplate!));
      }

      if (prereqsMet && (!deployOk || !verifyOk)) {
        failures.add('${m.id}: prereqs met but deploy=$deployOk verify=$verifyOk\n'
            '  deploy: $dr');
      }
    }

    expect(failures, isEmpty,
        reason: 'methods whose prerequisites were met failed to deploy/verify:\n'
            '${failures.join('\n')}');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
