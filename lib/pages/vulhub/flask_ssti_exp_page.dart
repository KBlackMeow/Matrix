import 'package:flutter/material.dart';

import '../../app/constants.dart';
import '../../exp/vulhub/misc_http_exp_service.dart';
import '_vulhub_page_helpers.dart';
import 'base_vulhub_exp_page.dart';

class FlaskSstiExpPage extends BaseVulhubExpPage {
  const FlaskSstiExpPage({super.key});

  @override
  State<FlaskSstiExpPage> createState() => _FlaskSstiPageState();
}

class _FlaskSstiPageState extends BaseVulhubExpPageState<FlaskSstiExpPage> {
  @override
  IconData get pageIcon => Icons.code;
  @override
  String get appBarTitle => 'Flask / Jinja2 SSTI 服务端模板注入 RCE';
  @override
  String get cardTitle => 'Flask / Jinja2 SSTI';
  @override
  String get cardSubtitle => '服务端 Jinja2 模板注入，通过 URL 参数执行任意 Python 代码';

  final _urlCtrl = TextEditingController();
  final _paramCtrl = TextEditingController(text: 'name');
  final _cmdCtrl = TextEditingController(text: 'id');
  final _timeoutCtrl = TextEditingController();

  FlaskSstiExpService _svc() => FlaskSstiExpService(
        baseUrl: _urlCtrl.text.trim(),
        paramName: _paramCtrl.text.trim().isEmpty ? 'name' : _paramCtrl.text.trim(),
        timeout: Duration(seconds: timeoutFrom(_timeoutCtrl)),
      );

  Future<void> _check() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog('[!] 请输入目标 URL');
      return;
    }
    setState(() => running = true);
    appendLog('[*] 检测 Jinja2 SSTI（233×233=54289）...');
    try {
      final r = await _svc().check();
      appendLog(r.vulnerable ? '[+] ${r.vulnName}: ${r.detail}' : '[-] 未检测到 SSTI');
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
    appendLog('[*] SSTI RCE 执行: $cmd');
    try {
      final out = await _svc().execRce(cmd);
      appendLog(out != null && out.isNotEmpty ? '[+] 输出:\n$out' : '[-] 无输出或执行失败');
    } catch (e) {
      appendLog('[!] 异常: $e');
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _paramCtrl.dispose();
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
          vTf(_paramCtrl, 'URL 注入参数名', 'name'),
          const SizedBox(height: 8),
          vTf(
            _timeoutCtrl,
            '超时(s)',
            '${AppConstants.defaultHttpTimeoutSeconds}',
            type: TextInputType.number,
          ),
          const SizedBox(height: 8),
          vBtn('检测 SSTI', running ? null : _check),
          const SizedBox(height: 16),
          vSecTitle('命令执行'),
          vTf(_cmdCtrl, '命令', 'id'),
          const SizedBox(height: 8),
          vBtn('执行命令', running ? null : _exec),
        ],
      ),
    );
  }
}
