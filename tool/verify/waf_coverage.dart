// WAF 覆盖守卫：每个 `check*` 方法都必须判定"是不是被拦了"。
//
// 背景（第 3 轮实靶踩出来的假阴性）：S2-005 / S2-045 / S2-052 / S2-057 的 check
// 拿到 403 后没有判定拦截，直接走"特征不存在"分支，扫描结果就把"没测通"
// 显示成"没漏洞"。这类缺陷靠人眼 review 抓不住，只能靠结构检查。
//
// 规则：`Future<ExpResult> check*( )` 的方法体里必须出现
//   looksLikeWafBlock / looksLikeBlockedBody / probeFailed('…WAF…')
// 之一，否则判定为违规。
//
// 用法：dart tool/verify/waf_coverage.dart
// 退出码 0 = 全覆盖，1 = 有 check 未处理拦截。

import 'dart:io';

final _methodStart = RegExp(r'Future<ExpResult> (check\w*)\s*\(');
const _required = [
  'looksLikeWafBlock',
  'looksLikeBlockedBody',
  'wafBlockedResult',
];

/// 纯分派方法：内部只按变体类型转调上面那几个 check，拦截判定由被调方负责。
const _delegating = {'checkSingle'};

int _violations = 0;

void main() {
  final files = Directory('lib/exp')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  var checked = 0;
  for (final f in files) {
    final text = f.readAsStringSync();
    final matches = _methodStart.allMatches(text).toList();
    for (var i = 0; i < matches.length; i++) {
      final start = matches[i].start;
      final end = i + 1 < matches.length
          ? matches[i + 1].start
          : text.length;
      final body = text.substring(start, end);
      final name = matches[i].group(1)!;
      if (_delegating.contains(name)) {
        stdout.writeln('[i] $name 是分派方法，跳过（拦截判定由被调的 check 负责）');
        continue;
      }
      checked++;
      final ok = _required.any(body.contains);
      if (!ok) {
        _violations++;
        final line = '\n'.allMatches(text.substring(0, start)).length + 1;
        stdout.writeln('[!] ${f.path}:$line  $name 未判定 WAF 拦截');
      }
    }
  }

  checkInlineClosures();

  if (_violations == 0) {
    stdout.writeln('[+] waf_coverage: 通过（$checked 个 check + 内联闭包全覆盖）');
    exit(0);
  }
  stdout.writeln('[!] waf_coverage: $_violations / $checked 个 check 未处理拦截');
  exit(1);
}

/// 内联 `checkFn:` 闭包（Shiro / Zentao 写在 registry 里）不在这份文件的
/// `check*` 方法中，历史上从未被守卫覆盖。规则：闭包必须显式处理拦截
/// （出现 wafBlockedResult / looksLikeWafBlock / ExploitBlocked 之一）。
void checkInlineClosures() {
  final registry = File('lib/exp/core/module_registry.dart');
  if (!registry.existsSync()) return;
  final text = registry.readAsStringSync();
  final starts = RegExp(r'checkFn:\s*\(t\)\s*async\s*\{').allMatches(text).toList();
  for (var i = 0; i < starts.length; i++) {
    final from = starts[i].start;
    final to = i + 1 < starts.length ? starts[i + 1].start : text.length;
    final body = text.substring(from, to);
    final ok = _required.any(body.contains) || body.contains('ExploitBlocked');
    if (!ok) {
      _violations++;
      final line = '\n'.allMatches(text.substring(0, from)).length + 1;
      stdout.writeln('[!] module_registry.dart:$line  内联 checkFn 未判定 WAF 拦截');
    }
  }
}
