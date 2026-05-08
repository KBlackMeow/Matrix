import 'package:flutter/material.dart';

import '../../app/constants.dart';
import '../../exp/vulhub/misc_http_exp_service.dart';
import '_vulhub_page_helpers.dart';
import 'base_vulhub_exp_page.dart';
import '../../app/localization.dart';

class SolrExpPage extends BaseVulhubExpPage {
  const SolrExpPage({super.key});

  @override
  State<SolrExpPage> createState() => _SolrPageState();
}

class _SolrPageState extends BaseVulhubExpPageState<SolrExpPage> {
  @override
  IconData get pageIcon => Icons.search;

  @override
  String get appBarTitle => S.vulhubSolrTitle;

  @override
  String get cardTitle => S.vulhubSolrCardTitle;

  @override
  String get cardSubtitle => S.vulhubSolrCardSubtitle;

  final _urlCtrl = TextEditingController();
  final _coreCtrl = TextEditingController(text: 'demo');
  final _cmdCtrl = TextEditingController(text: 'id');
  final _timeoutCtrl = TextEditingController();

  SolrExpService _svc() => SolrExpService(
    baseUrl: _urlCtrl.text.trim(),
    coreName: _coreCtrl.text.trim().isEmpty ? 'demo' : _coreCtrl.text.trim(),
    timeout: Duration(seconds: timeoutFrom(_timeoutCtrl)),
  );

  Future<void> _check() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog(S.expLogEnterTargetUrl);
      return;
    }
    setState(() => running = true);
    appendLog('[*] 检测 Solr 服务...');
    try {
      final r = await _svc().check();
      appendLog(
        r.vulnerable ? '[+] ${r.vulnName}: ${r.detail}' : '[-] Solr 不可访问或未检测到',
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
    appendLog('[*] 注册 RunExecutableListener + 触发 commit: $cmd');
    try {
      final out = await _svc().execRce(cmd);
      appendLog(out != null ? '[+] $out' : '[-] 执行失败');
    } catch (e) {
      appendLog(S.expLogException(e));
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _coreCtrl.dispose();
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
          vTf(_coreCtrl, 'Core 名称', 'demo'),
          const SizedBox(height: 8),
          vTf(
            _timeoutCtrl,
            S.fieldTimeout,
            '${AppConstants.defaultHttpTimeoutSeconds}',
            type: TextInputType.number,
          ),
          const SizedBox(height: 8),
          vBtn('检测 Solr', running ? null : _check),
          const SizedBox(height: 16),
          vSecTitle(S.sectionCmdExecOob),
          vTf(_cmdCtrl, S.fieldCommand, 'id'),
          const SizedBox(height: 8),
          vBtn('注入并触发', running ? null : _exec),
        ],
      ),
    );
  }
}
