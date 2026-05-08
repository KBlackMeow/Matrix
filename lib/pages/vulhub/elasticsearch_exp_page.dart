import 'package:flutter/material.dart';

import '../../app/constants.dart';
import '../../exp/vulhub/misc_http_exp_service.dart';
import '_vulhub_page_helpers.dart';
import 'base_vulhub_exp_page.dart';
import '../../app/localization.dart';

class ElasticsearchExpPage extends BaseVulhubExpPage {
  const ElasticsearchExpPage({super.key});

  @override
  State<ElasticsearchExpPage> createState() => _ElasticsearchPageState();
}

class _ElasticsearchPageState
    extends BaseVulhubExpPageState<ElasticsearchExpPage> {
  @override
  IconData get pageIcon => Icons.manage_search;

  @override
  String get appBarTitle => S.vulhubElasticTitle;

  @override
  String get cardTitle => S.vulhubElasticCardTitle;

  @override
  String get cardSubtitle => S.vulhubElasticCardSubtitle;

  final _urlCtrl = TextEditingController();
  final _cmdCtrl = TextEditingController(text: 'id');
  final _timeoutCtrl = TextEditingController();

  ElasticsearchExpService _svc() => ElasticsearchExpService(
    baseUrl: _urlCtrl.text.trim(),
    timeout: Duration(seconds: timeoutFrom(_timeoutCtrl)),
  );

  Future<void> _check() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog(S.expLogEnterTargetUrl);
      return;
    }
    setState(() => running = true);
    appendLog('[*] 检测 CVE-2015-1427 Groovy 沙箱逃逸...');
    try {
      final r = await _svc().check();
      appendLog(
        r.vulnerable ? '[+] ${r.vulnName}: ${r.detail}' : S.expLogNoVulnGeneric,
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
    appendLog('[*] Groovy 脚本 RCE: $cmd');
    try {
      final out = await _svc().execRce(cmd);
      appendLog(
        out != null && out.isNotEmpty ? '[+] 输出:\n$out' : '[-] 无输出或执行失败',
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
          vSecTitle(S.sectionCmdExec),
          vTf(_cmdCtrl, S.fieldCommand, 'id'),
          const SizedBox(height: 8),
          vBtn(S.btnExecCmd, running ? null : _exec),
        ],
      ),
    );
  }
}
