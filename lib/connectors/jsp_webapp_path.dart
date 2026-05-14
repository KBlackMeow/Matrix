import 'shell_connector.dart';

/// JSP / Tomcat 下「脚本所在 webapp 目录」的推导（不依赖 Tomcat 安装路径名）。
class JspWebappPath {
  JspWebappPath._();

  /// 当 cwd 在安装目录、或仅有 `CATALINA_BASE` 与 `CATALINA_HOME` 分离时，尽量落到 `webapps/...`。
  static const String kBashTomcatWebappNearPwd =
      r'if [ -n "${CATALINA_BASE-}" ] && [ -d "$CATALINA_BASE/webapps/ROOT" ]; then printf %s "$CATALINA_BASE/webapps/ROOT"; '
      r'elif [ -n "${CATALINA_BASE-}" ] && [ -d "$CATALINA_BASE/webapps" ]; then shopt -s nullglob 2>/dev/null; '
      r'for x in "$CATALINA_BASE"/webapps/*/; do [ -d "$x" ] || continue; printf %s "${x%/}"; break; done; '
      r'elif [ -n "${CATALINA_HOME-}" ] && [ -d "$CATALINA_HOME/webapps/ROOT" ]; then printf %s "$CATALINA_HOME/webapps/ROOT"; '
      r'elif [ -n "${CATALINA_HOME-}" ] && [ -d "$CATALINA_HOME/webapps" ]; then shopt -s nullglob 2>/dev/null; '
      r'for x in "$CATALINA_HOME"/webapps/*/; do [ -d "$x" ] || continue; printf %s "${x%/}"; break; done; '
      r'else _p="$(pwd)"; shopt -s nullglob 2>/dev/null; '
      r'if [ -d "$_p/webapps/ROOT" ]; then printf %s "$_p/webapps/ROOT"; '
      r'elif [ -d "$_p/webapps" ]; then for x in "$_p"/webapps/*/; do '
      r'[ -d "$x" ] || continue; printf %s "${x%/}"; break; done; fi; fi';

  static String normalizeUnixFsDir(String p) {
    var t = p.trim();
    while (t.length > 1 && t.endsWith('/')) {
      t = t.substring(0, t.length - 1);
    }
    return t;
  }

  /// 仅允许 URL 路径最后一段作为 `find -name` 参数，避免向 shell 注入。
  static String? safeScriptBasenameFromUrl(String url) {
    try {
      final u = Uri.parse(url);
      final parts = u.pathSegments.where((s) => s.isNotEmpty).toList();
      if (parts.isEmpty) return null;
      final seg = parts.last;
      if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(seg)) return null;
      return seg;
    } catch (_) {
      return null;
    }
  }

  /// 在常见 Tomcat 根下 `webapps` 内按脚本文件名查找，输出 `.../webapps/<app>`（非 JSP 子目录）。
  static String bashFindTomcatWebappByScriptFilename(String basename) {
    final q = basename.replaceAll(r"'", r"'\''");
    return "_mx_n='$q';"
        r'for _mx_r in "${CATALINA_BASE-}" "${CATALINA_HOME-}" "$(pwd)"; do '
        r'[ -z "$_mx_r" ]&&continue;[ -d "$_mx_r/webapps" ]||continue;'
        r'_mx_f=$(find "$_mx_r/webapps" -maxdepth 12 -name "$_mx_n" -type f 2>/dev/null|head -n1);'
        r'[ -z "$_mx_f" ]&&continue;'
        r'case "$_mx_f" in */webapps/*)'
        r' _mx_tmp="${_mx_f#*/webapps/}";'
        r' _mx_app="${_mx_tmp%%/*}";'
        r' _mx_pre="${_mx_f%/webapps/*}";'
        r' printf %s "$_mx_pre/webapps/$_mx_app";'
        r' exit 0;;'
        r'esac;'
        r'done';
  }

  static bool _usablePath(String v) {
    final t = v.trim();
    return t.isNotEmpty &&
        t != 'N/A' &&
        t != 'null' &&
        !t.startsWith('[') &&
        (t.startsWith('/') || t.startsWith(r'\\'));
  }

  /// 从 Matrix JSP agent `sysinfo` 的键值对中解析文档根 / webapp 物理路径。
  static String? docRootFromSysinfo(Map<String, String> info) {
    const preferredKeys = [
      '文档根目录',
      'Document root',
      'docRoot',
      'DocRoot',
      'WEB_ROOT',
      'WebRoot',
      '网站根目录',
      'Web根目录',
    ];
    for (final k in preferredKeys) {
      final v = info[k];
      if (v != null && _usablePath(v)) {
        return normalizeUnixFsDir(v);
      }
    }
    String? best;
    for (final e in info.entries) {
      final v = e.value;
      if (!_usablePath(v)) continue;
      final t = v.trim();
      if (!t.contains('/webapps/') && !t.contains(r'\webapps\')) continue;
      if (best == null || t.length > best.length) best = t;
    }
    return best != null ? normalizeUnixFsDir(best) : null;
  }

  /// 冰蝎 / ClassLoader agent：优先 Java sysinfo 文档根，再按 URL 脚本名在 `webapps` 下定位，其次目录启发式，最后 `SCRIPT_FILENAME`。
  static Future<String?> resolveJspAgentShellScriptDir({
    required bool supportsShellExec,
    required String shellUrl,
    required Future<Map<String, String>> Function() loadSysinfo,
    required Future<String> Function(String cmd, {String workingDir})
        exec,
  }) async {
    if (!supportsShellExec) return null;
    final doc = docRootFromSysinfo(await loadSysinfo());
    if (doc != null && doc.isNotEmpty) return doc;

    final base = safeScriptBasenameFromUrl(shellUrl);
    if (base != null) {
      final byName =
          (await exec(bashFindTomcatWebappByScriptFilename(base))).trim();
      if (byName.isNotEmpty && !byName.startsWith('[')) {
        return normalizeUnixFsDir(byName);
      }
    }

    final near = (await exec(kBashTomcatWebappNearPwd)).trim();
    if (near.isNotEmpty && !near.startsWith('[')) {
      return normalizeUnixFsDir(near);
    }

    final script =
        (await exec(ShellConnector.kUnixShellScriptDirProbe)).trim();
    if (script.isNotEmpty && !script.startsWith('[')) {
      return normalizeUnixFsDir(script);
    }
    return null;
  }

  /// `jsp_runtime`：无 Java sysinfo 时，按 URL 脚本名查找 webapp，再目录启发式，再 `SCRIPT_FILENAME`。
  static Future<String?> resolveJspRuntimeShellScriptDir({
    required String shellUrl,
    required Future<String> Function(String cmd) exec,
  }) async {
    final base = safeScriptBasenameFromUrl(shellUrl);
    if (base != null) {
      final byName =
          (await exec(bashFindTomcatWebappByScriptFilename(base))).trim();
      if (byName.isNotEmpty && !byName.startsWith('[')) {
        return normalizeUnixFsDir(byName);
      }
    }
    final near = (await exec(kBashTomcatWebappNearPwd)).trim();
    if (near.isNotEmpty && !near.startsWith('[')) {
      return normalizeUnixFsDir(near);
    }
    final script =
        (await exec(ShellConnector.kUnixShellScriptDirProbe)).trim();
    if (script.isNotEmpty && !script.startsWith('[')) {
      return normalizeUnixFsDir(script);
    }
    return null;
  }
}
