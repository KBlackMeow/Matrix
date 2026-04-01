import 'package:flutter/material.dart';

import '../../app/constants.dart';
import '../../exp/vulhub/misc_http_exp_service.dart';
import '_vulhub_page_helpers.dart';
import 'base_vulhub_exp_page.dart';

class SupervisorExpPage extends BaseVulhubExpPage {
  const SupervisorExpPage({super.key});

  @override
  State<SupervisorExpPage> createState() => _SupervisorPageState();
}

class _SupervisorPageState extends BaseVulhubExpPageState<SupervisorExpPage> {
  @override
  IconData get pageIcon => Icons.settings_applications;
  @override
  String get appBarTitle => 'Supervisor CVE-2017-11610 XML-RPC 方法链 RCE';
  @override
  String get cardTitle => 'Supervisor CVE-2017-11610';
  @override
  String get cardSubtitle => 'XML-RPC 未授权任意方法调用链 → os.system 执行命令 (3.3.2)';

  final _urlCtrl = TextEditingController();
  final _cmdCtrl = TextEditingController(text: 'id');
  final _timeoutCtrl = TextEditingController();

  SupervisorExpService _svc() => SupervisorExpService(
        baseUrl: _urlCtrl.text.trim(),
        timeout: Duration(seconds: timeoutFrom(_timeoutCtrl)),
      );

  Future<void> _check() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog('[!] 请输入目标 URL');
      return;
    }
    setState(() => running = true);
    appendLog('[*] 检测 Supervisor XML-RPC 端点...');
    try {
      final r = await _svc().check();
      appendLog(r.vulnerable ? '[+] ${r.vulnName}: ${r.detail}' : '[-] 未检测到端点');
    } catch (e) {
      appendLog('[!] 异常: $e');
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  Future<void> _exec() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog('[!] 请输入目标 URL');
      return;
    }
    final cmd = _cmdCtrl.text.trim().isEmpty ? 'id' : _cmdCtrl.text.trim();
    setState(() => running = true);
    appendLog('[*] XML-RPC 方法链执行: $cmd');
    try {
      final out = await _svc().execRce(cmd);
      appendLog(out != null && out.isNotEmpty ? '[+] 响应:\n$out' : '[-] 无输出');
    } catch (e) {
      appendLog('[!] 异常: $e');
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
          vSecTitle('目标配置'),
          vTf(_urlCtrl, '目标 URL', 'http://localhost:8080'),
          const SizedBox(height: 8),
          vTf(
            _timeoutCtrl,
            '超时(s)',
            '${AppConstants.defaultHttpTimeoutSeconds}',
            type: TextInputType.number,
          ),
          const SizedBox(height: 8),
          vBtn('检测 XML-RPC', running ? null : _check),
          const SizedBox(height: 16),
          vSecTitle('命令执行（无回显，需 OOB）'),
          vTf(_cmdCtrl, '命令', 'id'),
          const SizedBox(height: 8),
          vBtn('执行命令', running ? null : _exec),
        ],
      ),
    );
  }
}
