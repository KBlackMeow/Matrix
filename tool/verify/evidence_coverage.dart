// 证据强度覆盖：标了 strong 的变体，必须在实靶矩阵里有用例。
//
// 动机：`ExpEvidence` 是人工标的。没有这条规则，谁都可以把某个变体标高，
// 而它可能从来没在真实目标上跑通过。这里把"标注"和"实靶覆盖"绑起来。
//
// 例外必须显式列出并写原因（allowlist），不允许静默跳过。
//
// 用法：dart tool/verify/evidence_coverage.dart
// 退出码 0 = 覆盖完整，1 = 有 strong 变体没有实靶用例。

import 'dart:io';

/// 已知无法实靶覆盖的变体 → 原因。
const _allowlist = <String, String>{
  'struts2-s2057': '本地 2.3.34-showcase 镜像打不出信号（依赖 alwaysSelectFullNamespace + redirect 链）',
  'zentao-2024-24216': '本地无 zentao 镜像/靶场，整条链未做过运行时验证',
};

void main() {
  final specFiles = Directory('lib/exp/specs')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));

  final weak = <String>{};
  final all = <String>{};
  for (final f in specFiles) {
    final text = f.readAsStringSync();
    for (final block in text.split('\n    ExpVariant(').skip(1)) {
      final m = RegExp(r"moduleId:\s*'([^']+)'").firstMatch(block);
      if (m == null) continue;
      final id = m.group(1)!;
      all.add(id);
      if (block.contains('ExpEvidence.weak')) weak.add(id);
    }
  }

  final covered = RegExp(r"moduleId:\s*'([^']+)'")
      .allMatches(File('tool/verify/live_matrix.dart').readAsStringSync())
      .map((m) => m.group(1)!)
      .toSet();

  final strong = all.difference(weak);
  final missing = strong
      .difference(covered)
      .where((id) => !_allowlist.containsKey(id))
      .toList()
    ..sort();

  stdout.writeln(
    '[*] 变体 ${all.length}：strong ${strong.length} · weak ${weak.length} · '
    '实靶用例覆盖 ${strong.intersection(covered).length}',
  );

  var failed = false;
  if (missing.isNotEmpty) {
    failed = true;
    for (final id in missing) {
      stdout.writeln('[!] strong 但无实靶用例：$id');
    }
  }

  // 反向：weak 变体如果被当成了强证据来断言，也要提示（目前只是信息）
  for (final id in _allowlist.keys) {
    if (!all.contains(id)) {
      stdout.writeln('[!] allowlist 里的 $id 已不存在，请清理');
      failed = true;
    }
  }

  if (!failed) {
    stdout.writeln('[+] evidence_coverage: 通过');
    for (final e in _allowlist.entries) {
      stdout.writeln('[i] 例外 ${e.key}：${e.value}');
    }
    exit(0);
  }
  exit(1);
}
