// 绑定守门：spec 声明的 variant 必须真的指向一个存在的模块。
//
// 检查三件事：
//   1. `moduleId: 'x'` 在 module_registry.dart 里必须存在 `id: 'x'`
//   2. 同一 spec 内 variant id 不重复；跨 spec 的 moduleId 不重复（一个模块只能有一个入口）
//   3. 同一 spec 内字段 key 不重复
//
// 纯文本检查（不加载 Flutter），因此可以在任何环境跑。
// 用法：dart tool/verify/spec_bind.dart
// 退出码 0 = 通过，1 = 有违规。

import 'dart:io';

// 模块 id 有两种声明方式：`id: 'x'` 与 `build(Type.x, 'x', …)`。
final _moduleIdRe = RegExp(r"""\bid:\s*'([^']+)'""");
final _buildIdRe = RegExp(r"""build\(\s*[\w.]+,\s*'([^']+)'""", dotAll: true);
final _moduleIdInSpecRe = RegExp(r"""\bmoduleId:\s*'([^']+)'""");
final _variantIdRe = RegExp(r"""\bvariantId:\s*'([^']+)'""");
final _fieldKeyRe = RegExp(r"""\bkey:\s*'([^']+)'""");
// adapter 侧消费字段的方式：`t['key']` 或 `target['key']`。
final _consumedRe = RegExp(r"""(?:\bt|target)\[\s*'([^']+)'\s*\]""");

int _problems = 0;

void main() {
  final registry = File('lib/exp/core/module_registry.dart');
  if (!registry.existsSync()) {
    stdout.writeln('[!] 找不到 ${registry.path}');
    exit(1);
  }
  final registryText = registry.readAsStringSync();
  final knownModules = {
    ..._moduleIdRe.allMatches(registryText).map((m) => m.group(1)!),
    ..._buildIdRe.allMatches(registryText).map((m) => m.group(1)!),
  };

  final specDir = Directory('lib/exp/specs');
  final specFiles = specDir.existsSync()
      ? specDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .toList()
      : <File>[];

  final consumed = _consumedRe
      .allMatches(registryText)
      .map((m) => m.group(1)!)
      .toSet();
  final claimed = <String, String>{};

  for (final file in specFiles) {
    final text = file.readAsStringSync();
    final rel = file.path;

    final moduleIds = _moduleIdInSpecRe
        .allMatches(text)
        .map((m) => m.group(1)!)
        .toList();
    if (moduleIds.isEmpty) {
      stdout.writeln('[i] $rel: 没有声明任何 variant（跳过）');
      continue;
    }
    for (final id in moduleIds) {
      if (!knownModules.contains(id)) {
        _fail('$rel: moduleId "$id" 在 module_registry.dart 里不存在');
      }
      final previous = claimed[id];
      if (previous != null && previous != rel) {
        _fail('$rel: moduleId "$id" 已被 $previous 占用');
      }
      claimed[id] = rel;
    }

    final duplicates = _duplicates(
      _moduleIdInSpecRe.allMatches(text).map((m) => m.group(1)!),
    );
    for (final d in duplicates) {
      _fail('$rel: moduleId "$d" 重复声明');
    }

    final declared = _fieldKeyRe.allMatches(text).map((m) => m.group(1)!).toList();
    for (final d in _duplicates(declared)) {
      _fail('$rel: 字段 key "$d" 重复');
    }
    // 声明了却没人读 = 表单上一个假的输入框。
    for (final k in declared) {
      if (!consumed.contains(k)) {
        _fail('$rel: 字段 "$k" 没有被任何 adapter 消费（请删除或接线）');
      }
    }

    // variant 级 id（`ExpVariant(id: …)`）与 moduleId 常同名，这里只做存在性提示。
    final variantIds = _variantIdRe.allMatches(text).map((m) => m.group(1)!).toList();
    if (variantIds.isNotEmpty) {
      stdout.writeln('[i] $rel: $variantIds');
    }
  }

  if (_problems > 0) {
    stdout.writeln('[!] spec_bind: $_problems 处违规');
    exit(1);
  }
  stdout.writeln(
    '[+] spec_bind: 通过（${specFiles.length} 个 spec / ${claimed.length} 个 variant）',
  );
  exit(0);
}

Iterable<String> _duplicates(Iterable<String> values) {
  final seen = <String>{};
  final dup = <String>{};
  for (final v in values) {
    if (!seen.add(v)) dup.add(v);
  }
  return dup;
}

void _fail(String message) {
  _problems++;
  stdout.writeln('[!] $message');
}
