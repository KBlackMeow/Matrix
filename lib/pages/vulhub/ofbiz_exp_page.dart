import 'package:flutter/material.dart';

import '../../app/constants.dart';
import '../../exp/vulhub/misc_http_exp_service.dart';
import '_vulhub_page_helpers.dart';
import 'base_vulhub_exp_page.dart';

class OFBizExpPage extends BaseVulhubExpPage {
  const OFBizExpPage({super.key});

  @override
  State<OFBizExpPage> createState() => _OFBizPageState();
}

class _OFBizPageState extends BaseVulhubExpPageState<OFBizExpPage> {
  @override
  IconData get pageIcon => Icons.business;

  @override
  String get appBarTitle => 'Apache OFBiz CVE-2023-51467 / CVE-2024-38856 Groovy RCE';

  @override
  String get cardTitle => 'Apache OFBiz Groovy RCE';

  @override
  String get cardSubtitle => 'CVE-2023-51467 无需认证 Groovy 注入 / CVE-2024-38856 Unicode 绕过';

  final _urlCtrl = TextEditingController();
  final _cmdCtrl = TextEditingController(text: 'id');
  final _timeoutCtrl = TextEditingController();

  OFBizExpService _svc() => OFBizExpService(
        baseUrl: _urlCtrl.text.trim(),
        timeout: Duration(seconds: timeoutFrom(_timeoutCtrl)),
      );

  Future<void> _check51467() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog('[!] 请输入目标 URL');
      return;
    }
    setState(() => running = true);
    appendLog('[*] 检测 CVE-2023-51467...');
    try {
      final r = await _svc().checkCve202351467();
      appendLog(r.vulnerable ? '[+] ${r.vulnName}: ${r.detail}' : '[-] 未检测到 ${r.vulnName}');
    } catch (e) {
      appendLog('[!] 异常: $e');
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  Future<void> _check38856() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog('[!] 请输入目标 URL');
      return;
    }
    setState(() => running = true);
    appendLog('[*] 检测 CVE-2024-38856...');
    try {
      final r = await _svc().checkCve202438856();
      appendLog(r.vulnerable ? '[+] ${r.vulnName}: ${r.detail}' : '[-] 未检测到 ${r.vulnName}');
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
    appendLog('[*] Groovy RCE 执行 (CVE-2023-51467): $cmd');
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
          const SizedBox(height: 16),
          vSecTitle('漏洞检测'),
          Row(
            children: [
              vBtn('检测 CVE-2023-51467', running ? null : _check51467),
              const SizedBox(width: 8),
              vBtn('检测 CVE-2024-38856', running ? null : _check38856),
            ],
          ),
          const SizedBox(height: 16),
          vSecTitle('Groovy RCE 执行'),
          vTf(_cmdCtrl, '命令', 'id'),
          const SizedBox(height: 8),
          vBtn('执行命令', running ? null : _exec),
        ],
      ),
    );
  }
}
