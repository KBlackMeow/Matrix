import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CLI entrypoint absence', () {
    test('bin/mcp_server.dart must not exist', () {
      final file = File('bin/mcp_server.dart');
      expect(file.existsSync(), isFalse,
          reason: 'bin/mcp_server.dart 应已被删除。MCP CLI 入口已移除，'
              '请使用应用内 lib/pages/mcp_server_page.dart 的本地 HTTP 服务。');
    });
  });
}
