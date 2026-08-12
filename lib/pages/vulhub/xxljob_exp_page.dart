import 'package:flutter/material.dart';

import '../../app/constants.dart';
import '../../exp/vulhub/misc_http_exp_service.dart';
import '_vulhub_page_helpers.dart';
import 'base_vulhub_exp_page.dart';
class XxlJobExpPage extends BaseVulhubExpPage {
  final String? initialTargetUrl;

  const XxlJobExpPage({super.key, this.initialTargetUrl});

  @override
  State<XxlJobExpPage> createState() => _XxlJobPageState();
}

class _XxlJobPageState extends BaseVulhubExpPageState<XxlJobExpPage> {
  @override
  IconData get pageIcon => Icons.schedule;
  @override
  String get appBarTitle => 'XXL-JOB Unauthenticated Executor RCE';
  @override
  String get cardTitle => 'XXL-JOB Unauthenticated RCE';
  @override
  String get cardSubtitle => 'Unauthenticated Executor interface. Submit arbitrary shell commands via GLUE_SHELL type (2.2.0)';

  late final TextEditingController _urlCtrl;
  final _cmdCtrl = TextEditingController(text: 'id');
  final _timeoutCtrl = TextEditingController();

  XxlJobExpService _svc() => XxlJobExpService(
    baseUrl: _urlCtrl.text.trim(),
    timeout: Duration(seconds: timeoutFrom(_timeoutCtrl)),
  );

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: widget.initialTargetUrl ?? '');
  }

  Future<void> _check() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog('[!] Please enter the target URL');
      return;
    }
    setState(() => running = true);
    appendLog('[*] 检测 XXL-JOB 执行器未授权...');
    try {
      final r = await _svc().check();
      appendLog(
        r.vulnerable ? '[+] ${r.vulnName}: ${r.detail}' : '[-] 未检测到或已修复',
      );
    } catch (e) {
      appendLog('[!] Error: $e');
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  Future<void> _exec() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog('[!] Please enter the target URL');
      return;
    }
    final cmd = _cmdCtrl.text.trim().isEmpty ? 'id' : _cmdCtrl.text.trim();
    setState(() => running = true);
    appendLog('[*] 提交 GLUE_SHELL 命令: $cmd');
    try {
      final out = await _svc().execRce(cmd);
      appendLog(out != null && out.isNotEmpty ? '[+] 响应:\n$out' : '[-] 无响应');
    } catch (e) {
      appendLog('[!] Error: $e');
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
          vSecTitle('Target config'),
          vTf(_urlCtrl, '执行器 URL', 'http://localhost:8080'),
          const SizedBox(height: 8),
          vTf(
            _timeoutCtrl,
            'Timeout (s)',
            '${AppConstants.defaultHttpTimeoutSeconds}',
            type: TextInputType.number,
          ),
          const SizedBox(height: 8),
          vBtn('检测未授权', running ? null : _check),
          const SizedBox(height: 16),
          vSecTitle('Command execution (blind, verify via OOB)'),
          vTf(_cmdCtrl, 'Command', 'id'),
          const SizedBox(height: 8),
          vBtn('提交命令', running ? null : _exec),
        ],
      ),
    );
  }
}
