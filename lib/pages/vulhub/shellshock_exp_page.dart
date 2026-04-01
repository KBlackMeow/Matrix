import 'package:flutter/material.dart';

import '../../app/constants.dart';
import '../../exp/vulhub/misc_http_exp_service.dart';
import '_vulhub_page_helpers.dart';
import 'base_vulhub_exp_page.dart';

class ShellshockExpPage extends BaseVulhubExpPage {
  const ShellshockExpPage({super.key});

  @override
  State<ShellshockExpPage> createState() => _ShellshockPageState();
}

class _ShellshockPageState extends BaseVulhubExpPageState<ShellshockExpPage> {
  @override
  IconData get pageIcon => Icons.terminal;
  @override
  String get appBarTitle => 'Bash Shellshock CVE-2014-6271 CGI 命令注入';
  @override
  String get cardTitle => 'Bash Shellshock CVE-2014-6271';
  @override
  String get cardSubtitle => '通过 User-Agent/Referer 环境变量注入触发 Bash 函数解析 RCE';

  final _urlCtrl = TextEditingController();
  final _cgiCtrl = TextEditingController(text: '/cgi-bin/test.cgi');
  final _cmdCtrl = TextEditingController(text: 'id');
  final _timeoutCtrl = TextEditingController();

  ShellshockExpService _svc() => ShellshockExpService(
        baseUrl: _urlCtrl.text.trim(),
        cgiPath:
            _cgiCtrl.text.trim().isEmpty ? '/cgi-bin/test.cgi' : _cgiCtrl.text.trim(),
        timeout: Duration(seconds: timeoutFrom(_timeoutCtrl)),
      );

  Future<void> _check() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog('[!] 请输入目标 URL');
      return;
    }
    setState(() => running = true);
    appendLog('[*] 检测 Shellshock CVE-2014-6271...');
    try {
      final r = await _svc().check();
      appendLog(r.vulnerable ? '[+] ${r.vulnName}: ${r.detail}' : '[-] 未检测到 Shellshock');
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
    appendLog('[*] Shellshock 执行: $cmd');
    try {
      final out = await _svc().execRce(cmd);
      appendLog(out != null && out.isNotEmpty ? '[+] 输出:\n$out' : '[-] 无输出');
    } catch (e) {
      appendLog('[!] 异常: $e');
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _cgiCtrl.dispose();
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
          vTf(_cgiCtrl, 'CGI 路径', '/cgi-bin/test.cgi'),
          const SizedBox(height: 8),
          vTf(
            _timeoutCtrl,
            '超时(s)',
            '${AppConstants.defaultHttpTimeoutSeconds}',
            type: TextInputType.number,
          ),
          const SizedBox(height: 8),
          vBtn('检测漏洞', running ? null : _check),
          const SizedBox(height: 16),
          vSecTitle('命令执行（通过 User-Agent 注入）'),
          vTf(_cmdCtrl, '命令', 'id'),
          const SizedBox(height: 8),
          vBtn('执行命令', running ? null : _exec),
        ],
      ),
    );
  }
}
