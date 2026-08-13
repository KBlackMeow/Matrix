import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/pages/persistence_engine.dart';
import 'package:matrix/pages/persistence_methods.dart';

void main() {
  group('parseExploitability', () {
    test('ready when no FAIL tokens', () {
      final r = parseExploitability('EXPLOIT:OK:/tmp writable');
      expect(r.level, ExploitabilityLevel.ready);
      expect(r.satisfied, ['/tmp writable']);
      expect(r.blocked, isEmpty);
    });

    test('blocked when any FAIL token', () {
      final r = parseExploitability(
        'EXPLOIT:OK:/tmp writable\nEXPLOIT:FAIL:not root',
      );
      expect(r.level, ExploitabilityLevel.blocked);
      expect(r.blocked, ['not root']);
      expect(r.isDeployable, isFalse);
    });

    test('ignores lines without EXPLOIT prefix', () {
      final r = parseExploitability('some output\nEXPLOIT:OK:a');
      expect(r.satisfied, ['a']);
      expect(r.blocked, isEmpty);
    });
  });

  group('stripExploitLines', () {
    test('removes EXPLOIT-prefixed lines only', () {
      final out = stripExploitLines(
        'EXPLOIT:OK:a\nkeep me\nEXPLOIT:FAIL:b\n',
      );
      expect(out, contains('keep me'));
      expect(out, isNot(contains('EXPLOIT:')));
    });
  });

  group('parseDeploySuccess', () {
    test('detects DEPLOY_OK marker', () {
      expect(parseDeploySuccess('done\nDEPLOY_OK'), isTrue);
      expect(parseDeploySuccess('DEPLOY_FAILED'), isFalse);
    });
  });

  group('parseVerifySuccess', () {
    test('detects VERIFY_OK marker', () {
      expect(parseVerifySuccess('VERIFY_OK:entry_exists'), isTrue);
      expect(parseVerifySuccess('VERIFY_FAILED'), isFalse);
    });

    test('detects uid=0 root proof', () {
      expect(parseVerifySuccess('uid=0(root) gid=0(root)'), isTrue);
      expect(parseVerifySuccess('euid=0(root)'), isTrue);
    });
  });

  group('parseDetection', () {
    test('returns error on [Error] prefix', () {
      final r = parseDetection('cron_job', '[Error] boom');
      expect(r.verdict, DetectionVerdict.error);
    });

    test('dispatches cron_job to parseCron', () {
      final r = parseDetection('cron_job', '(no crontab or empty)');
      expect(r.verdict, DetectionVerdict.clean);
    });

    test('unknown method id falls back to found with truncated summary', () {
      final r = parseDetection('mystery', 'hello world');
      expect(r.verdict, DetectionVerdict.found);
      expect(r.summary, 'hello world');
    });

    test('attaches exploitability from EXPLOIT: lines', () {
      final r = parseDetection(
        'cron_job',
        'EXPLOIT:FAIL:not root\n(no crontab or empty)',
      );
      expect(r.exploitability, isNotNull);
      expect(r.exploitability!.isDeployable, isFalse);
      expect(r.verdict, DetectionVerdict.clean);
    });
  });
}
