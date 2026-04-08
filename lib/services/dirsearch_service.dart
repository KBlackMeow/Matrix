import 'dart:async' show unawaited;
import 'dart:convert' show utf8;
import 'dart:math' show Random;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

// ─────────────────────────────────────────────────────────────────────────────
// LCS helper
// ─────────────────────────────────────────────────────────────────────────────

/// Find the Longest Common Subsequence at word level.
/// Mimics Python difflib.Differ's "stable" (unchanged) tokens.
/// Capped at [_kLcsMaxWords] words per sequence for performance.
const _kLcsMaxWords = 300;

List<String> _lcsWords(List<String> a, List<String> b) {
  final w1 = a.length > _kLcsMaxWords ? a.sublist(0, _kLcsMaxWords) : a;
  final w2 = b.length > _kLcsMaxWords ? b.sublist(0, _kLcsMaxWords) : b;
  final m = w1.length;
  final n = w2.length;
  if (m == 0 || n == 0) return [];

  // Build DP table
  final dp = List.generate(m + 1, (_) => List.filled(n + 1, 0));
  for (var i = 1; i <= m; i++) {
    for (var j = 1; j <= n; j++) {
      if (w1[i - 1] == w2[j - 1]) {
        dp[i][j] = dp[i - 1][j - 1] + 1;
      } else {
        dp[i][j] = dp[i - 1][j] > dp[i][j - 1] ? dp[i - 1][j] : dp[i][j - 1];
      }
    }
  }

  // Backtrack
  final result = <String>[];
  var i = m, j = n;
  while (i > 0 && j > 0) {
    if (w1[i - 1] == w2[j - 1]) {
      result.add(w1[i - 1]);
      i--;
      j--;
    } else if (dp[i - 1][j] > dp[i][j - 1]) {
      i--;
    } else {
      j--;
    }
  }
  return result.reversed.toList();
}

// ─────────────────────────────────────────────────────────────────────────────
// DynamicContentParser — ported from dirsearch lib/utils/diff.py
// ─────────────────────────────────────────────────────────────────────────────

/// Determines whether a new HTTP response body is "wildcard-like" (soft-404).
/// Ported from dirsearch's DynamicContentParser.
class _DynamicContentParser {
  final bool _isStatic;
  final String _baseContent;
  final List<String> _staticPatterns; // ordered LCS tokens
  final int _lcsLen;

  const _DynamicContentParser._(
    this._isStatic,
    this._baseContent,
    this._staticPatterns,
    this._lcsLen,
  );

  factory _DynamicContentParser.fromContents(String c1, String c2) {
    if (c1 == c2) {
      return const _DynamicContentParser._(true, '', [], 0);
    }
    final w1 = c1.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final w2 = c2.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final stable = _lcsWords(w1, w2);
    return _DynamicContentParser._(false, c1, stable, stable.length);
  }

  /// Returns true if [content] is similar to the wildcard baseline (should be filtered).
  bool compareTo(String content) {
    if (_isStatic) return content == _baseContent;

    final words = content.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    var cursor = 0;
    var misses = 0;

    for (final pattern in _staticPatterns) {
      final idx = _indexFrom(words, pattern, cursor);
      if (idx == -1) {
        // Allow one miss when there are >=20 stable patterns
        if (misses > 0 || _staticPatterns.length < 20) return false;
        misses++;
      } else {
        cursor = idx + 1;
      }
    }

    // Fallback ratio check — mirrors Python's SequenceMatcher.ratio() > 0.75
    final baseWords =
        _baseContent.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length > baseWords.length && _staticPatterns.length < 20) {
      final total = baseWords.length + words.length;
      if (total > 0 && (2 * _lcsLen) / total <= 0.75) return false;
    }

