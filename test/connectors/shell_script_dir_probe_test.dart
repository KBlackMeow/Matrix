import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/connectors/shell_script_dir_probe.dart';

void main() {
  group('ShellScriptDirProbe.safeBasenameFromUrl', () {
    test('strips jsessionid suffix', () {
      expect(
        ShellScriptDirProbe.safeBasenameFromUrl(
          'http://10.0.0.1/app/shell.jsp;jsessionid=ABC123',
        ),
        'shell.jsp',
      );
    });

    test('rejects unsafe characters', () {
      expect(
        ShellScriptDirProbe.safeBasenameFromUrl('http://x/中文.jsp'),
        isNull,
      );
    });
  });

  group('ShellScriptDirProbe.phpResolveScriptDirCode', () {
    test('includes candidate dirs and basename check', () {
      final code = ShellScriptDirProbe.phpResolveScriptDirCode('m.php');
      expect(code, contains('SCRIPT_FILENAME'));
      expect(code, contains("'m.php'"));
      expect(code, contains('/var/www/html'));
      expect(code, contains('is_file'));
    });
  });

  group('ShellScriptDirProbe.bashFindScriptInCandidateDirs', () {
    test('includes tomcat roots and case-insensitive find', () {
      final sh = ShellScriptDirProbe.bashFindScriptInCandidateDirs('bing.jsp');
      expect(sh, contains('CATALINA_BASE'));
      expect(sh, contains('/usr/local/tomcat/webapps/ROOT'));
      expect(sh, contains('-iname'));
    });
  });
}
