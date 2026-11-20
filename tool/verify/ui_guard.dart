// UI 一致性守门：exp 目录禁止硬编码色值、字体族与字号。
//
// 统一组件能挡住"页面自己画卡片/日志/按钮"，但挡不住自定义插槽里的
// `Text` + 间距 + 状态色。这条脚本补上物理上覆盖不到的那块。
//
// 用法：
//   dart tool/verify/ui_guard.dart            # 全部目录
//   dart tool/verify/ui_guard.dart lib/exp/ui # 只看某个目录
// 退出码 0 = 通过，1 = 有违规。

import 'dart:io';

/// 默认受约束的目录（相对仓库根）。
const _defaultDirs = <String>[
  'lib/exp/ui',
  'lib/exp/specs',
  'lib/pages/exp',
];

class _Rule {
  const _Rule(this.pattern, this.hint);

  final RegExp pattern;
  final String hint;
}

final _rules = <_Rule>[
  // `ExpColors.` 不能算命中，因此用负向环视排除标识符前缀。
  _Rule(
    RegExp(r'(?<![A-Za-z0-9_])Colors\.'),
    '使用 ExpColors 语义色，不要引用 Material 调色板',
  ),
  _Rule(
    RegExp(r'(?<![A-Za-z0-9_])Color\(0x'),
    '使用 ExpColors，不要写字面色值',
  ),
  _Rule(
    RegExp(r'''(['"])Monaco\1'''),
    '使用 AppTextStyles，不要指定字体族',
  ),
  _Rule(
    RegExp(r'fontSize:'),
    '使用 AppTextStyles.*(size: ExpText.x) 或 ExpButton.labelStyle',
  ),
];

int _violations = 0;

void main(List<String> args) {
  final targets = args.where((a) => !a.startsWith('--')).toList();
  final dirs = targets.isEmpty ? _defaultDirs : targets;
  final root = Directory.current;

  for (final dirPath in dirs) {
    final dir = Directory('${root.path}/$dirPath');
    if (!dir.existsSync()) {
      stdout.writeln('[skip] $dirPath (不存在)');
      continue;
    }
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      _scan(entity, root.path);
    }
  }

  if (_violations == 0) {
    stdout.writeln('[+] ui_guard: 通过（${dirs.length} 个目录）');
    exit(0);
  }
  stdout.writeln('[!] ui_guard: $_violations 处违规');
  exit(1);
}

void _scan(File file, String root) {
  final lines = file.readAsLinesSync();
  for (var i = 0; i < lines.length; i++) {
    final raw = lines[i];
    if (raw.trimLeft().startsWith('//')) continue; // 注释里允许出现这些词
    for (final rule in _rules) {
      if (rule.pattern.hasMatch(raw)) {
        _violations++;
        final rel = file.path.replaceFirst('$root/', '');
        stdout.writeln('[!] $rel:${i + 1}  ${rule.pattern.pattern}  → ${rule.hint}');
      }
    }
  }
}
