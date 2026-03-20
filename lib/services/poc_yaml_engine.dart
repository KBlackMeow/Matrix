import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:yaml/yaml.dart';

// ── Data models ───────────────────────────────────────────────────────────────

class PocDefinition {
  final String name;
  final List<PocRule> rules;
  final String? globalExpression; // optional top-level expression (named rule/group refs)
  final Map<String, String> set; // variable declarations

  /// groups: format — named rule groups referenced by globalExpression via `name()`
  /// Key = group name, Value = ordered list of rules (AND logic within a group)
  final Map<String, List<PocRule>> groups;

  const PocDefinition({
    required this.name,
    required this.rules,
    required this.set,
    this.globalExpression,
    this.groups = const {},
  });

  /// True when POC uses groups: format instead of rules:
  bool get isGrouped => groups.isNotEmpty;
}

class PocRule {
  final String method;
  final String path;
  final Map<String, String> headers;
  final String? body;
  final bool followRedirects;
  final String expression;

  /// Regex with named capture groups extracted from response header+body.
  /// Captured groups are injected into vars for subsequent rule substitution.
  /// e.g.  search: "cookiepre = '(?P<token>[\w_]+)'"  → vars["token"] = "abc"
  final String? search;

  const PocRule({
    required this.method,
    required this.path,
    required this.headers,
    this.body,
    this.followRedirects = false,
    required this.expression,
    this.search,
  });
}

class PocRuleResponse {
  final int status;
  final List<int> body;
  final Map<String, String> headers;

  PocRuleResponse({
    required this.status,
    required this.body,
    required this.headers,
  });

  String get contentType =>
      headers.entries
          .firstWhere(
            (e) => e.key.toLowerCase() == 'content-type',
            orElse: () => const MapEntry('', ''),
          )
          .value;

  List<int> get rawHeader =>
      utf8.encode(headers.entries.map((e) => '${e.key}: ${e.value}').join('\r\n'));

  String? headerValue(String key) {
    final k = key.toLowerCase();
    for (final e in headers.entries) {
      if (e.key.toLowerCase() == k) return e.value;
    }
    return null;
  }
}

class PocRunResult {
  final String pocName;
  final String target;
  final bool vulnerable;
  final String detail;

  const PocRunResult({
    required this.pocName,
    required this.target,
    required this.vulnerable,
    this.detail = '',
  });
}

// ── Engine ────────────────────────────────────────────────────────────────────

class PocYamlEngine {
  final Duration timeout;
  final int concurrency;

  PocYamlEngine({
    this.timeout = const Duration(seconds: 10),
    this.concurrency = 10,
  });

  // ── POC loading ─────────────────────────────────────────────────────────────

  /// Parse a single POC YAML string.  Returns null on parse error.
  static PocDefinition? parsePoc(String yamlStr) {
    try {
      final doc = loadYaml(yamlStr);
      if (doc is! Map) return null;

      final name = (doc['name'] ?? '').toString();
      if (name.isEmpty) return null;

      // set: variables
      final set = <String, String>{};
      if (doc['set'] is Map) {
        for (final e in (doc['set'] as Map).entries) {
          set[e.key.toString()] = e.value.toString();
        }
      }

      final globalExpr = doc['expression']?.toString().trim();

      // ── groups: format (named groups with OR/AND global expression) ──────────
      if (doc['groups'] is Map) {
        final groups = <String, List<PocRule>>{};
        for (final ge in (doc['groups'] as Map).entries) {
          final groupName = ge.key.toString();
          final rawList = ge.value;
          if (rawList is! YamlList) continue;
          final groupRules = _parseRuleList(rawList);
          if (groupRules.isNotEmpty) groups[groupName] = groupRules;
        }
        if (groups.isEmpty) return null;
        return PocDefinition(
          name: name,
          rules: const [],
          set: set,
          globalExpression: globalExpr,
          groups: groups,
        );
      }

      // ── rules: format (sequential AND) ──────────────────────────────────────
      final rawRules = doc['rules'];
      if (rawRules is! YamlList) return null;

      final rules = _parseRuleList(rawRules);
      if (rules.isEmpty) return null;

      return PocDefinition(
        name: name,
        rules: rules,
        set: set,
        globalExpression: globalExpr,
      );
    } catch (_) {
      return null;
    }
  }

