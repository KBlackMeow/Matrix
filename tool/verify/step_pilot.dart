// 步骤体系样板验证：拿 Shiro 跑一遍完整流程 + 依赖阻塞。
//
// 用法：dart tool/verify/step_pilot.dart http://127.0.0.1:18114
// 退出码 0 = 全部符合预期。

import 'dart:io';

import '../../lib/exp/core/exploit_module.dart';
import '../../lib/exp/core/exp_step.dart';
import '../../lib/exp/core/log_line.dart';
import '../../lib/exp/core/step_runner.dart';
import '../../lib/exp/specs/shiro_spec.dart';

Future<void> main(List<String> args) async {
  final url = args.isEmpty ? 'http://127.0.0.1:18114' : args.first;
  final fields = <String, String>{};

  StepRunner runnerFor(void Function(LogLevel, String) log) => StepRunner(
    steps: shiroSpec.steps,
    targetBuilder: () => ExploitTarget(
      url: url,
      timeout: const Duration(seconds: 10),
      extra: Map.of(fields),
    ),
    readField: (k) => fields[k],
    writeField: (k, v) => fields[k] = v,
    log: log,
  );

  void printLog(LogLevel level, String text) => stdout.writeln('    ${level.prefix} $text');

  var failures = 0;

  // 1) 依赖阻塞：还没 key 就跑第 5 步
  {
    final r = runnerFor(printLog);
    final inject = shiroSpec.steps.firstWhere((s) => s.id == 'shiro.inject');
    final ok = r.canRun(inject);
    stdout.writeln('[依赖] 无 key 直接注入 → canRun=$ok status=${r.statusOf(inject).name}');
    if (ok || r.statusOf(inject) != StepStatus.blocked) failures++;
  }

  // 2) 完整流程
  {
    final r = runnerFor(printLog);
    for (final step in shiroSpec.steps) {
      stdout.writeln('[*] ${step.title}');
      await r.run(step);
      final st = r.statusOf(step);
      stdout.writeln('    → ${st.name} ${r.detailOf(step) ?? r.errorOf(step) ?? ''}');
      if (st != StepStatus.ok) {
        failures++;
        stdout.writeln('[!] 步骤未成功：${step.id}');
      }
    }
    stdout.writeln('[*] 产物：${r.artifacts}');
    if (!r.artifacts.containsKey('shellUrl')) {
      failures++;
      stdout.writeln('[!] 没有 shellUrl 产物');
    }
    // 注入成功必须产出 ShellSession，UI 靠它提示并跳转工作区。
    final shell = r.lastShell;
    stdout.writeln('[*] lastShell：${shell?.summary ?? "null"}');
    if (shell == null) {
      failures++;
      stdout.writeln('[!] 注入成功但没有产出 ShellSession（UI 无法提示/跳转）');
    } else if (shell.url != r.artifacts['shellUrl'] ||
        shell.password != r.artifacts['shellPassword']) {
      failures++;
      stdout.writeln('[!] ShellSession 与产物不一致');
    }
    if ((fields['key'] ?? '').isEmpty) {
      failures++;
      stdout.writeln('[!] 爆破出的 key 没有写回字段');
    }
  }

  stdout.writeln(failures == 0 ? '[+] 步骤体系样板通过' : '[!] $failures 处不符合预期');
  exit(failures == 0 ? 0 : 1);
}
