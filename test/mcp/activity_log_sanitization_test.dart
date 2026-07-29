import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 验证 MCP 活动日志不记录敏感参数和结果内容。
///
/// 检查 handlers.dart 中：
/// - _logCall 只输出 tool 名 + shell_id
/// - _logResult 只输出 tool 名 + 耗时
/// - _wrap 不计算结果摘要
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

  group('MCP activity log sanitization', () {
    late String source;

    setUp(() {
      final f = File('lib/mcp/handlers.dart');
      source = f.readAsStringSync();
    });

    test('_logCall only logs tool name + shell_id', () {
      final body = extractBody(source, 'void _logCall(');
      expect(body, isNotEmpty, reason: '找不到 _logCall 函数体');

      // 应提取 shell_id
      expect(body.contains('shell_id'), isTrue,
          reason: '_logCall 应只记录 shell_id');

      // 不应有旧的参数遍历/值拼接（args.entries.map.join 等）
      expect(body.contains('args.entries'), isFalse,
          reason: '_logCall 不应遍历全部参数');
      expect(body.contains('.join('), isFalse,
          reason: '_logCall 不应拼接参数值');
      expect(body.contains('password'), isFalse,
          reason: 'password 不应出现在日志代码中');
      expect(body.contains('_trunc'), isFalse,
          reason: '_logCall 不应截断参数值');
    });

    test('_logResult only logs tool name + latency', () {
      final body = extractBody(source, 'void _logResult(');
      expect(body, isNotEmpty, reason: '找不到 _logResult 函数体');

      // 应只有 tool 名和耗时
      expect(body.contains('ms'), isTrue,
          reason: '_logResult 应记录耗时');

      // 不应包含结果内容
      expect(body.contains('summary'), isFalse,
          reason: '_logResult 签名不应含 summary 参数');
      expect(body.contains('_trunc'), isFalse,
          reason: '_logResult 不应截断内容');
    });

    test('_wrap does not extract result preview for logging', () {
      final body = extractBody(source, 'ToolFunction _wrap(');
      expect(body, isNotEmpty, reason: '找不到 _wrap 函数体');

      // 不应提取 TextContent 做结果摘要
      expect(body.contains('preview'), isFalse,
          reason: '_wrap 不应计算结果预览');
      expect(body.contains('TextContent'), isFalse,
          reason: '_wrap 不应提取 TextContent');
      expect(body.contains('replaceAll'), isFalse,
          reason: '_wrap 不应格式化结果文本');
      // 不应有旧的 4 参数 _logResult 调用
      expect(body.contains('_logResult(log, name, sw.elapsedMilliseconds,'),
          isFalse,
          reason: '_logResult 调用不应含第四个参数');
    });
  });
}
