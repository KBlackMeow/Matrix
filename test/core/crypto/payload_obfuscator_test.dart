import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/core/crypto/payload_obfuscator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PayloadObfuscator JSP', () {
    test('jsp_behinder keeps custom method calls in sync with declarations', () async {
      final raw = await rootBundle.loadString(
        'assets/defaults/payloads/webshell/jsp_behinder.jsp',
      );
      final obfuscated = PayloadObfuscator.obfuscate(raw, 'jsp');
      expect(obfuscated, isNotNull);
      expect(obfuscated, isNot(equals(raw)));

      // Original declares `Class g(byte[])` and calls `.g(...)` on class U.
      expect(raw, contains('Class g(byte'));
      expect(raw, contains(').g('));

      // After obfuscation, `.g(` and `Class g(` must both be gone.
      expect(obfuscated, isNot(contains('Class g(')));
      expect(obfuscated, isNot(contains(').g(')));

      // Collect ALL renamed method declarations and call sites,
      // then verify that at least one declaration/call pair matches.
      final methodDeclRe = RegExp(r'Class ([a-f][0-9a-f]{5})\(byte');
      final callSiteRe = RegExp(r'\.([a-f][0-9a-f]{5})\(');

      final declNames = <String>{};
      for (final m in methodDeclRe.allMatches(obfuscated!)) {
        declNames.add(m.group(1)!);
      }
      final callNames = <String>{};
      for (final m in callSiteRe.allMatches(obfuscated)) {
        callNames.add(m.group(1)!);
      }

      expect(declNames, isNotEmpty, reason: 'expected at least one renamed method declaration');
      expect(callNames, isNotEmpty, reason: 'expected at least one renamed method call');

      final intersection = declNames.intersection(callNames);
      expect(intersection, isNotEmpty,
          reason: 'expected renamed method(s) to appear in both declaration and call site; '
              'declarations=$declNames, callSites=$callNames');
    });
  });
}
