import 'package:flutter/material.dart';
import '../../exp/vulhub/misc_http_exp_service.dart';
import '../../theme/app_theme.dart';
import '_vulhub_page_helpers.dart';

class ShellshockExpPage extends StatelessWidget {
  const ShellshockExpPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.bgDark,
        appBar: AppBar(
          backgroundColor: AppColors.bgElevated, elevation: 0,
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).pop()),
          title: Row(children: [
            const Icon(Icons.terminal, color: AppColors.primary), const SizedBox(width: 8),
            Text('Bash Shellshock CVE-2014-6271 CGI 命令注入',
                style: AppTextStyles.heading(size: 14, color: AppColors.primary)),
          ]),
        ),
        body: Padding(padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            vulhubInfoCard(Icons.terminal, 'Bash Shellshock CVE-2014-6271', '通过 User-Agent/Referer 环境变量注入触发 Bash 函数解析 RCE'),
            const SizedBox(height: 16),
            const Expanded(child: _ShellshockCard()),
          ]),
        ),
      );
}

class _ShellshockCard extends StatefulWidget {
  const _ShellshockCard();
  @override
  State<_ShellshockCard> createState() => _ShellshockCardState();
}

class _ShellshockCardState extends State<_ShellshockCard> {
  final _urlCtrl = TextEditingController();
  final _cgiCtrl = TextEditingController(text: '/cgi-bin/test.cgi');
  final _cmdCtrl = TextEditingController(text: 'id');
  final _timeoutCtrl = TextEditingController();
  final _logScroll = ScrollController();
  String _log = ''; bool _running = false;

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

  ShellshockExpService _svc() => ShellshockExpService(
    baseUrl: _urlCtrl.text.trim(),
    cgiPath: _cgiCtrl.text.trim().isEmpty ? '/cgi-bin/test.cgi' : _cgiCtrl.text.trim(),
    timeout: Duration(seconds: int.tryParse(_timeoutCtrl.text.trim()) ?? 10),
  );

  Future<void> _check() async {
    if (_urlCtrl.text.trim().isEmpty) { _log_('[!] 请输入目标 URL'); return; }
    setState(() => _running = true); _log_('[*] 检测 Shellshock CVE-2014-6271...');
    try { final r = await _svc().check(); _log_(r.vulnerable ? '[+] ${r.vulnName}: ${r.detail}' : '[-] 未检测到 Shellshock'); }
    catch (e) { _log_('[!] 异常: $e'); }
    finally { if (mounted) setState(() => _running = false); }
  }

  Future<void> _exec() async {
    if (_urlCtrl.text.trim().isEmpty) { _log_('[!] 请输入目标 URL'); return; }
    final cmd = _cmdCtrl.text.trim().isEmpty ? 'id' : _cmdCtrl.text.trim();
    setState(() => _running = true); _log_('[*] Shellshock 执行: $cmd');
    try {
      final out = await _svc().execRce(cmd);
      _log_(out != null && out.isNotEmpty ? '[+] 输出:\n$out' : '[-] 无输出');
    } catch (e) { _log_('[!] 异常: $e'); }
    finally { if (mounted) setState(() => _running = false); }
  }

  @override
  void dispose() { _urlCtrl.dispose(); _cgiCtrl.dispose(); _cmdCtrl.dispose(); _timeoutCtrl.dispose(); _logScroll.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => VulhubExpCardShell(
    running: _running, log: _log, logScroll: _logScroll,
    onClearLog: () => setState(() => _log = ''),
    leftPanel: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      vSecTitle('目标配置'),
      vTf(_urlCtrl, '目标 URL', 'http://target.com/'),
      const SizedBox(height: 8),
      vTf(_cgiCtrl, 'CGI 路径', '/cgi-bin/test.cgi'),
      const SizedBox(height: 8),
      vTf(_timeoutCtrl, '超时(s)', '10', type: TextInputType.number),
      const SizedBox(height: 8),
      vBtn('检测漏洞', _running ? null : _check),
      const SizedBox(height: 16),
      vSecTitle('命令执行（通过 User-Agent 注入）'),
      vTf(_cmdCtrl, '命令', 'id'),
      const SizedBox(height: 8),
      vBtn('执行命令', _running ? null : _exec),
    ])),
  );
}
