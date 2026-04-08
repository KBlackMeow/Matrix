import 'package:flutter/material.dart';

import '../../app/constants.dart';
import '../../exp/vulhub/services/confluence_exp_service.dart';
import '../../theme/app_theme.dart';
import '_vulhub_page_helpers.dart';
import 'base_vulhub_exp_page.dart';

class ConfluenceExpPage extends BaseVulhubExpPage {
  const ConfluenceExpPage({super.key});

  @override
  State<ConfluenceExpPage> createState() => _ConfluencePageState();
}

class _ConfluencePageState extends BaseVulhubExpPageState<ConfluenceExpPage> {
  @override
  IconData get pageIcon => Icons.article;
  @override
  String get appBarTitle => 'Confluence CVE-2023-22527 OGNL 注入 RCE';
  @override
  String get cardTitle => 'Confluence CVE-2023-22527';
  @override
  String get cardSubtitle =>
      'Velocity 模板注入 → OGNL 执行，无需认证 (8.0 – 8.5.3)';

  final _urlCtrl     = TextEditingController();
  final _cmdCtrl     = TextEditingController(text: 'id');
  final _timeoutCtrl = TextEditingController();

  ConfluenceExpService _svc() => ConfluenceExpService(
        baseUrl: _urlCtrl.text.trim(),
        timeout: Duration(seconds: timeoutFrom(_timeoutCtrl)),
      );

  Future<void> _check() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog('[!] 请输入目标 URL');
      return;
    }
    setState(() => running = true);
    appendLog('[*] 检测 CVE-2023-22527 OGNL 注入...');
    try {
      final r = await _svc().check();
      appendLog(r.vulnerable
          ? '[+] ${r.vulnName}: ${r.detail}'
          : '[-] 未检测到漏洞');
    } catch (e) {
      appendLog('[!] 异常: $e');
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  Future<void> _execRce() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog('[!] 请输入目标 URL');
      return;
    }
    final cmd = _cmdCtrl.text.trim().isEmpty ? 'id' : _cmdCtrl.text.trim();
    setState(() => running = true);
    appendLog('[*] 执行命令: $cmd');
    try {
      final out = await _svc().execRce(cmd);
      if (out != null && out.isNotEmpty) {
        appendLog('[+] 输出:\n$out');
      } else {
        appendLog('[-] 无输出（命令无回显或利用失败）');
      }
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
          vTf(_urlCtrl, '目标 URL', 'http://localhost:8090'),
          const SizedBox(height: 8),
          vTf(_timeoutCtrl, '超时(s)',
              '${AppConstants.defaultHttpTimeoutSeconds}',
              type: TextInputType.number),
          const SizedBox(height: 8),
          vBtn('检测漏洞', running ? null : _check),
          const SizedBox(height: 12),
          // 漏洞原理说明
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.bgDark,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              '端点: POST /template/aui/text-inline.vm\n'
              'label 参数注入 Velocity 指令 → 访问 OGNL 上下文\n'
              'x 参数作为 OGNL 表达式执行，结果回显在响应体\n'
              '注：Scanner.next() 在无 stdout 时无输出属正常',
              style: AppTextStyles.caption(
                  size: 11, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 16),
          vSecTitle('命令执行'),
          vTf(_cmdCtrl, '命令', 'id'),
          const SizedBox(height: 8),
          vBtn('执行命令', running ? null : _execRce),
        ],
      ),
    );
  }
}