    return true;
  }

  static int _indexFrom(List<String> list, String item, int start) {
    for (var i = start; i < list.length; i++) {
      if (list[i] == item) return i;
    }
    return -1;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Redirect regex — ported from dirsearch lib/utils/diff.py generate_matching_regex
// ─────────────────────────────────────────────────────────────────────────────

const _kReflectedMarker = '__REFLECTED_PATH__';

String _generateMatchingRegex(String s1, String s2) {
  final buf = StringBuffer('^');
  var i = 0;
  while (i < s1.length && i < s2.length) {
    if (s1[i] != s2[i]) {
      buf.write('.*');
      break;
    }
    buf.write(RegExp.escape(s1[i]));
    i++;
  }
  if (!buf.toString().endsWith('.*')) {
    return '${buf.toString()}\$';
  }
  // Find common suffix
  var suffix = '';
  var j1 = s1.length - 1, j2 = s2.length - 1;
  while (j1 >= i && j2 >= 0 && s1[j1] == s2[j2]) {
    suffix = RegExp.escape(s1[j1]) + suffix;
    j1--;
    j2--;
  }
  return '${buf.toString()}$suffix\$';
}

String? _generateRedirectRegex(
    String firstLoc, String firstPath, String secondLoc, String secondPath) {
  final loc1 = firstPath.isNotEmpty
      ? firstLoc.replaceAll('/$firstPath', _kReflectedMarker)
      : firstLoc;
  final loc2 = secondPath.isNotEmpty
      ? secondLoc.replaceAll('/$secondPath', _kReflectedMarker)
      : secondLoc;
  return _generateMatchingRegex(loc1, loc2);
}

// ─────────────────────────────────────────────────────────────────────────────
// Wildcard scanner — corresponds to dirsearch Scanner class
// ─────────────────────────────────────────────────────────────────────────────

/// Holds wildcard detection state for a single path-type category
/// (default, a specific extension, suffix, or prefix).
class _WildcardScanner {
  final int wildcardStatus;
  final _DynamicContentParser contentParser;
  final String? wildcardRedirectRegex;

  const _WildcardScanner({
    required this.wildcardStatus,
    required this.contentParser,
    this.wildcardRedirectRegex,
  });

  /// Returns true = real result (not wildcard), false = wildcard (should be excluded).
  bool check({
    required int responseStatus,
    required String? responseBody,
    required String? responseRedirect,
    required String requestPath,
  }) {
    // Different status -> always a real result
    if (wildcardStatus != responseStatus) return true;

    // Same status -> check redirect pattern first
    if (wildcardRedirectRegex != null &&
        responseRedirect != null &&
        responseRedirect.isNotEmpty) {
      final cleanPath = requestPath.startsWith('/')
          ? requestPath.substring(1)
          : requestPath;
      final normalizedRedirect =
          responseRedirect.replaceAll('/$cleanPath', _kReflectedMarker);
      final matches =
          RegExp(wildcardRedirectRegex!, caseSensitive: false).hasMatch(normalizedRedirect);
      if (!matches) return true; // redirect differs -> real result
    }

    // Check content similarity
    if (responseBody != null && responseBody.isNotEmpty) {
      return !contentParser.compareTo(responseBody);
    }

    // No body -> conservatively treat as wildcard (same status, unknown content)
    return false;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Full HTTP response (for scanner initialization)
// ─────────────────────────────────────────────────────────────────────────────

class _FullResponse {
  final int status;
  final String body; // empty for binary or on error
  final String? redirect;
  final int contentLength;

  const _FullResponse({
    required this.status,
    required this.body,
    this.redirect,
    required this.contentLength,
  });
}

class _ScriptAliasProfile {
  final int status;
  final int contentLength;
  const _ScriptAliasProfile({
    required this.status,
    required this.contentLength,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Blacklists — ported from dirsearch db/400_blacklist.txt etc.
// ─────────────────────────────────────────────────────────────────────────────

const _kBlacklists = <int, List<String>>{
  400: [
    '%2e%2e//google.com',
    '%ff',
    '%2e%2e/%2e%2e/%2e%2e/%2e%2e/%2e%2e/%2e%2e/etc/passwd',
    '%2e%2e;/test',
    '%3f/',
    '%c0%ae%c0%ae%c0%af',
    '../../../../../../etc/passwd',
    '..;/',
    'cgi-bin/.%2e/%2e%2e/%2e%2e/%2e%2e/etc/passwd',
  ],
  403: [
    '%2e%2e//google.com',
    '%ff',
    '%2e%2e/%2e%2e/%2e%2e/%2e%2e/%2e%2e/%2e%2e/etc/passwd',
    '%2e%2e;/test',
    '%3f/',
    '%c0%ae%c0%ae%c0%af',
    '../../../../../../etc/passwd',
    '..;/',
    'cgi-bin/.%2e/%2e%2e/%2e%2e/%2e%2e/etc/passwd',
  ],
  500: [
    '%ff',
    '%2e%2e/%2e%2e/%2e%2e/%2e%2e/%2e%2e/%2e%2e/etc/passwd',
    '%3f/',
    '%c0%ae%c0%ae%c0%af',
    '%2e%2e;/test',
    '../../../../../../etc/passwd',
    '..;/',
  ],
};

bool _isBlacklisted(String path, int status) {
  final blacklist = _kBlacklists[status];
  if (blacklist == null) return false;
  final p = path.toLowerCase();
  return blacklist.any((b) => p.endsWith(b));
}

// ─────────────────────────────────────────────────────────────────────────────
// Compute-isolate helpers (unchanged public interface)
// ─────────────────────────────────────────────────────────────────────────────

class _LoadAndExpandArgs {
  final String rawContent;
  final List<String> extensions;
  final bool forceExtensions;
  final bool overwriteExtensions;

  _LoadAndExpandArgs(
    this.rawContent,
    this.extensions, {
    this.forceExtensions = false,
    this.overwriteExtensions = false,
  });
}

class _LoadAndExpandResult {
  final List<String> basePaths;
  final List<String> paths;
  _LoadAndExpandResult(this.basePaths, this.paths);
}

_LoadAndExpandResult _loadAndExpandInIsolate(_LoadAndExpandArgs args) {
  final basePaths = args.rawContent
      .split('\n')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty && !e.startsWith('#'))
      .toList();
  final paths = DirsearchService.expandPaths(
    basePaths: basePaths,
    extensions: args.extensions,
    forceExtensions: args.forceExtensions,
    overwriteExtensions: args.overwriteExtensions,
  );
  return _LoadAndExpandResult(basePaths, paths);
}

class _NextRoundArgs {
  final List<String> dirs200;
  final List<String> basePaths;
  final List<String> extensions;
  final List<String> scannedPaths;
  final int maxPathsPerRound;

  _NextRoundArgs({
    required this.dirs200,
    required this.basePaths,
    required this.extensions,
    required this.scannedPaths,
    required this.maxPathsPerRound,
  });
}

List<String> _computeNextRoundPaths(_NextRoundArgs args) {
  final scannedSet = args.scannedPaths.toSet();
  final nextPaths = <String>{};
  for (final dir in args.dirs200) {
    if (nextPaths.length >= args.maxPathsPerRound) break;
    final children = DirsearchService.childPathsForDirectory(
      dirPath: dir,
      basePaths: args.basePaths,
      extensions: args.extensions,
    );
    for (final c in children) {
      if (nextPaths.length >= args.maxPathsPerRound) break;
      if (!scannedSet.contains(c)) nextPaths.add(c);
    }
  }
  return nextPaths.toList();
}

// ─────────────────────────────────────────────────────────────────────────────
// DirsearchResult (unchanged)
// ─────────────────────────────────────────────────────────────────────────────

/// 路径爆破结果
class DirsearchResult {
  final String path;
  final int statusCode;
  final int contentLength;
  /// 重定向目标（用于递归判断），无则为 null
  final String? redirect;

  const DirsearchResult({
    required this.path,
    required this.statusCode,
    required this.contentLength,
    this.redirect,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// DEFAULT_TEST_PREFIXES / DEFAULT_TEST_SUFFIXES — same as dirsearch settings.py
// ─────────────────────────────────────────────────────────────────────────────

const _kDefaultTestPrefixes = ['.', '.ht'];
const _kDefaultTestSuffixes = ['/', '~'];

// EXCLUDE_OVERWRITE_EXTENSIONS — same as dirsearch settings.py
const _kExcludeOverwriteExtensions = {
  'axd', 'cache', 'coffee', 'conf', 'config', 'css', 'dll', 'lock', 'log',
  'key', 'pub', 'properties', 'ini', 'jar', 'js', 'json', 'toml', 'txt',
  'xml', 'yaml', 'yml',
  // media
  'webm', 'mkv', 'avi', 'ts', 'mov', 'qt', 'amv', 'mp4', 'm4p', 'm4v',
  'mp3', 'swf', 'mpg', 'mpeg', 'jpg', 'jpeg', 'pjpeg', 'png', 'woff',
  'svg', 'webp', 'bmp', 'pdf', 'wav', 'vtt',
};

// ─────────────────────────────────────────────────────────────────────────────
// DirsearchService
// ─────────────────────────────────────────────────────────────────────────────

/// 复刻 [dirsearch](https://github.com/maurosoria/dirsearch) 的 Web 路径爆破逻辑
class DirsearchService {
  // -- Configuration ----------------------------------------------------------

  final String baseUrl;
  final int threads;
  final Duration timeout;
  final Set<int> includeStatus;
  final Set<int> excludeStatus;
  final String userAgent;
  final List<String> extensions;

  // -- Advanced filters (mirrors dirsearch is_excluded options) ---------------

  /// 响应体包含这些文本时过滤（对应 --exclude-texts）
  final List<String> excludeTexts;
  /// 响应体匹配此正则时过滤（对应 --exclude-regex）
  final String? excludeRegex;
  /// 重定向 URL 包含此字符串/正则时过滤（对应 --exclude-redirect）
  final String? excludeRedirect;
  /// 响应体最小字节数，不足则过滤（对应 --minimum-response-size）
  final int minResponseSize;
  /// 响应体最大字节数，超过则过滤，0 = 不限（对应 --maximum-response-size）
  final int maxResponseSize;
  /// 相同响应出现 N 次后过滤，0 = 不限（对应 --filter-threshold）
  final int filterThreshold;

  // -- Internal state ---------------------------------------------------------

  final _activeClients = <http.Client>[];

  /// Default wildcard scanner (random path with no special suffix/prefix).
  _WildcardScanner? _defaultScanner;

  /// Per-suffix wildcard scanners (key = suffix e.g. ".php", "/", "~").
  final _suffixScanners = <String, _WildcardScanner>{};

  /// Per-prefix wildcard scanners (key = prefix e.g. ".", ".ht").
  final _prefixScanners = <String, _WildcardScanner>{};
  /// Script alias scanners for patterns like "/index.php/anything".
  final _scriptAliasScanners = <String, _WildcardScanner>{};
  /// Script alias baseline profile keyed by script root (e.g. "/index.php").
  final _scriptAliasProfiles = <String, _ScriptAliasProfile>{};
  /// Concrete script-file scanners keyed by "<dir>|<ext>".
  final _scriptFileScanners = <String, _WildcardScanner>{};

  /// Response hash → occurrence count (for filter_threshold).
  final _responseHashes = <int, int>{};

  // -- Constructor ------------------------------------------------------------

  DirsearchService({
    required this.baseUrl,
    this.threads = 10,
    this.timeout = const Duration(seconds: 10),
    this.includeStatus = const {200, 201, 301, 302, 401, 403},
    this.excludeStatus = const {},
    this.userAgent =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    this.extensions = const ['php', 'html', 'js', 'txt', 'asp', 'aspx', 'jsp'],
    this.excludeTexts = const [],
    this.excludeRegex,
    this.excludeRedirect,
    this.minResponseSize = 0,
    this.maxResponseSize = 0,
    this.filterThreshold = 0,
  });

  /// 是否需要下载 body 来应用内容过滤器
  bool get _needsBodyForFilters =>
      excludeTexts.isNotEmpty || excludeRegex != null || filterThreshold > 0;

  // -- Static wordlist helpers ------------------------------------------------

  /// 从 assets/defaults/dicts 加载字典
  static Future<List<String>> loadWordlist(String fileName) async {
    String content;
    try {
      content = await rootBundle.loadString('assets/defaults/dicts/$fileName');
    } catch (_) {
      return [];
    }
    return content
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && !e.startsWith('#'))
        .toList();
  }

  /// 加载字典并展开路径（在 isolate 中执行解析和展开，避免 UI 卡顿）
  static Future<({List<String> basePaths, List<String> paths})>
      loadAndExpandWordlistAsync(
    String fileName,
    List<String> extensions, {
    bool forceExtensions = false,
    bool overwriteExtensions = false,
  }) async {
    String content;
    try {
      content = await rootBundle.loadString('assets/defaults/dicts/$fileName');
    } catch (_) {
      return (basePaths: <String>[], paths: <String>[]);
    }
    if (content.isEmpty) return (basePaths: <String>[], paths: <String>[]);
    final r = await compute(
      _loadAndExpandInIsolate,
      _LoadAndExpandArgs(content, extensions,
          forceExtensions: forceExtensions,
          overwriteExtensions: overwriteExtensions),
    );
    return (basePaths: r.basePaths, paths: r.paths);
  }

  /// 列出可用的内置字典（assets/defaults/dicts 下）
  static Future<List<String>> listAvailableDicts() async {
    const candidates = ['common_paths.txt', 'dirsearch_paths.txt'];
    final available = <String>[];
    for (final name in candidates) {
      try {
        await rootBundle.loadString('assets/defaults/dicts/$name');
        available.add(name);
      } catch (_) {}
    }
    return available;
  }

  // -- expandPaths — ported from dirsearch Dictionary.generate() --------------

  /// Expand a list of raw dictionary paths.
  ///
  /// - `%EXT%` -> replaced with each extension (classic dirsearch mode).
  /// - `forceExtensions=true` -> for paths without extension and not ending in `/`,
  ///   also add `path/` and `path.<ext>` variants (like dirsearch's --force-extensions).
  /// - `overwriteExtensions=true` -> replace existing extensions with specified ones.
  static List<String> expandPaths({
    required List<String> basePaths,
    required List<String> extensions,
    bool forceExtensions = false,
    bool overwriteExtensions = false,
  }) {
    final result = <String>{};
    final extTagRegex = RegExp(r'%ext%', caseSensitive: false);
    final extRecognitionRegex = RegExp(r'\w+(\.[a-zA-Z0-9]{2,5}){1,3}~?$');

    for (final path in basePaths) {
      final trimmed = path.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

      // Strip leading "/" to normalise; we add it back below
      final stripped = trimmed.startsWith('/') ? trimmed.substring(1) : trimmed;
      final normalized = '/$stripped';
      final hasExtPlaceholder = trimmed.toLowerCase().contains('%ext%');

      if (hasExtPlaceholder) {
        // Classic dirsearch: replace %EXT% with each extension
        if (extensions.isEmpty) {
          result.add(normalized.replaceAll(extTagRegex, ''));
        } else {
          for (final ext in extensions) {
            result.add(normalized.replaceAll(extTagRegex, ext));
          }
        }
        continue;
      }

      result.add(normalized);

      final hasQuery = stripped.contains('?') || stripped.contains('#');

      if (forceExtensions &&
          !stripped.contains('.') &&
          !stripped.endsWith('/') &&
          !hasQuery) {
        result.add('$normalized/');
        for (final ext in extensions) {
          result.add('$normalized.$ext');
        }
      } else if (overwriteExtensions &&
          !stripped.endsWith('/') &&
          !hasQuery &&
          extRecognitionRegex.hasMatch(stripped)) {
        final dotIdx = stripped.lastIndexOf('.');
        if (dotIdx >= 0) {
          final currentExt = stripped.substring(dotIdx + 1).toLowerCase();
          if (!_kExcludeOverwriteExtensions.contains(currentExt) &&
              !extensions.contains(currentExt)) {
            final base = normalized.substring(0, normalized.lastIndexOf('.'));
            for (final ext in extensions) {
              result.add('$base.$ext');
            }
          }
        }
      }
    }

    return result.toList();
  }

  // -- Directory detection & recursion helpers --------------------------------

  /// 判断路径是否可能为目录（用于递归扫描 200）
  static bool looksLikeDirectory(String path) {
    final p = path.trim();
    if (p.isEmpty) return false;
    if (p.endsWith('/')) return true;
    return !RegExp(r'\.\w+$').hasMatch(p);
  }

  /// 异步生成递归下一轮路径（在 isolate 中执行，避免主 isolate 卡顿）
  static Future<List<String>> computeNextRoundPaths({
    required List<String> dirs200,
    required List<String> basePaths,
    required List<String> extensions,
    required Set<String> scannedPaths,
    int maxPathsPerRound = 50000,
  }) {
    return compute(
      _computeNextRoundPaths,
      _NextRoundArgs(
        dirs200: dirs200,
        basePaths: basePaths,
        extensions: extensions,
        scannedPaths: scannedPaths.toList(),
        maxPathsPerRound: maxPathsPerRound,
      ),
    );
  }

  /// 为已发现的目录生成子路径（用于递归）
  static List<String> childPathsForDirectory({
    required String dirPath,
    required List<String> basePaths,
    required List<String> extensions,
  }) {
    final prefix = dirPath.endsWith('/') ? dirPath : '$dirPath/';
    final result = <String>{};
    for (final p in basePaths) {
      final trimmed = p.trim();
      if (trimmed.isEmpty) continue;
      final normalized =
          trimmed.startsWith('/') ? trimmed : '/$trimmed';
      final child =
          '$prefix${normalized.startsWith('/') ? normalized.substring(1) : normalized}';
      if (child != prefix && child != dirPath) result.add(child);
    }
    return expandPaths(basePaths: result.toList(), extensions: extensions);
  }

  // -- Internal HTTP helpers --------------------------------------------------

  static String _randomHex(int len) {
    final r = Random.secure();
    return List.generate(len, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  /// GET request; returns null on error. Reads body up to 1 MB.
  Future<_FullResponse?> _fetchFull(http.Client client, Uri uri) async {
    try {
      final req = http.Request('GET', uri)
        ..headers['User-Agent'] = userAgent
        ..followRedirects = false;
      final res = await client.send(req).timeout(timeout);
      final bytes = <int>[];
      await for (final chunk in res.stream) {
        bytes.addAll(chunk);
        if (bytes.length >= 1024 * 1024) break; // 1 MB cap
      }
      final body = utf8.decode(bytes, allowMalformed: true);
      final location = res.headers['location'];
      final cl =
          int.tryParse(res.headers['content-length'] ?? '') ?? bytes.length;
      return _FullResponse(
          status: res.statusCode, body: body, redirect: location, contentLength: cl);
    } catch (_) {
      return null;
    }
  }

  /// HEAD -> GET fallback; does NOT download body.
  Future<({int? code, int? contentLength, String? location})> _probePath({
    required http.Client client,
    required Uri url,
  }) async {
    try {
      final headReq = http.Request('HEAD', url)
        ..headers['User-Agent'] = userAgent
        ..followRedirects = false;
      final headRes = await client.send(headReq).timeout(timeout);
      if (headRes.statusCode == 405) {
        return _probeGet(client: client, url: url);
      }
      unawaited(headRes.stream.listen(null).cancel());
      final cl = int.tryParse(headRes.headers['content-length'] ?? '0') ?? 0;
      return (
        code: headRes.statusCode,
        contentLength: cl,
        location: headRes.headers['location']
      );
    } catch (_) {
      return _probeGet(client: client, url: url);
    }
  }

  Future<({int? code, int? contentLength, String? location})> _probeGet({
    required http.Client client,
    required Uri url,
  }) async {
    try {
      final getReq = http.Request('GET', url)
        ..headers['User-Agent'] = userAgent
        ..followRedirects = false;
      final getRes = await client.send(getReq).timeout(timeout);
      final cl = int.tryParse(getRes.headers['content-length'] ?? '0') ?? 0;
      final location = getRes.headers['location'];
      unawaited(getRes.stream.listen(null).cancel());
      return (code: getRes.statusCode, contentLength: cl, location: location);
    } catch (_) {
      return (code: null, contentLength: null, location: null);
    }
  }

  /// Fetch body only (for wildcard comparison after status is already known).
  Future<String?> _fetchBody(http.Client client, Uri url) async {
    try {
      final req = http.Request('GET', url)
        ..headers['User-Agent'] = userAgent
        ..followRedirects = false;
      final res = await client.send(req).timeout(timeout);
      final bytes = <int>[];
      await for (final chunk in res.stream) {
        bytes.addAll(chunk);
        if (bytes.length >= 1024 * 1024) break;
      }
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return null;
    }
  }

  // -- Scanner initialisation — ported from dirsearch Fuzzer.setup_scanners() -

  /// Build a wildcard scanner by making two random requests with the given paths.
  Future<_WildcardScanner?> _buildScanner(
      http.Client client, String path1, String path2) async {
    final base = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    final uri1 = Uri.tryParse('$base$path1');
    final uri2 = Uri.tryParse('$base$path2');
    if (uri1 == null || uri2 == null) return null;

    final r1 = await _fetchFull(client, uri1);
    if (r1 == null) return null;
    final r2 = await _fetchFull(client, uri2);
    if (r2 == null) return null;

    String? redirectRegex;
    if (r1.redirect != null && r2.redirect != null) {
      redirectRegex =
          _generateRedirectRegex(r1.redirect!, path1, r2.redirect!, path2);
    }

    final parser = _DynamicContentParser.fromContents(r1.body, r2.body);
    return _WildcardScanner(
      wildcardStatus: r1.status,
      contentParser: parser,
      wildcardRedirectRegex: redirectRegex,
    );
  }

  /// Initialise all wildcard scanners (default + per-prefix + per-suffix + per-extension).
  /// [basePath] is the directory being scanned (e.g. "admin/"), used so wildcard
  /// test requests hit the same directory as the actual scan (like dirsearch's
  /// fuzzer.set_base_path(directory) + setup_scanners()).
  /// Runs all requests in parallel for speed.
  Future<void> _initScanners(http.Client client, {String basePath = ''}) async {
    // Reset state for this directory
    _defaultScanner = null;
    _suffixScanners.clear();
    _prefixScanners.clear();

    final prefix = basePath.isEmpty
        ? ''
        : (basePath.endsWith('/') ? basePath : '$basePath/');

    final futures = <Future<void>>[];

    // Default scanner: random path with no special suffix/prefix
    futures.add(
      _buildScanner(client, '$prefix${_randomHex(8)}', '$prefix${_randomHex(8)}')
          .then((s) { if (s != null) _defaultScanner = s; }),
    );

    // Suffix scanners (DEFAULT_TEST_SUFFIXES: "/" and "~")
    for (final suf in _kDefaultTestSuffixes) {
      final capturedSuf = suf;
      futures.add(
        _buildScanner(
          client,
          '$prefix${_randomHex(8)}$capturedSuf',
          '$prefix${_randomHex(8)}$capturedSuf',
        ).then((s) { if (s != null) _suffixScanners[capturedSuf] = s; }),
      );
    }

    // Prefix scanners (DEFAULT_TEST_PREFIXES: "." and ".ht")
    for (final pref in _kDefaultTestPrefixes) {
      final capturedPref = pref;
      futures.add(
        _buildScanner(
          client,
          '$prefix$capturedPref${_randomHex(8)}',
          '$prefix$capturedPref${_randomHex(8)}',
        ).then((s) { if (s != null) _prefixScanners[capturedPref] = s; }),
      );
    }

    // Extension scanners (one per configured extension)
    for (final ext in extensions) {
      final suffix = '.$ext';
      if (!_suffixScanners.containsKey(suffix)) {
        final capturedSuf = suffix;
        futures.add(
          _buildScanner(
            client,
            '$prefix${_randomHex(8)}$capturedSuf',
            '$prefix${_randomHex(8)}$capturedSuf',
          ).then((s) { if (s != null) _suffixScanners[capturedSuf] = s; }),
        );
      }
    }

    await Future.wait(futures);
  }

  /// 公开方法：为指定目录初始化 wildcard scanners（每个递归子目录调用一次）。
  /// [basePath] 如 "admin/" 或 "" (根路径)。
  Future<void> initScannersForBase(String basePath) async {
    final client = http.Client();
    _activeClients.add(client);
    try {
      await _initScanners(client, basePath: basePath);
    } finally {
      _activeClients.remove(client);
      client.close();
    }
  }

  // -- Get applicable scanners for a path — mirrors Fuzzer.get_scanners_for() -

  Iterable<_WildcardScanner> _scannersFor(String path) sync* {
    // Clean path: remove leading slash, query, fragment
    var cleanPath = path.startsWith('/') ? path.substring(1) : path;
    final qi = cleanPath.indexOf('?');
    if (qi >= 0) cleanPath = cleanPath.substring(0, qi);
    final fi = cleanPath.indexOf('#');
    if (fi >= 0) cleanPath = cleanPath.substring(0, fi);
    final isConcreteScriptFile = RegExp(
      r'\.(?:php|asp|aspx|jsp)$',
      caseSensitive: false,
    ).hasMatch(cleanPath);

    // Filename for prefix matching (last component after final "/")
    final filename = cleanPath.contains('/')
        ? cleanPath.substring(cleanPath.lastIndexOf('/') + 1)
        : cleanPath;

    for (final entry in _prefixScanners.entries) {
      if (filename.startsWith(entry.key)) yield entry.value;
    }

    for (final entry in _suffixScanners.entries) {
      if (!cleanPath.endsWith(entry.key)) continue;
      // Avoid false negatives: for concrete script files like "upload/shell.php",
      // do not apply dynamic-script extension wildcard scanners.
      if (isConcreteScriptFile && _isDynamicScriptSuffix(entry.key)) {
        continue;
      }
      yield entry.value;
    }

    if (_defaultScanner != null) yield _defaultScanner!;
  }

  // -- Advanced exclusion filters — mirrors dirsearch Fuzzer.is_excluded() ---

  /// Returns true if the response should be excluded from results.
  /// Mirrors dirsearch's is_excluded() checks beyond status-code filtering.
  bool _isExcluded({
    required int code,
    required int contentLength,
    required String? redirect,
    required String? body,
  }) {
    // Size filters (based on Content-Length header)
    if (minResponseSize > 0 && contentLength < minResponseSize) return true;
    if (maxResponseSize > 0 && contentLength > maxResponseSize) return true;

    // Redirect pattern filter
    if (excludeRedirect != null && redirect != null && redirect.isNotEmpty) {
      if (redirect.contains(excludeRedirect!) ||
          RegExp(excludeRedirect!).hasMatch(redirect)) {
        return true;
      }
    }

    // Content-based filters (require body)
    if (body != null && body.isNotEmpty) {
      if (excludeTexts.any((t) => body.contains(t))) return true;
      if (excludeRegex != null && RegExp(excludeRegex!).hasMatch(body)) {
        return true;
      }
      // filter_threshold: hash-based duplicate response filter
      if (filterThreshold > 0) {
        final h = Object.hash(code, body);
        final count = (_responseHashes[h] ?? 0) + 1;
        _responseHashes[h] = count;
        if (count >= filterThreshold) return true;
      }
    }

    return false;
  }

  // -- Cancel -----------------------------------------------------------------

  /// 立即中止所有进行中的 HTTP 请求
  void cancel() {
    for (final c in List.of(_activeClients)) {
      c.close();
    }
  }

  // -- Main scan method -------------------------------------------------------

  /// 执行路径爆破
  Future<List<DirsearchResult>> scan({
    required List<String> paths,
    required void Function(DirsearchResult) onFound,
    required void Function(int current, int total) onProgress,
    required bool Function() isCancelled,
  }) async {
    final results = <DirsearchResult>[];
    final base = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    var completed = 0;
    final total = paths.length;

    // scanners must be pre-initialised via initScannersForBase(); if not done
    // yet (e.g. standalone use), initialise for root now.
    if (_defaultScanner == null &&
        _suffixScanners.isEmpty &&
        _prefixScanners.isEmpty) {
      await initScannersForBase('');
    }

    // -- Chunk paths across threads -------------------------------------------
    final chunkSize = (paths.length / threads).ceil().clamp(1, paths.length);
    final chunks = <List<String>>[];
    for (var i = 0; i < paths.length; i += chunkSize) {
      chunks.add(paths.sublist(i, (i + chunkSize).clamp(0, paths.length)));
    }

    final chunkResults = await Future.wait(chunks.map((chunk) async {
      final chunkFound = <DirsearchResult>[];
      final client = http.Client();
      _activeClients.add(client);
      try {
        for (final path in chunk) {
          if (isCancelled()) break;

          final cleanPath =
              path.startsWith('/') ? path.substring(1) : path;
          final fullUrl = Uri.parse('$base$cleanPath');

          // -- Probe: use GET when body needed for content filters,
          //    otherwise HEAD + GET fallback (saves bandwidth) ----------------
          int? code;
          int? contentLength;
          String? location;
          String? body;
          final concreteScript = _extractConcreteScriptInfo(path);

          if (_needsBodyForFilters) {
            // Single GET retrieves status + body in one round-trip
            final full = await _fetchFull(client, fullUrl);
            if (full != null) {
              code = full.status;
              contentLength = full.contentLength;
              location = full.redirect;
              body = full.body;
            }
          } else {
            final probe = await _probePath(client: client, url: fullUrl);
            code = probe.code;
            contentLength = probe.contentLength;
            location = probe.location;
          }

          if (code == null) {
            _tick(++completed, total, onProgress);
            continue;
          }

          // Heuristic fix:
          // Some targets reply 200 with 0B for arbitrary dynamic routes on HEAD.
          // For such cases, do a lightweight GET-body verification once.
          if (code == 200 &&
              (contentLength ?? 0) == 0 &&
              (location == null || location.isEmpty)) {
            final verifyBody = body ?? await _fetchBody(client, fullUrl);
            if (verifyBody == null || verifyBody.isEmpty) {
              // Silent webshells may legitimately return 200 with empty body.
              // Keep concrete script files and continue filtering later.
              if (concreteScript == null) {
                _tick(++completed, total, onProgress);
                continue;
              }
            }
            body = verifyBody;
            contentLength = verifyBody?.length ?? contentLength;
          }

          // -- Status filtering -----------------------------------------------
          final allowed =
              includeStatus.isEmpty || includeStatus.contains(code);
          final excluded = excludeStatus.contains(code);
          if (!allowed || excluded) {
            _tick(++completed, total, onProgress);
            continue;
          }

          // -- Blacklist filtering --------------------------------------------
          if (_isBlacklisted(path, code)) {
            _tick(++completed, total, onProgress);
            continue;
          }

          // -- Homepage redirect filtering ------------------------------------
          if (_isHomepageRedirect(code, location, base)) {
            _tick(++completed, total, onProgress);
            continue;
          }

          // -- Advanced exclusion filters (is_excluded) -----------------------
          if (_isExcluded(
            code: code,
            contentLength: contentLength ?? 0,
            redirect: location,
            body: body,
          )) {
            _tick(++completed, total, onProgress);
            continue;
          }

          // -- Wildcard scanner check ----------------------------------------
          final applicableScanners = concreteScript != null
              ? await _scannersForConcreteScript(client, concreteScript)
              : _scannersFor(path).toList();
          bool isWildcard = false;

          if (applicableScanners.isNotEmpty) {
            // Download body for wildcard comparison if not already fetched
            if (body == null &&
                applicableScanners.any((s) => s.wildcardStatus == code)) {
              body = await _fetchBody(client, fullUrl);
            }

            for (final scanner in applicableScanners) {
              if (!scanner.check(
                responseStatus: code,
                responseBody: body,
                responseRedirect: location,
                requestPath: path,
              )) {
                isWildcard = true;
                break;
              }
            }
          }

          if (isWildcard) {
            _tick(++completed, total, onProgress);
            continue;
          }

          // Script alias wildcard filtering:
          // e.g. "/index.php/anything" returns the same 200 page for arbitrary tails.
          if (code == 200) {
            // Strong guard: keep "/index.php" itself, but drop
            // "/index.php/..." style front-controller tail routes.
            if (_isScriptAliasTailPath(path) &&
                (location == null || location.isEmpty)) {
              _tick(++completed, total, onProgress);
              continue;
            }

            final scriptRoot = _extractScriptRoot(path);
            if (scriptRoot != null) {
              final rootNoLeadingSlash = scriptRoot.startsWith('/')
                  ? scriptRoot.substring(1)
                  : scriptRoot;
              _WildcardScanner? scriptScanner =
                  _scriptAliasScanners[scriptRoot];
              scriptScanner ??= await _buildScanner(
                client,
                '$rootNoLeadingSlash/${_randomHex(8)}',
                '$rootNoLeadingSlash/${_randomHex(8)}',
              );
              if (scriptScanner != null) {
                _scriptAliasScanners[scriptRoot] = scriptScanner;
                final compareBody = body ?? await _fetchBody(client, fullUrl);
                final real = scriptScanner.check(
                  responseStatus: code,
                  responseBody: compareBody,
                  responseRedirect: location,
                  requestPath: path,
                );
                if (!real) {
                  _tick(++completed, total, onProgress);
                  continue;
                }
              }

              // Additional guard for reflected front-controller routes:
              // build one baseline under same script root and compare
              // status + content-length pattern.
              _ScriptAliasProfile? profile = _scriptAliasProfiles[scriptRoot];
              if (profile == null) {
                final probePath = '$rootNoLeadingSlash/${_randomHex(10)}';
                final probeUri = Uri.parse('$base$probePath');
                final probe = await _probePath(client: client, url: probeUri);
                if (probe.code != null) {
                  profile = _ScriptAliasProfile(
                    status: probe.code!,
                    contentLength: probe.contentLength ?? 0,
                  );
                  _scriptAliasProfiles[scriptRoot] = profile;
                }
              }

              if (profile != null &&
                  profile.status == code &&
                  profile.contentLength > 0 &&
                  (contentLength ?? 0) > 0 &&
                  ((contentLength ?? 0) - profile.contentLength).abs() <= 32 &&
                  (location == null || location.isEmpty)) {
                _tick(++completed, total, onProgress);
                continue;
              }
            }
          }

          // -- Record result -------------------------------------------------
          final r = DirsearchResult(
            path: path,
            statusCode: code,
            contentLength: contentLength ?? 0,
            redirect: location,
          );
          chunkFound.add(r);
          onFound(r);

          _tick(++completed, total, onProgress);
        }
      } finally {
        _activeClients.remove(client);
        client.close();
      }
      return chunkFound;
    }));

    for (final list in chunkResults) {
      results.addAll(list);
    }
    return results;
  }

  void _tick(int completed, int total, void Function(int, int) onProgress) {
    if (completed % 50 == 0 || completed == total) {
      onProgress(completed, total);
    }
  }

  static bool _isHomepageRedirect(int code, String? location, String base) {
    if ((code != 301 && code != 302) || location == null) return false;
    final loc = Uri.tryParse(location);
    if (loc == null) return false;
    final locPath = loc.path.isEmpty ? '/' : loc.path;
    final basePath =
        Uri.tryParse(base)?.path.let((p) => p.isEmpty ? '/' : p) ?? '/';
    return locPath == '/' || locPath == basePath;
  }

  /// Extract script root from a path like "/index.php/a/b" => "/index.php".
  static String? _extractScriptRoot(String path) {
    final clean = path.split('?').first.split('#').first;
    final m = RegExp(
      r'^(/?.+?\.(?:php|asp|aspx|jsp))(?:/.*)$',
      caseSensitive: false,
    ).firstMatch(clean);
    return m?.group(1);
  }

  /// True for paths that look like front-controller script aliases:
  /// "/index.php/anything", "/foo.asp/bar", etc.
  static bool isScriptAliasPath(String path) =>
      _extractScriptRoot(path) != null;

  /// True only for "/index.php/..." style paths, not "/index.php" itself.
  static bool _isScriptAliasTailPath(String path) {
    final clean = path.split('?').first.split('#').first;
    final root = _extractScriptRoot(clean);
    if (root == null) return false;
    return clean != root;
  }

  static bool _isDynamicScriptSuffix(String suffix) {
    switch (suffix.toLowerCase()) {
      case '.php':
      case '.asp':
      case '.aspx':
      case '.jsp':
        return true;
      default:
        return false;
    }
  }

  static ({String dirPrefix, String extension})? _extractConcreteScriptInfo(
    String path,
  ) {
    var clean = path.startsWith('/') ? path.substring(1) : path;
    final qi = clean.indexOf('?');
    if (qi >= 0) clean = clean.substring(0, qi);
    final fi = clean.indexOf('#');
    if (fi >= 0) clean = clean.substring(0, fi);
    if (clean.isEmpty || clean.endsWith('/')) return null;

    final m = RegExp(r'^(.*?)([^/]+\.(php|asp|aspx|jsp))$',
            caseSensitive: false)
        .firstMatch(clean);
    if (m == null) return null;
    final dir = m.group(1) ?? '';
    final ext = '.${(m.group(3) ?? '').toLowerCase()}';
    final dirPrefix = dir.isEmpty ? '' : dir;
    return (dirPrefix: dirPrefix, extension: ext);
  }

  Future<List<_WildcardScanner>> _scannersForConcreteScript(
    http.Client client,
    ({String dirPrefix, String extension}) info,
  ) async {
    final key = '${info.dirPrefix}|${info.extension}';
    _WildcardScanner? scanner = _scriptFileScanners[key];
    scanner ??= await _buildScanner(
      client,
      '${info.dirPrefix}${_randomHex(10)}${info.extension}',
      '${info.dirPrefix}${_randomHex(10)}${info.extension}',
    );
    if (scanner != null) {
      _scriptFileScanners[key] = scanner;
      return <_WildcardScanner>[scanner];
    }
    // Fallback to generic scanners only when dedicated probe is unavailable.
    return _scannersFor('${info.dirPrefix}x${info.extension}').toList();
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T) block) => block(this);
}
