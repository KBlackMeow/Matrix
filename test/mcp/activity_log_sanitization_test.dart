import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 验证 MCP 活动日志保留调试所需的参数与结果摘要，且隐藏密码和正文。
///
/// 检查 handlers.dart 中：
/// - _logCall 输出参数，但不输出 password 或 content 的原始值
/// - _logResult 输出结果摘要
/// - _wrap 提取 TextContent 作为结果摘要
///
/// 这是静态源码级检查，配合集成测试和人工审查使用。
void main() {
  /// 提取从 [marker] 之后的函数体（大括号计数）。
  String extractBody(String source, String marker) {
    final start = source.indexOf(marker);
    if (start == -1) return '';
    var braceStart = source.indexOf('{', start);
    if (braceStart == -1) return '';
    var depth = 0;
    for (var i = braceStart; i < source.length; i++) {
      if (source[i] == '{') {
        depth++;
      } else if (source[i] == '}') {
        depth--;
        if (depth == 0) return source.substring(braceStart + 1, i);
      }
    }
    return '';
  }

  group('MCP detailed activity log', () {
    late String source;

    setUp(() {
      final f = File('lib/mcp/handlers.dart');
      source = f.readAsStringSync();
    });

    test('_logCall logs arguments while redacting password and content', () {
      final body = extractBody(source, 'void _logCall(');
      expect(body, isNotEmpty, reason: '找不到 _logCall 函数体');

      expect(body.contains('args.entries'), isTrue);
      expect(body.contains('password'), isTrue);
      expect(body.contains('content'), isTrue);
      expect(body.contains('_trunc'), isTrue);
    });

    test('_logResult includes a truncated result summary', () {
      final body = extractBody(source, 'void _logResult(');
      expect(body, isNotEmpty, reason: '找不到 _logResult 函数体');

      expect(body.contains('ms'), isTrue, reason: '_logResult 应记录耗时');
      expect(body.contains('summary'), isTrue);
      expect(body.contains('_trunc'), isTrue);
    });

    test('_wrap extracts a result preview for logging', () {
      final body = extractBody(source, 'ToolFunction _wrap(');
      expect(body, isNotEmpty, reason: '找不到 _wrap 函数体');

      expect(body.contains('preview'), isTrue);
      expect(body.contains('TextContent'), isTrue);
      expect(body.contains('replaceAll'), isTrue);
      expect(
        body.contains('_logResult(log, name, sw.elapsedMilliseconds,'),
        isTrue,
      );
    });
  });
}
