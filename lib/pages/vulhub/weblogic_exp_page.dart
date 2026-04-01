import 'package:flutter/material.dart';
import '../../exp/vulhub/misc_http_exp_service.dart';
import '../../theme/app_theme.dart';
import '_vulhub_page_helpers.dart';

class WebLogicExpPage extends StatelessWidget {
  const WebLogicExpPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.bgDark,
        appBar: AppBar(
          backgroundColor: AppColors.bgElevated, elevation: 0,
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).pop()),
          title: Row(children: [
            const Icon(Icons.dns, color: AppColors.primary), const SizedBox(width: 8),
            Text('Oracle WebLogic CVE-2017-10271 / CVE-2020-14882 RCE',
                style: AppTextStyles.heading(size: 14, color: AppColors.primary)),
          ]),
        ),
        body: Padding(padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            vulhubInfoCard(Icons.dns, 'Oracle WebLogic RCE', 'CVE-2017-10271 XMLDecoder 反序列化 + CVE-2020-14882 控制台未授权 RCE'),
            const SizedBox(height: 16),
            const Expanded(child: _WebLogicCard()),
          ]),
        ),
      );
}

class _WebLogicCard extends StatefulWidget {
  const _WebLogicCard();
  @override
  State<_WebLogicCard> createState() => _WebLogicCardState();
}

class _WebLogicCardState extends State<_WebLogicCard> {
  final _urlCtrl = TextEditingController();
  final _cmdCtrl = TextEditingController(text: 'id');
  final _timeoutCtrl = TextEditingController();
  final _logScroll = ScrollController();
  String _log = ''; bool _running = false;
  int _tab = 0; // 0 = CVE-2017-10271, 1 = CVE-2020-14882

  void _log_(String l) {
    setState(() {
      final lines = _log.isEmpty ? <String>[] : _log.split('\n');
      lines.add(l); if (lines.length > 500) lines.removeRange(0, lines.length - 500);
      _log = lines.join('\n');
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients) _logScroll.animateTo(_logScroll.position.maxScrollExtent, duration: const Duration(milliseconds: 100), curve: Curves.easeOut);
    });
  }

  WebLogicExpService _svc() => WebLogicExpService(baseUrl: _urlCtrl.text.trim(), timeout: Duration(seconds: int.tryParse(_timeoutCtrl.text.trim()) ?? 10));

  Future<void> _check() async {
    if (_urlCtrl.text.trim().isEmpty) { _log_('[!] 请输入目标 URL'); return; }
    setState(() => _running = true);
    if (_tab == 0) {
      _log_('[*] 检测 CVE-2017-10271 XMLDecoder 端点...');
      try { final r = await _svc().checkCve201710271(); _log_(r.vulnerable ? '[+] ${r.vulnName}: ${r.detail}' : '[-] 未检测到'); }
      catch (e) { _log_('[!] 异常: $e'); }
    } else {
      _log_('[*] 检测 CVE-2020-14882 控制台路径绕过...');
      try { final r = await _svc().checkCve202014882(); _log_(r.vulnerable ? '[+] ${r.vulnName}: ${r.detail}' : '[-] 未检测到'); }
      catch (e) { _log_('[!] 异常: $e'); }
    }
    if (mounted) setState(() => _running = false);
  }

  Future<void> _exec() async {
    if (_urlCtrl.text.trim().isEmpty) { _log_('[!] 请输入目标 URL'); return; }
    final cmd = _cmdCtrl.text.trim().isEmpty ? 'id' : _cmdCtrl.text.trim();
    setState(() => _running = true);
    if (_tab == 0) {
      _log_('[*] CVE-2017-10271 XMLDecoder RCE: $cmd');
      try { final out = await _svc().execRceCve201710271(cmd); _log_(out != null ? '[+] 响应:\n$out' : '[-] 无响应'); }
      catch (e) { _log_('[!] 异常: $e'); }
    } else {
      _log_('[*] CVE-2020-14882 控制台 RCE: $cmd');
      try { final out = await _svc().execRceCve202014882(cmd); _log_(out != null ? '[+] 响应:\n$out' : '[-] 无响应'); }
      catch (e) { _log_('[!] 异常: $e'); }
    }
    if (mounted) setState(() => _running = false);
  }

  @override
  void dispose() { _urlCtrl.dispose(); _cmdCtrl.dispose(); _timeoutCtrl.dispose(); _logScroll.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => VulhubExpCardShell(
    running: _running, log: _log, logScroll: _logScroll,
    onClearLog: () => setState(() => _log = ''),
    leftPanel: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      vSecTitle('目标配置'),
      vTf(_urlCtrl, '目标 URL', 'http://target.com:7001/'),
      const SizedBox(height: 8),
      vTf(_timeoutCtrl, '超时(s)', '10', type: TextInputType.number),
      const SizedBox(height: 16),
      vSecTitle('CVE 选择'),
      Row(children: [
        _tabBtn('CVE-2017-10271', 0),
        const SizedBox(width: 8),
        _tabBtn('CVE-2020-14882', 1),
      ]),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: AppColors.bgDark, borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.border)),
        child: Text(
          _tab == 0
              ? 'XMLDecoder 反序列化 → /wls-wsat/CoordinatorPortType\n无直接回显，需结合 OOB/写文件验证'
              : '控制台路径绕过 → /console/css/%252e%252e%252fconsole.portal\n无直接回显',
          style: AppTextStyles.caption(size: 11, color: AppColors.textSecondary),
        ),
      ),
      const SizedBox(height: 8),
      vBtn('检测漏洞', _running ? null : _check),
      const SizedBox(height: 16),
      vSecTitle('命令执行'),
      vTf(_cmdCtrl, '命令', 'id'),
      const SizedBox(height: 8),
      vBtn('执行命令', _running ? null : _exec),
    ])),
  );

  Widget _tabBtn(String label, int idx) => GestureDetector(
    onTap: _running ? null : () => setState(() => _tab = idx),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _tab == idx ? AppColors.primary.withValues(alpha: 0.2) : AppColors.bgDark,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _tab == idx ? AppColors.primary.withValues(alpha: 0.6) : AppColors.border),
      ),
      child: Text(label, style: AppTextStyles.caption(size: 11, color: _tab == idx ? AppColors.primary : AppColors.textSecondary)),
    ),
  );
}