  /// Parse a YamlList of rule maps into PocRule objects.
  static List<PocRule> _parseRuleList(YamlList rawList) {
    final rules = <PocRule>[];
    for (final r in rawList) {
      if (r is! Map) continue;
      final method = (r['method'] ?? 'GET').toString().toUpperCase();
      final path = (r['path'] ?? '/').toString();
      final expr = (r['expression'] ?? 'true').toString().trim();
      final follow = r['follow_redirects'] == true;

      final headers = <String, String>{};
      if (r['headers'] is Map) {
        for (final e in (r['headers'] as Map).entries) {
          headers[e.key.toString()] = e.value.toString();
        }
      }

      final body = r['body']?.toString();
      final search = r['search']?.toString().trim();
      rules.add(PocRule(
        method: method,
        path: path,
        headers: headers,
        body: body,
        followRedirects: follow,
        expression: expr,
        search: (search != null && search.isNotEmpty) ? search : null,
      ));
    }
    return rules;
  }

  /// Load all POC YAML files from the assets/data/pocs/ bundle.
  static Future<List<PocDefinition>> loadAllPocs() async {
    final pocs = <PocDefinition>[];
    try {
      final manifest = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = json.decode(manifest);
      final pocKeys = manifestMap.keys
          .where((k) => k.startsWith('data/pocs/') && k.endsWith('.yml'))
          .toList();

      for (final key in pocKeys) {
        try {
          final content = await rootBundle.loadString(key);
          final poc = parsePoc(content);
          if (poc != null) pocs.add(poc);
        } catch (_) {}
      }
    } catch (_) {}
    return pocs;
  }

  // ── POC execution ────────────────────────────────────────────────────────────

  /// Run a single POC against baseUrl. Returns null if not vulnerable.
  Future<PocRunResult?> runPoc(PocDefinition poc, String baseUrl) async {
    final vars = _resolveVars(poc.set);

    if (poc.isGrouped) {
      return _runGrouped(poc, baseUrl, vars);
    }

    // rules: format — evaluate sequentially; all must match (AND logic)
    for (final rule in poc.rules) {
      final resp = await _executeRule(baseUrl, rule, vars);
      if (resp == null) return null;

      // search: extract named regex groups into vars for subsequent rules
      if (rule.search != null) {
        final extracted = _doSearch(rule.search!, resp);
        if (extracted == null) return null; // search required but matched nothing
        vars.addAll(extracted);
      }

      final exprStr = rule.expression.trim();
      if (exprStr == 'true' || exprStr.isEmpty) continue;
      if (!_evalExpr(exprStr, resp, vars)) return null;
    }

    return PocRunResult(pocName: poc.name, target: baseUrl, vulnerable: true);
  }

  /// groups: format — iterate groups in order; return true on the FIRST
  /// successful group (OR logic). Matches fscan's executeRules Groups branch.
  Future<PocRunResult?> _runGrouped(
    PocDefinition poc,
    String baseUrl,
    Map<String, dynamic> vars,
  ) async {
    for (final entry in poc.groups.entries) {
      if (await _evalRuleGroup(entry.value, baseUrl, vars)) {
        return PocRunResult(pocName: poc.name, target: baseUrl, vulnerable: true);
      }
    }
    return null;
  }

  /// Run all rules in a group sequentially (AND logic).
  /// Applies search: extraction between rules, same as runPoc.
  Future<bool> _evalRuleGroup(
    List<PocRule> rules,
    String baseUrl,
    Map<String, dynamic> vars,
  ) async {
    for (final rule in rules) {
      final resp = await _executeRule(baseUrl, rule, vars);
      if (resp == null) return false;

      if (rule.search != null) {
        final extracted = _doSearch(rule.search!, resp);
        if (extracted == null) return false;
        vars.addAll(extracted);
      }

      final exprStr = rule.expression.trim();
      if (exprStr == 'true' || exprStr.isEmpty) continue;
      if (!_evalExpr(exprStr, resp, vars)) return false;
    }
    return true;
  }

