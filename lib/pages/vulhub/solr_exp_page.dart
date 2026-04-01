import 'package:flutter/material.dart';

import '../../app/constants.dart';
import '../../exp/vulhub/misc_http_exp_service.dart';
import '_vulhub_page_helpers.dart';
import 'base_vulhub_exp_page.dart';

class SolrExpPage extends BaseVulhubExpPage {
  const SolrExpPage({super.key});

  @override
  State<SolrExpPage> createState() => _SolrPageState();
}

class _SolrPageState extends BaseVulhubExpPageState<SolrExpPage> {
  @override
  IconData get pageIcon => Icons.search;

  @override
  String get appBarTitle => 'Apache Solr CVE-2017-12629 RunExecutableListener RCE';

  @override
  String get cardTitle => 'Apache Solr CVE-2017-12629';

  @override
  String get cardSubtitle => '通过 Listener 配置 RunExecutableListener 执行任意命令（< 7.1.0）';

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
      appendLog('[!] 请输入目标 URL');
      return;
    }
    setState(() => running = true);
    appendLog('[*] 检测 Solr 服务...');
    try {
      final r = await _svc().check();
      appendLog(r.vulnerable ? '[+] ${r.vulnName}: ${r.detail}' : '[-] Solr 不可访问或未检测到');
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
    appendLog('[*] 注册 RunExecutableListener + 触发 commit: $cmd');
    try {
      final out = await _svc().execRce(cmd);
      appendLog(out != null ? '[+] $out' : '[-] 执行失败');
    } catch (e) {
      appendLog('[!] 异常: $e');
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
          vSecTitle('目标配置'),
          vTf(_urlCtrl, '目标 URL', 'http://localhost:8080'),
          const SizedBox(height: 8),
          vTf(_coreCtrl, 'Core 名称', 'demo'),
          const SizedBox(height: 8),
          vTf(
            _timeoutCtrl,
            '超时(s)',
            '${AppConstants.defaultHttpTimeoutSeconds}',
            type: TextInputType.number,
          ),
          const SizedBox(height: 8),
          vBtn('检测 Solr', running ? null : _check),
          const SizedBox(height: 16),
          vSecTitle('命令执行（无回显，结合 OOB 验证）'),
          vTf(_cmdCtrl, '命令', 'id'),
          const SizedBox(height: 8),
          vBtn('注入并触发', running ? null : _exec),
        ],
      ),
    );
  }
}
