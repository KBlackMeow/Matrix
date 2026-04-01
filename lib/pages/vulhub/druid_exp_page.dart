import 'package:flutter/material.dart';

import '../../app/constants.dart';
import '../../exp/vulhub/misc_http_exp_service.dart';
import '_vulhub_page_helpers.dart';
import 'base_vulhub_exp_page.dart';

class DruidExpPage extends BaseVulhubExpPage {
  const DruidExpPage({super.key});

  @override
  State<DruidExpPage> createState() => _DruidPageState();
}

class _DruidPageState extends BaseVulhubExpPageState<DruidExpPage> {
  @override
  IconData get pageIcon => Icons.data_object;

  @override
  String get appBarTitle => 'Apache Druid CVE-2021-25646 嵌入式 JavaScript RCE';

  @override
  String get cardTitle => 'Apache Druid CVE-2021-25646';

  @override
  String get cardSubtitle => 'Sampler 接口强制执行用户提供的 JavaScript 代码，影响 <= 0.20.0';

  final _urlCtrl = TextEditingController();
  final _cmdCtrl = TextEditingController(text: 'id');
  final _timeoutCtrl = TextEditingController();

  DruidExpService _svc() => DruidExpService(
        baseUrl: _urlCtrl.text.trim(),
        timeout: Duration(seconds: timeoutFrom(_timeoutCtrl)),
      );

  Future<void> _check() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog('[!] 请输入目标 URL');
      return;
    }
    setState(() => running = true);
    appendLog('[*] 检测 CVE-2021-25646...');
    try {
      final r = await _svc().check();
      appendLog(r.vulnerable ? '[+] ${r.vulnName}: ${r.detail}' : '[-] 未检测到漏洞');
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
    appendLog('[*] 执行命令: $cmd');
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
          vBtn('检测漏洞', running ? null : _check),
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
