import 'dart:async' show unawaited;
import 'dart:convert' show utf8;
import 'dart:math' show Random;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

/// compute 用参数，需可序列化
class _LoadAndExpandArgs {
  final String rawContent;
  final List<String> extensions;
  _LoadAndExpandArgs(this.rawContent, this.extensions);
}

/// compute 返回：basePaths 供递归用，paths 为展开后的路径列表
class _LoadAndExpandResult {
  final List<String> basePaths;
  final List<String> paths;
  _LoadAndExpandResult(this.basePaths, this.paths);
}

/// compute 内执行：解析字典 + 展开路径
_LoadAndExpandResult _loadAndExpandInIsolate(_LoadAndExpandArgs args) {
  final basePaths = args.rawContent
      .split('\n')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
  final paths = DirsearchService.expandPaths(
    basePaths: basePaths,
    extensions: args.extensions,
  );
  return _LoadAndExpandResult(basePaths, paths);
}

/// compute 用参数：递归生成下一轮路径
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

/// compute 内执行：为递归扫描生成下一轮路径，避免主 isolate 卡顿
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

/// 路径爆破结果
class DirsearchResult {
  final String path;
  final int statusCode;
  final int contentLength;

  const DirsearchResult({
    required this.path,
    required this.statusCode,
    required this.contentLength,
  });
}

