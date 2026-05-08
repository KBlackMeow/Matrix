import 'package:flutter/material.dart';

import '../../app/constants.dart';
import '../../exp/vulhub/misc_http_exp_service.dart';
import '_vulhub_page_helpers.dart';
import 'base_vulhub_exp_page.dart';
import '../../app/localization.dart';

class ShellshockExpPage extends BaseVulhubExpPage {
  const ShellshockExpPage({super.key});

  @override
  State<ShellshockExpPage> createState() => _ShellshockPageState();
}

class _ShellshockPageState extends BaseVulhubExpPageState<ShellshockExpPage> {
  @override
  IconData get pageIcon => Icons.terminal;
  @override
  String get appBarTitle => S.vulhubShellshockTitle;
  @override
  String get cardTitle => S.vulhubShellshockCardTitle;
  @override
  String get cardSubtitle => S.vulhubShellshockCardSubtitle;

  final _urlCtrl = TextEditingController();
  final _cmdCtrl = TextEditingController(text: 'id');
  final _timeoutCtrl = TextEditingController();

  ShellshockExpService _svc() => ShellshockExpService(
    baseUrl: _urlCtrl.text.trim(),
    timeout: Duration(seconds: timeoutFrom(_timeoutCtrl)),
  );

  Future<void> _check() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog(S.expLogEnterTargetUrl);
      return;
    }
    setState(() => running = true);
    appendLog('[*] 检测 Shellshock CVE-2014-6271...');
    try {
      final svc = _svc();
      final r = await svc.check(onLog: (line) => appendLog(line));
      appendLog(
        r.vulnerable ? '[+] ${r.vulnName}: ${r.detail}' : '[-] 未检测到 Shellshock',
      );
    } catch (e) {
      appendLog(S.expLogException(e));
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  Future<void> _exec() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog(S.expLogEnterTargetUrl);
      return;
    }
    final cmd = _cmdCtrl.text.trim().isEmpty ? 'id' : _cmdCtrl.text.trim();
    setState(() => running = true);
    appendLog('[*] Shellshock 执行: $cmd');
    try {
      final out = await _svc().execRce(cmd, onLog: appendLog);
      appendLog(
        out != null && out.isNotEmpty
            ? '[+] 输出:\n$out'
            : '[-] 无输出（Shellshock 未触发或无回显）',
      );
    } catch (e) {
      appendLog(S.expLogException(e));
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _cmdCtrl.dispose();
    _timeoutCtrl.dispose();
    super.dispose();
  }

  @override
  Widget buildLeftPanel(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          vSecTitle(S.sectionTargetConfig),
          vTf(_urlCtrl, S.fieldTargetUrl, 'http://localhost:8080'),
          const SizedBox(height: 8),
          vTf(
            _timeoutCtrl,
            S.fieldTimeout,
            '${AppConstants.defaultHttpTimeoutSeconds}',
            type: TextInputType.number,
          ),
          const SizedBox(height: 8),
          vBtn(S.btnDetectVuln, running ? null : _check),
          const SizedBox(height: 16),
          vSecTitle(S.sectionCmdExecUserAgentInject),
          vTf(_cmdCtrl, S.fieldCommand, 'id'),
          const SizedBox(height: 8),
          vBtn(S.btnExecCmd, running ? null : _exec),
        ],
      ),
    );
  }
}
