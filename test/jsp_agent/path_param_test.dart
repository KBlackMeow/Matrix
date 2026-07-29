import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 验证 M.java 的 getParam 在 path 参数时，body 中的 path_b64 处理
/// 位于 legacy X-Path-B64 / X-Path Header 回退之前。
///
/// 这是静态源码级检查：读取 tools/jsp_agent/M.java，确认代码顺序。
/// 更完整的集成测试需要用 Java 容器验证中文路径实际返回，属于后续优化。
void main() {
  group('M.java path_b64 param handling', () {
    /// 提取 getParam 方法中 "path".equals(name) 分支的 body。
    /// 从 `if ("path".equals(name)) {` 到对应的 `}` 为止。
    String extractPathBranch(String source) {
      // 找到 if ("path".equals(name)) { 的位置
      final marker = '"path".equals(name)';
      final start = source.indexOf(marker);
      if (start == -1) return '';

      // 从 marker 之后找到第一个 {
      var braceStart = source.indexOf('{', start);
      if (braceStart == -1) return '';

      // 从 { 开始计算嵌套深度
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

    test('path_b64 from body params is processed before X-Path-B64 header', () {
      final mjava = File('tools/jsp_agent/M.java');
      if (!mjava.existsSync()) {
        // 从项目根目录运行时
        final alt = File('tools/jsp_agent/M.java');
        expect(mjava.existsSync() || alt.existsSync(), isTrue,
            reason: 'M.java not found — test must run from project root');
      }

      final source = mjava.existsSync()
          ? mjava.readAsStringSync()
          : File('tools/jsp_agent/M.java').readAsStringSync();

      final pathBranch = extractPathBranch(source);
      expect(pathBranch, isNotEmpty, reason: '找不到 getParam 中 path 分支');

      // 关键断言：body params path_b64 必须在 X-Path-B64 header 之前处理
      final bodyPb64Idx = pathBranch.indexOf('this.params.get("path_b64")');
      final headerPb64Idx = pathBranch.indexOf('X-Path-B64');
      final headerPathIdx = pathBranch.indexOf('X-Path');

      expect(bodyPb64Idx, isNot(-1),
          reason: 'M.java 必须在 path 分支中处理 this.params.get("path_b64")');
      expect(headerPb64Idx, isNot(-1),
          reason: 'X-Path-B64 header 回退应保留');

      // body path_b64 必须在 header 之前
      expect(bodyPb64Idx, lessThan(headerPb64Idx),
          reason: 'body path_b64 处理必须在 X-Path-B64 header 回退之前');

      // X-Path 是最后的回退
      expect(headerPathIdx, isNot(-1),
          reason: 'X-Path header 回退应保留');
    });

    test('comment documents body param priority', () {
      final mjava = File('tools/jsp_agent/M.java');
      if (!mjava.existsSync()) return; // 同上，需要项目根目录运行

      final source = mjava.readAsStringSync();
      final pathBranch = extractPathBranch(source);

      // 验证注释说明优先从 body 参数读取
      expect(
        pathBranch.contains('优先从 body 参数读取 path_b64') ||
            pathBranch.contains('body 参数') ||
            pathBranch.contains('非 ASCII 路径'),
        isTrue,
        reason: 'path 分支应有注释说明 body path_b64 的优先级',
      );
    });
  });
}
