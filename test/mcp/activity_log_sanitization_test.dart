import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/mcp/log_redaction.dart';

/// 验证 MCP 活动日志保留调试所需的参数与结果摘要，且隐藏密码和正文。
///
/// 检查 handlers.dart 中：
/// - _logCall 把参数格式化委托给 describeToolArguments
/// - _logResult 输出结果摘要
/// - _wrap 提取 TextContent 作为结果摘要
///
/// 同时直接验证 log_redaction.dart 的脱敏行为。
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

    test('_logCall delegates argument formatting to the redactor', () {
      final body = extractBody(source, 'void _logCall(');
      expect(body, isNotEmpty, reason: '找不到 _logCall 函数体');

      expect(body.contains('describeToolArguments'), isTrue);
      expect(body.contains('log('), isTrue);
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

  group('describeToolArguments', () {
    test('masks sensitive argument values', () {
      const args = {
        'password': 'p@ss-value',
        'secret_key': 'secret-value',
        'token': 'token-value',
        'cookie': 'cookie-value',
        'authorization': 'auth-value',
      };

      final line = describeToolArguments(args);

      expect(line, contains('password=***'));
      expect(line, contains('secret_key=***'));
      expect(line, contains('token=***'));
      expect(line, contains('cookie=***'));
      expect(line, contains('authorization=***'));
      for (final value in args.values) {
        expect(line, isNot(contains(value)));
      }
    });

    test('masks sensitive keys case-insensitively', () {
      expect(describeToolArguments({'Password': 'p@ss'}), 'Password=***');
    });

    test('records content length without exposing its body', () {
      final content = List.filled(1024, 'A').join();
      final line = describeToolArguments({
        'content': content,
        'path': '/tmp/example.php',
      });

      expect(line, contains('content=<1024 chars>'));
      expect(line, isNot(contains(content)));
      expect(line, contains('path=/tmp/example.php'));
    });

    test('truncates long non-sensitive values', () {
      final command = List.filled(250, 'x').join();
      final line = describeToolArguments({'command': command});

      expect(line, 'command=${command.substring(0, 200)}…');
    });

    test('keeps ordinary values readable', () {
      expect(
        describeToolArguments({'name': 'web1', 'url': 'https://target/x.php'}),
        'name=web1, url=https://target/x.php',
      );
    });
  });
}
