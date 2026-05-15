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

      // After obfuscation, `.g(` must not remain while `Class g(` is gone.
      expect(obfuscated, isNot(contains('Class g(')));
      expect(obfuscated, isNot(contains(').g(')));
      // Renamed method should still appear on both declaration and call site.
      final methodDecl = RegExp(r'Class ([a-f][0-9a-f]{5})\(byte');
      final callSite = RegExp(r'\.([a-f][0-9a-f]{5})\(');
      final declMatch = methodDecl.firstMatch(obfuscated!);
      final callMatch = callSite.firstMatch(obfuscated);
      expect(declMatch, isNotNull, reason: 'expected renamed method declaration');
      expect(callMatch, isNotNull, reason: 'expected renamed method call');
      expect(declMatch!.group(1), equals(callMatch!.group(1)));
    });
  });
}