  /// Apply a regex with named capture groups to response header+body.
  /// Returns the captured map, or null if the regex matched nothing.
  /// Mirrors fscan's doSearch() — null means "search required but no match".
  Map<String, String>? _doSearch(String pattern, PocRuleResponse resp) {
    try {
      final re = RegExp(pattern);
      final haystack = _buildSearchText(resp);
      final m = re.firstMatch(haystack);
      if (m == null) return null;
      final result = <String, String>{};
      // Extract group names from pattern: (?P<name>…) or (?<name>…)
      for (final nm in RegExp(r'\(\?P?<(\w+)>').allMatches(pattern)) {
        final name = nm.group(1)!;
        final v = m.namedGroup(name);
        if (v != null) result[name] = v;
      }
      // If regex has no named groups, treat match as non-blocking (return empty map)
      return result;
    } catch (_) {
      return {}; // bad regex → non-blocking
    }
  }

  /// Concatenate response headers + body as text (mirrors fscan GetHeader+body).
  String _buildSearchText(PocRuleResponse resp) {
    final headerStr = resp.headers.entries
        .map((e) => '${e.key}: ${e.value}')
        .join('\n');
    return '$headerStr\r\n${utf8.decode(resp.body, allowMalformed: true)}';
  }

  /// Scan a URL against a list of POCs with bounded concurrency.
  Stream<PocRunResult> scanUrl(
    String baseUrl,
    List<PocDefinition> pocs, {
    bool Function()? isCancelled,
  }) async* {
    final sem = _Sem(concurrency);
    final results = <PocRunResult>[];

    await Future.wait(pocs.map((poc) async {
      if (isCancelled?.call() == true) return;
      await sem.acquire();
      try {
        if (isCancelled?.call() == true) return;
        final r = await runPoc(poc, baseUrl);
        if (r != null) results.add(r);
      } finally {
        sem.release();
      }
    }));

    for (final r in results) {
      yield r;
    }
  }

  // ── HTTP execution ───────────────────────────────────────────────────────────

  Future<PocRuleResponse?> _executeRule(
    String baseUrl,
    PocRule rule,
    Map<String, dynamic> vars,
  ) async {
    try {
      final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
      final pathSub = _substituteVars(rule.path, vars);
      final urlStr = pathSub.startsWith('http') ? pathSub : '$base$pathSub';
      final uri = Uri.parse(urlStr);

      final HttpClient client = HttpClient()
        ..connectionTimeout = timeout
        ..badCertificateCallback = (_, __, ___) => true;

      if (!rule.followRedirects) {
        client.maxConnectionsPerHost = 4;
      }

      final req = await client.openUrl(rule.method, uri).timeout(timeout);

      // Default headers (mirrors fscan createBaseRequest)
      req.headers.set('User-Agent', 'Mozilla/5.0 (compatible; fscan/1.0)');
      req.headers.set('Accept', '*/*');
      req.headers.set('Accept-Language', 'zh-CN,zh;q=0.9');

      // Rule headers (override defaults)
      for (final e in rule.headers.entries) {
        final key = _substituteVars(e.key, vars);
        final val = _substituteVars(e.value, vars);
        req.headers.set(key, val);
      }

      // Body
      if (rule.body != null && rule.body!.isNotEmpty) {
        final bodyBytes = utf8.encode(_substituteVars(rule.body!, vars));
        req.headers.contentLength = bodyBytes.length;
        // Default Content-Type when not explicitly set (mirrors fscan DoRequest)
        if (req.headers.value('content-type') == null) {
          req.headers.set('Content-Type', 'application/x-www-form-urlencoded');
        }
        req.add(bodyBytes);
      }

      final resp = await req.close().timeout(timeout);

      // Collect headers (join multi-values with ';' like fscan)
      final respHeaders = <String, String>{};
      resp.headers.forEach((name, values) {
        if (values.isNotEmpty) respHeaders[name] = values.join(';');
      });

      // Read body (cap at 1 MB), decompress gzip (mirrors fscan getRespBody)
      final rawBuf = <int>[];
      await for (final chunk in resp) {
        rawBuf.addAll(chunk);
        if (rawBuf.length > 1024 * 1024) break;
      }
      final bodyBuf = _decompressBody(rawBuf, respHeaders);

      client.close();

      return PocRuleResponse(
        status: resp.statusCode,
        body: bodyBuf,
        headers: respHeaders,
      );
    } catch (_) {
      return null;
    }
  }

