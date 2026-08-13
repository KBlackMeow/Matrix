import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/pages/priv_esc_landing.dart';
import 'package:matrix/pages/priv_esc_vectors.dart';

void main() {
  test('detectSuid matches basename against gtfoBins', () {
    final candidates =
        detectSuid('/usr/bin/find\n/usr/bin/python3\n/usr/bin/notreal\n');
    final exploitable =
        candidates.where((c) => c.gtfo != null).map((c) => c.gtfo!.id);
    expect(exploitable, containsAll(['find', 'python3']));
    expect(exploitable, isNot(contains('notreal')));
  });

  test('detectSuid marks interactive bins as a lead (no gtfo)', () {
    final candidates = detectSuid('/usr/bin/vim\n');
    expect(candidates.single.gtfo, isNull);
    expect(candidates.single.vectorId, 'suid-interactive');
  });

  test('detectSudo parses NOPASSWD ALL', () {
    final candidates = detectSudo('(ALL) NOPASSWD: ALL');
    expect(candidates.single.binPath, '/bin/sh');
    expect(candidates.single.prefix, 'sudo -n ');
    expect(candidates.single.gtfo, isNotNull);
  });

  test('detectSudo parses a specific binary', () {
    final candidates = detectSudo('(root) NOPASSWD: /usr/bin/find');
    expect(candidates.single.gtfo!.id, 'find');
    expect(candidates.single.prefix, 'sudo -n ');
  });

  test('detectWritablePasswd only accepts writable', () {
    expect(detectWritablePasswd('writable'), isNotEmpty);
    expect(detectWritablePasswd('not writable'), isEmpty);
  });

  test('buildChain base64-wraps the landing deploy for a primitive', () {
    final candidate =
        detectSuid('/usr/bin/find\n').firstWhere((c) => c.gtfo != null);
    final landing = landingById('suid_shell');
    final params = {'mimic': 'kworker'};
    final chain =
        buildChain(candidate: candidate, landing: landing, params: params);

    final expectedB64 = base64Encode(
      utf8.encode(substituteTemplate(landing.deployTemplate, params)),
    );
    expect(chain.deployCommand, contains(expectedB64));
    expect(chain.deployCommand, contains('-exec sh -p -c'));
  });

  test('buildChain python payload has balanced quotes', () {
    final candidate =
        detectSuid('/usr/bin/python3\n').firstWhere((c) => c.gtfo != null);
    final chain = buildChain(
      candidate: candidate,
      landing: landingById('suid_shell'),
      params: {'mimic': 'kworker'},
    );
    expect(chain.deployCommand.split("'").length.isOdd, isTrue);
    expect(chain.deployCommand.split('"').length.isOdd, isTrue);
  });

  test('buildChain for a fused vector uses the landing directly', () {
    final candidate = detectWritablePasswd('writable').single;
    final chain = buildChain(
      candidate: candidate,
      landing: landingById('passwd_user'),
      params: {'username': 'x', 'password': 'p', 'salt': 'AA'},
    );
    expect(chain.deployCommand, contains('/etc/passwd'));
    expect(chain.deployCommand, isNot(contains('base64')));
  });

  test('every gtfo payload is non-empty and uses {b64_root}', () {
    for (final b in gtfoBins) {
      expect(b.payloadTemplate, isNotEmpty);
      expect(b.payloadTemplate, contains('{b64_root}'));
      expect(b.proofTemplate, contains('{bin}'));
    }
  });

  test('perl/awk/tar/busybox are SUID-unsafe (sudo-only)', () {
    for (final id in ['perl', 'awk', 'tar', 'busybox']) {
      expect(gtfoBins.firstWhere((b) => b.id == id).suidSafe, isFalse, reason: id);
    }
    for (final id in ['find', 'bash', 'php', 'env', 'python3']) {
      expect(gtfoBins.firstWhere((b) => b.id == id).suidSafe, isTrue, reason: id);
    }
  });

  test('detectSuid reports SUID-unsafe binaries as a lead (no gtfo)', () {
    final candidates = detectSuid('/usr/bin/perl\n');
    expect(candidates.single.gtfo, isNull);
    expect(candidates.single.vectorId, 'suid-sudo-only');
  });

  test('detectLdPreload distinguishes writable/exists/absent', () {
    expect(detectLdPreload('writable').single.vectorId, 'ld-preload');
    expect(detectLdPreload('exists').single.vectorId, 'ld-preload');
    expect(detectLdPreload('absent'), isEmpty);
  });
}