/// 复刻 [dirsearch](https://github.com/maurosoria/dirsearch) 的 Web 路径爆破逻辑
class DirsearchService {
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
        .where((e) => e.isNotEmpty)
        .toList();
  }

  /// 加载字典并展开路径（在 isolate 中执行解析和展开，避免 UI 卡顿）
  /// 返回 (basePaths, paths)，basePaths 供递归 childPathsForDirectory 使用
  static Future<({List<String> basePaths, List<String> paths})>
      loadAndExpandWordlistAsync(
    String fileName,
    List<String> extensions,
  ) async {
    String content;
    try {
      content = await rootBundle.loadString('assets/defaults/dicts/$fileName');
    } catch (_) {
      return (basePaths: <String>[], paths: <String>[]);
    }
    if (content.isEmpty) return (basePaths: <String>[], paths: <String>[]);
    final r = await compute(
      _loadAndExpandInIsolate,
      _LoadAndExpandArgs(content, extensions),
    );
    return (basePaths: r.basePaths, paths: r.paths);
  }

  /// 列出可用的内置字典（assets/defaults/dicts 下）
  static Future<List<String>> listAvailableDicts() async {
    const candidates = [
      'common_paths.txt',
      'dirsearch_paths.txt',
    ];
    final available = <String>[];
    for (final name in candidates) {
      try {
        await rootBundle.loadString('assets/defaults/dicts/$name');
        available.add(name);
      } catch (_) {}
    }
    return available;
  }

  /// 展开路径：仅对含 %EXT% 的路径替换扩展名，其余保持原样与 URL 拼接
  /// - 含 %EXT%：按扩展名替换
  /// - 其他：保持字典原样
  static List<String> expandPaths({
    required List<String> basePaths,
    required List<String> extensions,
  }) {
    final result = <String>{};
    for (final path in basePaths) {
      final trimmed = path.trim();
      if (trimmed.isEmpty) continue;

      final normalized = trimmed.startsWith('/') ? trimmed : '/$trimmed';
      final hasExtPlaceholder = trimmed.contains('%EXT%');

      if (hasExtPlaceholder) {
        if (extensions.isEmpty) {
          result.add(normalized.replaceAll('%EXT%', ''));
        } else {
          for (final ext in extensions) {
            final e = ext.startsWith('.') ? ext : '.$ext';
            result.add(normalized.replaceAll('%EXT%', e));
          }
        }
      } else {
        result.add(normalized);
      }
    }
    return result.toList();
  }

  /// 判断路径是否可能为目录（用于递归扫描 200）
  /// - 以 / 结尾
  /// - 或无文件扩展名（如 .php, .html）
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
      final normalized = trimmed.startsWith('/') ? trimmed : '/$trimmed';
      final child = '$prefix${normalized.startsWith('/') ? normalized.substring(1) : normalized}';
      if (child != prefix && child != dirPath) result.add(child);
    }
    return expandPaths(basePaths: result.toList(), extensions: extensions);
  }

  final String baseUrl;
  final int threads;
  final Duration timeout;
  final Set<int> includeStatus;
  final Set<int> excludeStatus;
  final String userAgent;

  final _activeClients = <http.Client>[];

  /// 软404指纹：移植自 dirsearch 的 DynamicContentParser
  _ContentFingerprint? _wildcardFingerprint;

  static String _randomHex(int len) {
    final r = Random.secure();
    return List.generate(len, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  /// GET 随机路径并返回响应 body 文本；非200或异常返回 null
  Future<String?> _fetchWildcardBody(http.Client client, Uri uri) async {
    try {
      final req = http.Request('GET', uri)
        ..headers['User-Agent'] = userAgent
        ..followRedirects = false;
      final res = await client.send(req).timeout(timeout);
      if (res.statusCode != 200) {
        unawaited(res.stream.listen(null).cancel());
        return null;
      }
      final bytes = await res.stream.toBytes();
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return null;
    }
  }

  /// 扫描前建立软404指纹：两次随机路径均返回200才认定为软404站点
  Future<void> _initWildcard(http.Client client) async {
    final base = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    final c1 = await _fetchWildcardBody(client, Uri.parse('$base${_randomHex(16)}notexist'));
    if (c1 == null) return;
    final c2 = await _fetchWildcardBody(client, Uri.parse('$base${_randomHex(16)}notexist'));
    if (c2 == null) return;
    _wildcardFingerprint = _ContentFingerprint.from(c1, c2);
  }

  /// 下载 GET body 用于与软404指纹比对；失败或非200返回 null
  Future<String?> _fetchBodyForCheck(http.Client client, Uri url) async {
    try {
      final req = http.Request('GET', url)
        ..headers['User-Agent'] = userAgent
        ..followRedirects = false;
      final res = await client.send(req).timeout(timeout);
      if (res.statusCode != 200) {
        unawaited(res.stream.listen(null).cancel());
        return null;
      }
      final bytes = await res.stream.toBytes();
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return null;
    }
  }

  /// 判断是否为软404：使用内容指纹而非大小比较
  bool _isSoft404(String? body) {
    if (_wildcardFingerprint == null || body == null || body.isEmpty) return false;
    return _wildcardFingerprint!.matches(body);
  }

  /// 立即中止所有进行中的 HTTP 请求
  void cancel() {
    for (final c in List.of(_activeClients)) {
      c.close();
    }
  }

  /// 探测路径：先 HEAD，失败或 405 时回退到 GET（GET 仅读 header，不下载 body）
  Future<({int? code, int? contentLength, String? location})> _probePath({
    required http.Client client,
    required Uri url,
    required Duration timeout,
  }) async {
    try {
      final headReq = http.Request('HEAD', url)
        ..headers['User-Agent'] = userAgent
        ..followRedirects = false;
      final headRes = await client.send(headReq).timeout(timeout);
      if (headRes.statusCode == 405) {
        return _probePathWithGet(
          client: client,
          url: url,
          timeout: timeout,
        );
      }
      final contentLength =
          int.tryParse(headRes.headers['content-length'] ?? '0') ?? 0;
      final location = headRes.headers['location'];
      return (code: headRes.statusCode, contentLength: contentLength, location: location);
    } catch (_) {
      return _probePathWithGet(
        client: client,
        url: url,
        timeout: timeout,
      );
    }
  }

  Future<({int? code, int? contentLength, String? location})> _probePathWithGet({
    required http.Client client,
    required Uri url,
    required Duration timeout,
  }) async {
    try {
      final getReq = http.Request('GET', url)
        ..headers['User-Agent'] = userAgent
        ..followRedirects = false;
      final getRes = await client.send(getReq).timeout(timeout);
      final contentLength =
          int.tryParse(getRes.headers['content-length'] ?? '0') ?? 0;
      final location = getRes.headers['location'];
      unawaited(getRes.stream.listen(null).cancel());
      return (code: getRes.statusCode, contentLength: contentLength, location: location);
    } catch (_) {
      return (code: null, contentLength: null, location: null);
    }
  }

  DirsearchService({
    required this.baseUrl,
    this.threads = 10,
    this.timeout = const Duration(seconds: 10),
    this.includeStatus = const {200, 201, 301, 302, 401, 403},
    this.excludeStatus = const {},
    this.userAgent =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  });

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

    // 软404基线探测：扫描前请求随机不存在路径，检测服务器是否对所有路径返回200
    final wildcardClient = http.Client();
    _activeClients.add(wildcardClient);
    try {
      await _initWildcard(wildcardClient);
    } finally {
      _activeClients.remove(wildcardClient);
      wildcardClient.close();
    }

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
          final fullUrl = Uri.parse('$base${path.startsWith('/') ? path.substring(1) : path}');
          final (:code, :contentLength, :location) = await _probePath(
            client: client,
            url: fullUrl,
            timeout: timeout,
          );
          if (code != null) {
            final allowed = includeStatus.isEmpty || includeStatus.contains(code);
            final excluded = excludeStatus.contains(code);
            // 排除重定向到主页的误报：301/302 且 Location 指向根路径
            final isHomepageRedirect = (code == 301 || code == 302) &&
                location != null &&
                (() {
                  final loc = Uri.tryParse(location);
                  if (loc == null) return false;
                  final locPath = loc.path.isEmpty ? '/' : loc.path;
                  return locPath == '/' || locPath == Uri.parse(base).path;
                })();
            // 软404检测：仅在有基线且响应为200时下载body比对内容
            bool isSoft404 = false;
            if (code == 200 && _wildcardFingerprint != null) {
              final body = await _fetchBodyForCheck(client, fullUrl);
              isSoft404 = _isSoft404(body);
            }
            if (allowed && !excluded && !isHomepageRedirect && !isSoft404) {
              final r = DirsearchResult(
                path: path,
                statusCode: code,
                contentLength: contentLength ?? 0,
              );
              chunkFound.add(r);
              onFound(r);
            }
          }
          completed++;
          if (completed % 50 == 0 || completed == total) {
            onProgress(completed, total);
          }
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
}

/// 移植自 dirsearch 的 DynamicContentParser：
/// 通过比较两次随机路径响应的稳定词 token，判断新响应是否与软404基线相似。
class _ContentFingerprint {
  final bool _isStatic;
  final String _baseContent;
  final List<String> _staticPatterns;

  _ContentFingerprint._(this._isStatic, this._baseContent, this._staticPatterns);

  factory _ContentFingerprint.from(String content1, String content2) {
    if (content1 == content2) {
      return _ContentFingerprint._(true, content1, const []);
    }
    // 提取两次响应中均稳定出现的词 token（有序）
    final words2 = content2.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toSet();
    final stable = content1
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && words2.contains(w))
        .toList();
    return _ContentFingerprint._(false, content1, stable);
  }

  /// 返回 true 表示 content 与软404基线相似（应过滤）
  bool matches(String content) {
    if (_isStatic) return content == _baseContent;

    final words = content.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    var cursor = 0;
    var misses = 0;

    for (final pattern in _staticPatterns) {
      final idx = _indexFrom(words, pattern, cursor);
      if (idx == -1) {
        // dirsearch 允许 20 个以上的模式里漏掉一个
        if (misses > 0 || _staticPatterns.length < 20) return false;
        misses++;
      } else {
        cursor = idx + 1;
      }
    }

    // 模式数少时用相似率兜底（对应 dirsearch 的 SequenceMatcher > 0.75）
    final baseWordCount = _baseContent.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    if (words.length > baseWordCount && _staticPatterns.length < 20) {
      return _jaccardSimilarity(_baseContent, content) > 0.75;
    }

    return true;
  }

  static int _indexFrom(List<String> list, String item, int start) {
    for (var i = start; i < list.length; i++) {
      if (list[i] == item) return i;
    }
    return -1;
  }

  /// Jaccard 相似度：交集词数 / 并集词数
  static double _jaccardSimilarity(String a, String b) {
    final setA = a.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toSet();
    final setB = b.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toSet();
    if (setA.isEmpty && setB.isEmpty) return 1.0;
    if (setA.isEmpty || setB.isEmpty) return 0.0;
    return setA.intersection(setB).length / setA.union(setB).length;
  }
}
