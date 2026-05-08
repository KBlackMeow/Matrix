import 'package:flutter/material.dart';

import '../../app/constants.dart';
import '../../exp/vulhub/misc_http_exp_service.dart';
import '_vulhub_page_helpers.dart';
import 'base_vulhub_exp_page.dart';
import '../../app/localization.dart';

class OFBizExpPage extends BaseVulhubExpPage {
  const OFBizExpPage({super.key});

  @override
  State<OFBizExpPage> createState() => _OFBizPageState();
}

class _OFBizPageState extends BaseVulhubExpPageState<OFBizExpPage> {
  @override
  IconData get pageIcon => Icons.business;

  @override
  String get appBarTitle => S.vulhubOfbizTitle;

  @override
  String get cardTitle => S.vulhubOfbizCardTitle;

  @override
  String get cardSubtitle => S.vulhubOfbizCardSubtitle;

  final _urlCtrl = TextEditingController();
  final _cmdCtrl = TextEditingController(text: 'id');
  final _timeoutCtrl = TextEditingController();
  String _execCve = 'CVE-2023-51467';

  OFBizExpService _svc() => OFBizExpService(
    baseUrl: _urlCtrl.text.trim(),
    timeout: Duration(seconds: timeoutFrom(_timeoutCtrl)),
  );

  Future<void> _check51467() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog(S.expLogEnterTargetUrl);
      return;
    }
    setState(() => running = true);
    appendLog('[*] 检测 CVE-2023-51467...');
    try {
      final r = await _svc().checkCve202351467();
      appendLog(
        r.vulnerable
            ? '[+] ${r.vulnName}: ${r.detail}'
            : '[-] 未检测到 ${r.vulnName}',
      );
    } catch (e) {
      appendLog(S.expLogException(e));
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  Future<void> _check38856() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog(S.expLogEnterTargetUrl);
      return;
    }
    setState(() => running = true);
    appendLog('[*] 检测 CVE-2024-38856...');
    try {
      final r = await _svc().checkCve202438856();
      appendLog(
        r.vulnerable
            ? '[+] ${r.vulnName}: ${r.detail}'
            : '[-] 未检测到 ${r.vulnName}',
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
    appendLog('[*] Groovy RCE 执行 ($_execCve): $cmd');
    try {
      final out = _execCve == 'CVE-2024-38856'
          ? await _svc().execRce38856(cmd)
          : await _svc().execRce(cmd);
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
          const SizedBox(height: 16),
          vSecTitle(S.sectionVulnDetect),
          Row(
            children: [
              vBtn(
                '检测 CVE-2023-51467 (OFBiz 18.12.10)',
                running ? null : _check51467,
              ),
              const SizedBox(width: 8),
              vBtn(
                '检测 CVE-2024-38856 (OFBiz 18.12.11)',
                running ? null : _check38856,
              ),
            ],
          ),
          const SizedBox(height: 16),
          vSecTitle(S.sectionGroovyRce),
          RadioGroup<String>(
            groupValue: _execCve,
            onChanged: (v) {
              if (!running && v != null) setState(() => _execCve = v);
            },
            child: Row(
              children: [
                const Radio<String>(value: 'CVE-2023-51467'),
                const Text('CVE-2023-51467 (OFBiz 18.12.10)'),
                const SizedBox(width: 12),
                const Radio<String>(value: 'CVE-2024-38856'),
                const Text('CVE-2024-38856 (OFBiz 18.12.11)'),
              ],
            ),
          ),
          vTf(_cmdCtrl, S.fieldCommand, 'id'),
          const SizedBox(height: 8),
          vBtn(S.btnExecCmd, running ? null : _exec),
        ],
      ),
    );
  }
}
