import 'package:flutter/material.dart';

import '../../app/constants.dart';
import '../../exp/vulhub/misc_http_exp_service.dart';
import '_vulhub_page_helpers.dart';
import 'base_vulhub_exp_page.dart';
import '../../app/localization.dart';

class TomcatExpPage extends BaseVulhubExpPage {
  const TomcatExpPage({super.key});

  @override
  State<TomcatExpPage> createState() => _TomcatPageState();
}

class _TomcatPageState extends BaseVulhubExpPageState<TomcatExpPage> {
  @override
  IconData get pageIcon => Icons.cloud_upload;

  @override
  String get appBarTitle => S.vulhubTomcatTitle;

  @override
  String get cardTitle => S.vulhubTomcatCardTitle;

  @override
  String get cardSubtitle => S.vulhubTomcatCardSubtitle;

  final _urlCtrl = TextEditingController();
  final _cmdCtrl = TextEditingController(text: 'id');
  final _timeoutCtrl = TextEditingController();

  TomcatExpService _svc() => TomcatExpService(
    baseUrl: _urlCtrl.text.trim(),
    timeout: Duration(seconds: timeoutFrom(_timeoutCtrl)),
  );

  Future<void> _check() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog(S.expLogEnterTargetUrl);
      return;
    }
    setState(() => running = true);
    appendLog('[*] 检测 CVE-2017-12615 PUT 方法...');
    try {
      final r = await _svc().check();
      appendLog(
        r.vulnerable ? '[+] ${r.vulnName}: ${r.detail}' : '[-] 未检测到 PUT 文件写入',
      );
    } catch (e) {
      appendLog(S.expLogException(e));
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  Future<void> _getShell() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog(S.expLogEnterTargetUrl);
      return;
    }
    setState(() => running = true);
    appendLog('[*] PUT 上传 JSP Webshell...');
    try {
      final shellUrl = await _svc().getShell();
      if (shellUrl != null) {
        appendLog('[+] Webshell 写入成功: $shellUrl?cmd=id');
      } else {
        appendLog('[-] 写入失败（PUT 方法可能未开启）');
      }
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
    appendLog('[*] 上传 Shell 并执行: $cmd');
    try {
      final out = await _svc().execRce(cmd);
      appendLog(
        out != null && out.isNotEmpty ? '[+] 输出:\n$out' : '[-] 无输出或上传失败',
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
          Row(
            children: [
              vBtn(S.btnDetectVuln, running ? null : _check),
              const SizedBox(width: 8),
              vBtn(S.btnGetShell, running ? null : _getShell),
            ],
          ),
          const SizedBox(height: 16),
          vSecTitle(S.sectionCmdExecAutoUpload),
          vTf(_cmdCtrl, S.fieldCommand, 'id'),
          const SizedBox(height: 8),
          vBtn(S.btnExecCmd, running ? null : _exec),
        ],
      ),
    );
  }
}
