/// 在常见部署目录中探测 Webshell 脚本文件；未命中时由上层回落到 [getCurrentDir]。
class ShellScriptDirProbe {
  ShellScriptDirProbe._();

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

  /// PHP：先 `SCRIPT_FILENAME` / `__FILE__`，再在常见 Web 根目录中查找 URL 对应脚本。
  static String phpResolveScriptDirCode(String? basename) {
    final buf = StringBuffer(
      r'$f=isset($_SERVER["SCRIPT_FILENAME"])?$_SERVER["SCRIPT_FILENAME"]:"";'
      r'$d=($f!=="")?@realpath(dirname($f)):false;'
      r'if($d===false||$d===""){$f2=explode("(",__FILE__)[0];$d=@realpath(dirname($f2));}'
      r'if($d!==false&&$d!==""){echo $d;exit;}',
    );
    if (basename == null || basename.isEmpty) {
      buf.write('echo "";');
      return buf.toString();
    }
    final n = basename.replaceAll("'", r"\'");
    buf.write("\$n='$n';");
    buf.write(r'$c=array();');
    buf.write(
      r'if(!empty($_SERVER["DOCUMENT_ROOT"]))$c[]=$_SERVER["DOCUMENT_ROOT"];',
    );
    for (final d in _unixPhpCandidateDirs) {
      final q = d.replaceAll(r"'", r"\'");
      buf.write("\$c[]='$q';");
    }
    buf.write(r'$wd=@getcwd();if($wd)$c[]=$wd;');
    buf.write(
      r'foreach($c as $_mx_d){'
      r'if(!is_string($_mx_d)||$_mx_d==="")continue;'
      r'$_mx_p=$_mx_d.DIRECTORY_SEPARATOR.$n;'
      r'if(@is_file($_mx_p)){'
      r'$_mx_r=@realpath($_mx_d);'
      r'if($_mx_r!==false&&$_mx_r!==""){echo $_mx_r;exit;}'
      r'}}'
      r'echo "";',
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