  /// Decompress gzip body if Content-Encoding contains gzip.
  /// Mirrors fscan's getRespBody().
  static List<int> _decompressBody(List<int> raw, Map<String, String> headers) {
    final enc = headers['content-encoding'] ?? headers['Content-Encoding'] ?? '';
    if (!enc.contains('gzip')) return raw;
    try {
      return GZipCodec().decode(raw);
    } catch (_) {
      return raw; // decompression failed → return raw bytes
    }
  }

  // ── Variable resolution ──────────────────────────────────────────────────────

  Map<String, dynamic> _resolveVars(Map<String, String> set) {
    final vars = <String, dynamic>{};
    final rng = Random.secure();
    for (final e in set.entries) {
      vars[e.key] = _resolveOneVar(e.value.trim(), vars, rng);
    }
    return vars;
  }

  /// Resolve a single `set:` value expression, referencing already-resolved vars.
  static dynamic _resolveOneVar(String v, Map<String, dynamic> resolved, Random rng) {
    // randomLowercase(n) — n may be int literal or a previously resolved var name
    if (v.startsWith('randomLowercase(')) {
      final arg = v.substring(16, v.length - 1).trim();
      final n = int.tryParse(arg) ?? (resolved[arg] is int ? resolved[arg] as int : 8);
      return _randomLowercase(n, rng);
    }
    // randomUppercase(n)
    if (v.startsWith('randomUppercase(')) {
      final arg = v.substring(16, v.length - 1).trim();
      final n = int.tryParse(arg) ?? (resolved[arg] is int ? resolved[arg] as int : 8);
      return _randomUppercase(n, rng);
    }
    // randomInt(min, max)
    if (v.startsWith('randomInt(')) {
      final parts = v.substring(10, v.length - 1).split(',');
      final min = int.tryParse(parts[0].trim()) ?? 0;
      final max = int.tryParse(parts[1].trim()) ?? 1000000000;
      return min + rng.nextInt((max - min).clamp(1, 1 << 30));
    }
    // String concatenation: randomLowercase(4) + ".txt"
    if (v.contains(') + "') || v.contains(') + \'')) {
      final plus = v.indexOf(') + ');
      if (plus != -1) {
        final left = _resolveOneVar(v.substring(0, plus + 1), resolved, rng);
        final right = v.substring(plus + 4).trim().replaceAll('"', '').replaceAll("'", '');
        return '$left$right';
      }
    }
    // reverse.url / reverse.domain — OOB DNSLOG, not supported; leave as placeholder
    if (v == 'reverse.url' || v == 'reverse.domain') return '';
    return v;
  }

