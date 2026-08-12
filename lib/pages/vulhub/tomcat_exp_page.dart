import 'package:flutter/material.dart';

import '../../app/constants.dart';
import '../../exp/vulhub/misc_http_exp_service.dart';
import '_vulhub_page_helpers.dart';
import 'base_vulhub_exp_page.dart';
class TomcatExpPage extends BaseVulhubExpPage {
  final String? initialTargetUrl;

  const TomcatExpPage({super.key, this.initialTargetUrl});

  @override
  State<TomcatExpPage> createState() => _TomcatPageState();
}

class _TomcatPageState extends BaseVulhubExpPageState<TomcatExpPage> {
  @override
  IconData get pageIcon => Icons.cloud_upload;

  @override
  String get appBarTitle => 'Apache Tomcat CVE-2017-12615 PUT Method Arbitrary File Upload RCE';

  @override
  String get cardTitle => 'Apache Tomcat CVE-2017-12615';

  @override
  String get cardSubtitle => 'Upload JSP Webshell when PUT method is enabled (Tomcat 8.5.19)';

  late final TextEditingController _urlCtrl;
  final _cmdCtrl = TextEditingController(text: 'id');
  final _timeoutCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: widget.initialTargetUrl ?? '');
  }

  TomcatExpService _svc() => TomcatExpService(
    baseUrl: _urlCtrl.text.trim(),
    timeout: Duration(seconds: timeoutFrom(_timeoutCtrl)),
  );

  Future<void> _check() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog('[!] Please enter the target URL');
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
      appendLog('[!] Error: $e');
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  Future<void> _getShell() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog('[!] Please enter the target URL');
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
      appendLog('[!] Error: $e');
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  Future<void> _exec() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog('[!] Please enter the target URL');
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
      appendLog('[!] Error: $e');
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
          vSecTitle('Target config'),
          vTf(_urlCtrl, 'Target URL', 'http://localhost:8080'),
          const SizedBox(height: 8),
          vTf(
            _timeoutCtrl,
            'Timeout (s)',
            '${AppConstants.defaultHttpTimeoutSeconds}',
            type: TextInputType.number,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              vBtn('Detect vuln', running ? null : _check),
              const SizedBox(width: 8),
              vBtn('GetShell', running ? null : _getShell),
            ],
          ),
          const SizedBox(height: 16),
          vSecTitle('Command execution (auto-upload + execute)'),
          vTf(_cmdCtrl, 'Command', 'id'),
          const SizedBox(height: 8),
          vBtn('Execute command', running ? null : _exec),
        ],
      ),
    );
  }
}
