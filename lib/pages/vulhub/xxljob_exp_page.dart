import 'package:flutter/material.dart';

import '../../app/constants.dart';
import '../../exp/vulhub/misc_http_exp_service.dart';
import '_vulhub_page_helpers.dart';
import 'base_vulhub_exp_page.dart';
import '../../app/localization.dart';

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
  String get appBarTitle => S.vulhubXxljobTitle;
  @override
  String get cardTitle => S.vulhubXxljobCardTitle;
  @override
  String get cardSubtitle => S.vulhubXxljobCardSubtitle;

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
      appendLog(S.expLogEnterTargetUrl);
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
    appendLog('[*] 提交 GLUE_SHELL 命令: $cmd');
    try {
      final out = await _svc().execRce(cmd);
      appendLog(out != null && out.isNotEmpty ? '[+] 响应:\n$out' : '[-] 无响应');
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
          vTf(_urlCtrl, '执行器 URL', 'http://localhost:8080'),
          const SizedBox(height: 8),
          vTf(
            _timeoutCtrl,
            S.fieldTimeout,
            '${AppConstants.defaultHttpTimeoutSeconds}',
            type: TextInputType.number,
          ),
          const SizedBox(height: 8),
          vBtn('检测未授权', running ? null : _check),
          const SizedBox(height: 16),
          vSecTitle(S.sectionCmdExecOob),
          vTf(_cmdCtrl, S.fieldCommand, 'id'),
          const SizedBox(height: 8),
          vBtn('提交命令', running ? null : _exec),
        ],
      ),
    );
  }
}