  static String _randomLowercase(int n, Random rng) {
    const chars = 'abcdefghijklmnopqrstuvwxyz';
    return List.generate(n, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  static String _randomUppercase(int n, Random rng) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    return List.generate(n, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  static String _randomString(int n, Random rng) {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List.generate(n, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  String _substituteVars(String s, Map<String, dynamic> vars) {
    return s.replaceAllMapped(RegExp(r'\{\{(\w+)\}\}'), (m) {
      final v = vars[m.group(1)];
      return v?.toString() ?? '';
    });
  }

  // ── Expression evaluation ────────────────────────────────────────────────────

  bool _evalExpr(String expr, PocRuleResponse resp, Map<String, dynamic> vars) {
    try {
      return _ExprEval(expr, resp, vars).evalBool();
    } catch (_) {
      return false;
    }
  }
}

// ── Expression evaluator ──────────────────────────────────────────────────────

/// Recursive-descent evaluator for the fscan/xray POC expression language.
///
/// Supported:
///   - response.status, response.body, response.content_type,
///     response.headers["Key"], response.raw_header
///   - b"…", r"…", "…", integer literals
///   - bytes(v), string(v), md5(v), substr(s, start, len)
///   - .bcontains(bytes), .contains(string), .icontains(string)
///   - .bmatches(bytes) — regex match against byte string
///   - Arithmetic: +, -, *, /, % (ints and string concat)
///   - Comparison: ==, !=, <, <=, >, >=
///   - Logical: &&, ||, ! (unary not)
///   - Grouping: (…)
///   - Variable references from set: block
class _ExprEval {
  final String src;
  final PocRuleResponse resp;
  final Map<String, dynamic> vars;
  int _pos = 0;

  _ExprEval(this.src, this.resp, this.vars);

  bool evalBool() => _asBool(_parseOr());

  // ── grammar: or ──────────────────────────────────────────────────────────────

  dynamic _parseOr() {
    var left = _parseAnd();
    _ws();
    while (_at('||')) {
      _pos += 2;
      final right = _parseAnd();
      left = _asBool(left) || _asBool(right);
      _ws();
    }
    return left;
  }

  dynamic _parseAnd() {
    var left = _parseNot();
    _ws();
    while (_at('&&')) {
      _pos += 2;
      final right = _parseNot();
      left = _asBool(left) && _asBool(right);
      _ws();
    }
    return left;
  }

  dynamic _parseNot() {
    _ws();
    if (_pos < src.length && src[_pos] == '!') {
      _pos++;
      return !_asBool(_parseNot());
    }
    return _parseCmp();
  }

  dynamic _parseCmp() {
    final left = _parseAdd();
    _ws();
    if (_at('==')) { _pos += 2; return _eq(left, _parseAdd()); }
    if (_at('!=')) { _pos += 2; return !_eq(left, _parseAdd()); }
    if (_at('>=')) { _pos += 2; return _cmp(left, _parseAdd()) >= 0; }
    if (_at('<=')) { _pos += 2; return _cmp(left, _parseAdd()) <= 0; }
    if (_at('>'))  { _pos += 1; return _cmp(left, _parseAdd()) > 0; }
    if (_at('<'))  { _pos += 1; return _cmp(left, _parseAdd()) < 0; }
    return left;
  }

  // ── grammar: arithmetic ──────────────────────────────────────────────────────

  dynamic _parseAdd() {
    var left = _parseMul();
    _ws();
    while (_pos < src.length && (src[_pos] == '+' || src[_pos] == '-')) {
      final op = src[_pos++];
      final right = _parseMul();
      if (op == '+') {
        if (left is int && right is int) {
          left = left + right;
        } else {
          left = '${_asStr(left)}${_asStr(right)}';
        }
      } else {
        left = (left is int ? left : 0) - (right is int ? right : 0);
      }
      _ws();
    }
    return left;
  }

  dynamic _parseMul() {
    var left = _parsePostfix();
    _ws();
    while (_pos < src.length && (src[_pos] == '*' || src[_pos] == '/' || src[_pos] == '%')) {
      final op = src[_pos++];
      final right = _parsePostfix();
      final l = left is int ? left : 0;
      final r = right is int ? right : 1;
      if (op == '*') { left = l * r; }
      else if (op == '/') { left = r != 0 ? l ~/ r : 0; }
      else { left = r != 0 ? l % r : 0; }
      _ws();
    }
    return left;
  }

  // ── grammar: postfix (method calls & property access) ───────────────────────

  dynamic _parsePostfix() {
    var val = _parsePrimary();
    _ws();
    while (_pos < src.length && (src[_pos] == '.' || src[_pos] == '[')) {
      if (src[_pos] == '[') {
        // subscript: obj["key"]
        _pos++; // skip [
        final key = _parsePrimary();
        _ws();
        if (_pos < src.length && src[_pos] == ']') _pos++;
        val = _subscript(val, key);
      } else {
        _pos++; // skip .
        final name = _ident();
        _ws();
        if (_pos < src.length && src[_pos] == '(') {
          _pos++; // skip (
          final args = _argList();
          _ws();
          if (_pos < src.length && src[_pos] == ')') _pos++;
          val = _method(val, name, args);
        } else {
          val = _prop(val, name);
        }
      }
      _ws();
    }
    return val;
  }

  // ── grammar: primary ─────────────────────────────────────────────────────────

  dynamic _parsePrimary() {
    _ws();
    if (_pos >= src.length) return null;

    final ch = src[_pos];

    // Byte literal  b"…"  b'…'
    if (ch == 'b' && _pos + 1 < src.length && (src[_pos + 1] == '"' || src[_pos + 1] == "'")) {
      _pos++;
      return utf8.encode(_strLit());
    }
    // Raw string  r"…"  r'…'  (regex pattern — keep as string)
    if (ch == 'r' && _pos + 1 < src.length && (src[_pos + 1] == '"' || src[_pos + 1] == "'")) {
      _pos++;
      return _strLit();
    }
    // String literal
    if (ch == '"' || ch == "'") return _strLit();

    // Number
    if (ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57) return _numLit();

    // Grouped expression
    if (ch == '(') {
      _pos++;
      final v = _parseOr();
      _ws();
      if (_pos < src.length && src[_pos] == ')') _pos++;
      return v;
    }

    // Identifier (variable, function call, or 'response')
    final name = _ident();
    if (name.isEmpty) return null;
    _ws();

    if (_pos < src.length && src[_pos] == '(') {
      _pos++;
      final args = _argList();
      _ws();
      if (_pos < src.length && src[_pos] == ')') _pos++;
      return _func(name, args);
    }

    return _resolveIdent(name);
  }

  // ── arg list (comma separated, stops at ')' respecting nesting) ──────────────

  List<dynamic> _argList() {
    final args = <dynamic>[];
    _ws();
    while (_pos < src.length && src[_pos] != ')') {
      args.add(_parseOr()); // full expression including logical ops
      _ws();
      if (_pos < src.length && src[_pos] == ',') {
        _pos++;
        _ws();
      }
    }
    return args;
  }

  // ── lexer helpers ────────────────────────────────────────────────────────────

  void _ws() {
    while (_pos < src.length && (src[_pos] == ' ' || src[_pos] == '\t' || src[_pos] == '\n' || src[_pos] == '\r')) {
      _pos++;
    }
  }

  bool _at(String s) {
    if (_pos + s.length > src.length) return false;
    return src.substring(_pos, _pos + s.length) == s;
  }

  String _ident() {
    final start = _pos;
    while (_pos < src.length) {
      final c = src[_pos].codeUnitAt(0);
      if ((c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 95) {
        _pos++;
      } else {
        break;
      }
    }
    return src.substring(start, _pos);
  }

  String _strLit() {
    if (_pos >= src.length) return '';
    final quote = src[_pos++];
    final buf = StringBuffer();
    while (_pos < src.length && src[_pos] != quote) {
      if (src[_pos] == '\\') {
        _pos++;
        if (_pos < src.length) {
          switch (src[_pos]) {
            case 'n': buf.write('\n'); break;
            case 'r': buf.write('\r'); break;
            case 't': buf.write('\t'); break;
            case '\\': buf.write('\\'); break;
            default: buf.write(src[_pos]);
          }
          _pos++;
        }
      } else {
        buf.write(src[_pos++]);
      }
    }
    if (_pos < src.length) _pos++; // closing quote
    return buf.toString();
  }

  int _numLit() {
    final start = _pos;
    while (_pos < src.length && src[_pos].codeUnitAt(0) >= 48 && src[_pos].codeUnitAt(0) <= 57) {
      _pos++;
    }
    return int.tryParse(src.substring(start, _pos)) ?? 0;
  }

  // ── value helpers ────────────────────────────────────────────────────────────

  bool _asBool(dynamic v) {
    if (v is bool) return v;
    if (v is int) return v != 0;
    if (v is String) return v.isNotEmpty && v != 'false';
    if (v is List) return v.isNotEmpty;
    return false;
  }

  String _asStr(dynamic v) {
    if (v is String) return v;
    if (v is List<int>) return utf8.decode(v, allowMalformed: true);
    return v?.toString() ?? '';
  }

  bool _eq(dynamic a, dynamic b) {
    if (a is int && b is int) return a == b;
    if (a is bool && b is bool) return a == b;
    return _asStr(a) == _asStr(b);
  }

  int _cmp(dynamic a, dynamic b) {
    if (a is int && b is int) return a.compareTo(b);
    return _asStr(a).compareTo(_asStr(b));
  }

  // ── identifier resolution ────────────────────────────────────────────────────

  dynamic _resolveIdent(String name) {
    if (name == 'response') return resp;
    if (name == 'true') return true;
    if (name == 'false') return false;
    final v = vars[name];
    return v; // may be int or String
  }

  // ── property access ──────────────────────────────────────────────────────────

  dynamic _prop(dynamic obj, String name) {
    if (obj is PocRuleResponse) {
      switch (name) {
        case 'status': return obj.status;
        case 'body': return obj.body;
        case 'content_type': return obj.contentType;
        case 'raw_header': return obj.rawHeader;
        case 'headers': return obj; // subscript handled via _subscript
      }
    }
    return null;
  }

  dynamic _subscript(dynamic obj, dynamic key) {
    if (obj is PocRuleResponse) {
      return obj.headerValue(_asStr(key)) ?? '';
    }
    if (obj is Map) return obj[key];
    return null;
  }

  // ── method calls ─────────────────────────────────────────────────────────────

  dynamic _method(dynamic obj, String name, List<dynamic> args) {
    switch (name) {
      // bytes methods
      case 'bcontains':
        final needle = args.isNotEmpty ? args[0] : <int>[];
        return _bcontains(_toBytes(obj), _toBytes(needle));

      case 'bmatches':
        // "pattern".bmatches(haystack) — regex match on bytes-as-string
        final pattern = _asStr(obj);
        final haystack = args.isNotEmpty ? _toBytes(args[0]) : <int>[];
        try {
          final re = RegExp(pattern);
          return re.hasMatch(utf8.decode(haystack, allowMalformed: true));
        } catch (_) {
          return false;
        }

      // string methods
      case 'contains':
        final s = _asStr(obj);
        final sub = args.isNotEmpty ? _asStr(args[0]) : '';
        return s.contains(sub);

      case 'icontains':
        final s = _asStr(obj).toLowerCase();
        final sub = args.isNotEmpty ? _asStr(args[0]).toLowerCase() : '';
        return s.contains(sub);

      // bytes.startsWith(bytes) — e.g. response.body.startsWith(b"\x50\x4B")
      case 'startsWith':
      case 'istartsWith':
        final haystack = _toBytes(obj);
        final prefix = args.isNotEmpty ? _toBytes(args[0]) : <int>[];
        if (prefix.isEmpty) return true;
        if (prefix.length > haystack.length) return false;
        for (var i = 0; i < prefix.length; i++) {
          if (haystack[i] != prefix[i]) return false;
        }
        return true;

      // "hexString".hexdecode() → bytes  (instance method form)
      case 'hexdecode':
        return _parseHex(_asStr(obj));

      default:
        return null;
    }
  }

  bool _bcontains(List<int> haystack, List<int> needle) {
    if (needle.isEmpty) return true;
    if (needle.length > haystack.length) return false;
    outer:
    for (var i = 0; i <= haystack.length - needle.length; i++) {
      for (var j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) continue outer;
      }
      return true;
    }
    return false;
  }

  List<int> _toBytes(dynamic v) {
    if (v is List<int>) return v;
    if (v is List) return v.cast<int>();
    if (v is String) return utf8.encode(v);
    return utf8.encode(v?.toString() ?? '');
  }

  List<int> _parseHex(String hex) {
    try {
      final h = hex.replaceAll(' ', '');
      final out = <int>[];
      for (var i = 0; i + 1 < h.length; i += 2) {
        out.add(int.parse(h.substring(i, i + 2), radix: 16));
      }
      return out;
    } catch (_) {
      return <int>[];
    }
  }

  // ── built-in functions ───────────────────────────────────────────────────────

  dynamic _func(String name, List<dynamic> args) {
    switch (name) {
      case 'bytes':
        final v = args.isNotEmpty ? args[0] : '';
        return _toBytes(v);

      case 'string':
        final v = args.isNotEmpty ? args[0] : '';
        if (v is int) return v.toString();
        return _asStr(v);

      case 'md5':
        final v = args.isNotEmpty ? _asStr(args[0]) : '';
        return md5.convert(utf8.encode(v)).toString();

      case 'substr':
        final s = args.isNotEmpty ? _asStr(args[0]) : '';
        final start = args.length > 1 ? (args[1] is int ? args[1] as int : 0) : 0;
        final len = args.length > 2 ? (args[2] is int ? args[2] as int : s.length) : s.length;
        if (start >= s.length) return '';
        return s.substring(start, (start + len).clamp(0, s.length));

      case 'randomInt':
        final min = args.isNotEmpty && args[0] is int ? args[0] as int : 0;
        final max = args.length > 1 && args[1] is int ? args[1] as int : 1000000000;
        return min + Random.secure().nextInt((max - min).clamp(1, 1 << 30));

      case 'randomLowercase':
        final n = args.isNotEmpty && args[0] is int ? args[0] as int : 8;
        return PocYamlEngine._randomLowercase(n, Random.secure());

      case 'randomUppercase':
        final n = args.isNotEmpty && args[0] is int ? args[0] as int : 8;
        return PocYamlEngine._randomUppercase(n, Random.secure());

      case 'randomString':
        final n = args.isNotEmpty && args[0] is int ? args[0] as int : 8;
        return PocYamlEngine._randomString(n, Random.secure());

      case 'TDdate':
        // Tongda OA date format: YYMM — e.g. "2506" for June 2025
        final now = DateTime.now();
        return '${now.year.toString().substring(2)}${now.month.toString().padLeft(2, '0')}';

      case 'base64':
        final v = args.isNotEmpty ? args[0] : '';
        return base64.encode(_toBytes(v));

      case 'base64Decode':
        final v = args.isNotEmpty ? _asStr(args[0]) : '';
        try { return utf8.decode(base64.decode(v)); } catch (_) { return v; }

      case 'urlencode':
        final v = args.isNotEmpty ? _asStr(args[0]) : '';
        return Uri.encodeQueryComponent(v);

      case 'urldecode':
        final v = args.isNotEmpty ? _asStr(args[0]) : '';
        try { return Uri.decodeQueryComponent(v); } catch (_) { return v; }

      case 'hexdecode':
        // Free-function form: hexdecode("377ABCAF...")
        final hexStr = args.isNotEmpty ? _asStr(args[0]) : '';
        return _parseHex(hexStr);

      default:
        // Unknown function name — look up in vars (resolves group booleans like h5s1())
        return vars[name];
    }
  }
}

// ── Simple semaphore ──────────────────────────────────────────────────────────

class _Sem {
  int _count;
  final _waiters = <void Function()>[];

  _Sem(this._count);

  Future<void> acquire() async {
    if (_count > 0) { _count--; return; }
    final c = Completer<void>();
    _waiters.add(c.complete);
    await c.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0)();
    } else {
      _count++;
    }
  }
}
