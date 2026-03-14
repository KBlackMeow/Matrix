import 'dart:convert';
import 'dart:io';

/// 网站标题探测（webtitle）：状态码、长度、标题、重定向
/// 输出格式对齐 fscan: [SUCCESS] 网站标题 http://host:port 状态码:200 长度:1706 标题:"xxx"
class WebTitleService {
  final Duration timeout;

  WebTitleService({this.timeout = const Duration(seconds: 5)});

  /// 探测单个 URL，返回格式化的结果行
  Future<WebTitleResult> probe(String url) async {
    HttpClient? client;
    try {
      final normalized = url.trim().startsWith('http') ? url : 'http://$url';
      final uri = Uri.parse(normalized);
      final scheme = uri.scheme.isEmpty ? 'http' : uri.scheme;
      final host = uri.host;
      final port = uri.hasPort ? uri.port : (scheme == 'https' ? 443 : 80);
      final path = uri.path.isEmpty ? '/' : uri.path;
      final baseUri = Uri.parse('$scheme://$host:$port$path');

      client = HttpClient()
        ..connectionTimeout = timeout
        ..badCertificateCallback = (_, __, ___) => true;

      final req = await client.getUrl(baseUri);
      req.headers.set('User-Agent', 'Mozilla/5.0 (compatible; MatrixScanner/1.0)');
      req.followRedirects = false;

      final res = await req.close().timeout(timeout);
      final body = await res.transform(utf8.decoder).join();

      String? redirectUrl;
      if (res.statusCode >= 300 && res.statusCode < 400) {
        redirectUrl = res.headers.value('location');
        if (redirectUrl != null && !redirectUrl.startsWith('http')) {
          redirectUrl = baseUri.resolve(redirectUrl).toString();
        }
      }

      final titleMatch = RegExp(r'<title[^>]*>([^<]*)</title>', caseSensitive: false).firstMatch(body);
      final title = titleMatch?.group(1)?.trim().replaceAll(RegExp(r'\s+'), ' ').substring(0, 80) ?? '';
      final displayTitle = title.isEmpty ? '无标题' : title;

      return WebTitleResult(
        url: baseUri.toString(),
        statusCode: res.statusCode,
        contentLength: body.length,
        title: displayTitle,
        redirectUrl: redirectUrl,
      );
    } catch (_) {
      return WebTitleResult(
        url: url,
        statusCode: -1,
        contentLength: 0,
        title: '探测失败',
        redirectUrl: null,
      );
    } finally {
      client?.close(force: true);
    }
  }

  /// 格式化为 fscan 风格输出
  static String formatResult(WebTitleResult r) {
    final parts = <String>['状态码:${r.statusCode}', '长度:${r.contentLength}', '标题:"${r.title}"'];
    if (r.redirectUrl != null && r.redirectUrl!.isNotEmpty) {
      parts.add('重定向地址: ${r.redirectUrl}');
    }
    return '[SUCCESS] 网站标题 ${r.url}     ${parts.join('    ')}';
  }
}

class WebTitleResult {
  final String url;
  final int statusCode;
  final int contentLength;
  final String title;
  final String? redirectUrl;

  WebTitleResult({
    required this.url,
    required this.statusCode,
    required this.contentLength,
    required this.title,
    this.redirectUrl,
  });
}
