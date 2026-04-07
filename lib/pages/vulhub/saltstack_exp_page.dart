import 'package:flutter/material.dart';

import '../../app/constants.dart';
import '../../exp/vulhub/misc_http_exp_service.dart';
import '_vulhub_page_helpers.dart';
import 'base_vulhub_exp_page.dart';

class SaltstackExpPage extends BaseVulhubExpPage {
  const SaltstackExpPage({super.key});

  @override
  State<SaltstackExpPage> createState() => _SaltstackPageState();
}

class _SaltstackPageState extends BaseVulhubExpPageState<SaltstackExpPage> {
  @override
  IconData get pageIcon => Icons.grain;
  @override
  String get appBarTitle => 'SaltStack CVE-2020-16846 SSH 模块命令注入 RCE';
  @override
  String get cardTitle => 'SaltStack CVE-2020-16846';
  @override
  String get cardSubtitle => 'SSH 模块 ssh_priv 参数命令注入，通过 REST API 触发';

  final _urlCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();
  final _cmdCtrl = TextEditingController(text: 'id');
  final _timeoutCtrl = TextEditingController();

  SaltstackExpService _svc() => SaltstackExpService(
        baseUrl: _urlCtrl.text.trim(),
        token: _tokenCtrl.text.trim(),
        timeout: Duration(seconds: timeoutFrom(_timeoutCtrl)),
      );

  Future<void> _check() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog('[!] 请输入目标 URL');
      return;
    }
    if (_tokenCtrl.text.trim().isEmpty) {
      appendLog('[!] 请输入 API Token');
      return;
    }
    setState(() => running = true);
    appendLog('[*] 检测 SaltStack API...');
    try {
      final r = await _svc().check();
      appendLog(r.vulnerable ? '[+] ${r.vulnName}: ${r.detail}' : '[-] 未检测到服务: ${r.detail}');
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
    if (_tokenCtrl.text.trim().isEmpty) {
      appendLog('[!] 请输入 API Token');
      return;
    }
    final cmd = _cmdCtrl.text.trim().isEmpty ? 'id' : _cmdCtrl.text.trim();
    setState(() => running = true);
    appendLog('[*] SSH 模块命令注入: $cmd');
    try {
      final out = await _svc().execRce(cmd);
      appendLog(out != null && out.isNotEmpty ? '[+] 响应:\n$out' : '[-] 无响应');
    } catch (e) {
      appendLog('[!] 异常: $e');
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _tokenCtrl.dispose();
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
          vTf(_tokenCtrl, 'API Token *', ''),
          const SizedBox(height: 8),
          vTf(
            _timeoutCtrl,
            '超时(s)',
            '${AppConstants.defaultHttpTimeoutSeconds}',
            type: TextInputType.number,
          ),
          const SizedBox(height: 8),
          vBtn('检测 API', running ? null : _check),
          const SizedBox(height: 16),
          vSecTitle('SSH 模块命令注入'),
          vTf(_cmdCtrl, '命令', 'id'),
          const SizedBox(height: 8),
          vBtn('执行命令', running ? null : _exec),
        ],
      ),
    );
  }
}
