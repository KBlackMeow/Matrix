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

  group('ShellScriptDirProbe.safeScriptRelDirFromUrl', () {
    test('extracts parent path segments', () {
      expect(
        ShellScriptDirProbe.safeScriptRelDirFromUrl(
          'http://localhost:8081/001/upload/php_behinder.php',
        ),
        '001/upload',
      );
    });

    test('returns null for script at web root', () {
      expect(
        ShellScriptDirProbe.safeScriptRelDirFromUrl(
          'http://localhost/shell.php',
        ),
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
      expect(code, contains('_mx_ok_dir'));
      expect(code, contains(r"$GLOBALS['_mx_n']"));
    });

    test('_mx_ok_dir reads basename via \$GLOBALS, not global \$n', () {
      final code = ShellScriptDirProbe.phpResolveScriptDirCode('shell.php');
      // probe 在冰蝎 class C::__invoke 的 eval 内运行，$n 是方法局部变量。
      // `global $n` 在函数内访问的是 PHP 全局作用域（拿不到局部 $n），永远 null。
      // 必须用 $GLOBALS 超全局变量才能跨越作用域边界传递 basename。
      expect(code, contains(r"$GLOBALS['_mx_n']"));
      expect(code, contains(r'$GLOBALS["_mx_n"]'));
    });

    test('skips relative SCRIPT_FILENAME to avoid CWD expansion', () {
      final code = ShellScriptDirProbe.phpResolveScriptDirCode('shell.php');
      // Must guard that SCRIPT_FILENAME starts with / (or Windows drive letter)
      expect(code, contains(r'$f[0]==="/"'));
    });

    test('includes DOCUMENT_ROOT + SCRIPT_NAME and URL subpath', () {
      final code = ShellScriptDirProbe.phpResolveScriptDirCode(
        'php_behinder.php',
        shellUrl: 'http://localhost:8081/001/upload/php_behinder.php',
      );
      expect(code, contains('SCRIPT_FILENAME'));
      expect(code, contains('_mx_echo_script_dir'));
      expect(code, contains('SCRIPT_NAME'));
      expect(code, contains('/001/upload'));
    });

    test('trace mode emits marker and MX_SD trace machinery', () {
      final code = ShellScriptDirProbe.phpResolveScriptDirCode(
        'x.php',
        shellUrl: 'http://h/a/x.php',
        trace: true,
      );
      expect(code, contains('[MX_SD]'));
      expect(code, contains(ShellScriptDirProbe.kPhpScriptDirMarker));
      expect(code, contains('_mx_sd_finish'));
    });
  });

  group('ShellScriptDirProbe.parsePhpScriptDirResponse', () {
    test('splits trace and path', () {
      final raw = '''
[MX_SD] step=a
[MX_SD] step=b
${ShellScriptDirProbe.kPhpScriptDirMarker}
/tmp/upload''';
      final p = ShellScriptDirProbe.parsePhpScriptDirResponse(raw);
      expect(p.path, '/tmp/upload');
      expect(p.remoteTrace, contains('[MX_SD] step=a'));
    });
  });

  group('ShellScriptDirProbe.diagnosePhpScriptDirProbeResponse', () {
    test('marks unusable paths', () {
      final d = ShellScriptDirProbe.diagnosePhpScriptDirProbeResponse(
        rawResponse: '[HTTP 500]',
        webshellUrl: 'http://localhost/s.php',
        connectorLabel: 'Test',
        traceEnabled: false,
      );
      expect(d.path, isNull);
      expect(d.diagnostic, contains('usable=false'));
    });

    test('hints empty HTTP 200 body', () {
      final d = ShellScriptDirProbe.diagnosePhpScriptDirProbeResponse(
        rawResponse: '',
        webshellUrl: 'http://localhost/a.php',
        connectorLabel: 'Test',
        traceEnabled: true,
        httpStatus: 200,
        responseBodyBytes: 0,
      );
      expect(d.diagnostic, contains('hint='));
      expect(d.diagnostic, contains('httpStatus=200'));
      expect(d.diagnostic, contains('responseBodyBytes=0'));
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
