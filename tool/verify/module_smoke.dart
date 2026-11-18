// ignore_for_file: avoid_print

/// 模块冒烟测试：直接调用统一模块接口，验证 检测 / 命令执行 / 获取 WebShell。
///
/// 用法：
///   dart tool/verify/module_smoke.dart <moduleId> <url> [cmd] [--shell]
///   dart tool/verify/module_smoke.dart --list
library;

import 'dart:io';

import '../../lib/exp/core/exploit_module.dart';
import '../../lib/exp/core/module_registry.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.first == '--list') {
    for (final m in exploitModules) {
      print('${m.id.padRight(22)} ${m.capabilities.map((c) => c.name).join(',')}'
          '  ${m.category} · ${m.cve}');
    }
    return;
  }
  final id = args[0];
  final url = args.length > 1 ? args[1] : '';
  final cmd = args.length > 2 && !args[2].startsWith('--') ? args[2] : 'id';
  final wantShell = args.contains('--shell');

  final module = exploitModules.where((m) => m.id == id).firstOrNull;
  if (module == null) {
    print('unknown module: $id');
    exitCode = 64;
    return;
  }
  final target = ExploitTarget(url: url);

  print('== ${module.name} (${module.cve}) ==');
  if (module.supports(ExploitCapability.check)) {
    final r = await module.check(target);
    print('check: ${r.summary}');
  }

  if (module.supports(ExploitCapability.exec)) {
    final out = await module.exec(target, cmd);
    print('exec : ${out == null ? "(null)" : out.trim()}');
  }

  if (wantShell && module.supports(ExploitCapability.getShell)) {
    final shell = await module.getShell(target);
    print('shell: ${shell == null ? "(null)" : shell.summary}');
  }
}
