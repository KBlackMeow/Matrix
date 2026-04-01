import 'package:flutter/material.dart';
import '../../exp/vulhub/misc_http_exp_service.dart';
import '../../theme/app_theme.dart';
import '_vulhub_page_helpers.dart';

class PhpExpPage extends StatelessWidget {
  const PhpExpPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.bgDark,
        appBar: AppBar(
          backgroundColor: AppColors.bgElevated, elevation: 0,
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).pop()),
          title: Row(children: [
            const Icon(Icons.php, color: AppColors.primary), const SizedBox(width: 8),
            Text('PHP 8.1.0-dev 后门 / CVE-2012-1823 PHP-CGI RCE',
                style: AppTextStyles.heading(size: 14, color: AppColors.primary)),
          ]),
        ),
        body: Padding(padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            vulhubInfoCard(Icons.php, 'PHP RCE 系列', 'PHP 8.1.0-dev User-Agentt 后门 + CVE-2012-1823 PHP-CGI 参数注入'),
            const SizedBox(height: 16),
            const Expanded(child: _PhpCard()),
          ]),
        ),
      );
}

class _PhpCard extends StatefulWidget {
  const _PhpCard();
  @override
  State<_PhpCard> createState() => _PhpCardState();
}

class _PhpCardState extends State<_PhpCard> {
  final _urlCtrl = TextEditingController();
  final _phpPathCtrl = TextEditingController(text: '/index.php');
  final _cmdCtrl = TextEditingController(text: 'id');
  final _timeoutCtrl = TextEditingController();
  final _logScroll = ScrollController();
  String _log = ''; bool _running = false;
  int _tab = 0; // 0 = backdoor, 1 = cgi

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

  PhpBackdoorExpService _backdoorSvc() => PhpBackdoorExpService(
    baseUrl: _urlCtrl.text.trim(), phpPath: _phpPathCtrl.text.trim().isEmpty ? '/index.php' : _phpPathCtrl.text.trim(),
    timeout: Duration(seconds: int.tryParse(_timeoutCtrl.text.trim()) ?? 10),
  );

  PhpCgiExpService _cgiSvc() => PhpCgiExpService(
    baseUrl: _urlCtrl.text.trim(), phpPath: _phpPathCtrl.text.trim().isEmpty ? '/index.php' : _phpPathCtrl.text.trim(),
    timeout: Duration(seconds: int.tryParse(_timeoutCtrl.text.trim()) ?? 10),
  );

  Future<void> _check() async {
    if (_urlCtrl.text.trim().isEmpty) { _log_('[!] 请输入目标 URL'); return; }
    setState(() => _running = true);
    if (_tab == 0) {
      _log_('[*] 检测 PHP 8.1.0-dev User-Agentt 后门...');
      try { final r = await _backdoorSvc().check(); _log_(r.vulnerable ? '[+] ${r.vulnName}: ${r.detail}' : '[-] 未检测到后门'); }
      catch (e) { _log_('[!] 异常: $e'); }
    } else {
      _log_('[*] 检测 CVE-2012-1823 PHP-CGI...');
      try { final r = await _cgiSvc().check(); _log_(r.vulnerable ? '[+] ${r.vulnName}: ${r.detail}' : '[-] 未检测到 PHP-CGI 漏洞'); }
      catch (e) { _log_('[!] 异常: $e'); }
    }
    if (mounted) setState(() => _running = false);
  }

  Future<void> _exec() async {
    if (_urlCtrl.text.trim().isEmpty) { _log_('[!] 请输入目标 URL'); return; }
    final cmd = _cmdCtrl.text.trim().isEmpty ? 'id' : _cmdCtrl.text.trim();
    setState(() => _running = true);
    if (_tab == 0) {
      _log_('[*] PHP 8.1.0-dev 后门 执行: $cmd');
      try { final out = await _backdoorSvc().execRce(cmd); _log_(out != null && out.isNotEmpty ? '[+] 输出:\n$out' : '[-] 无输出'); }
      catch (e) { _log_('[!] 异常: $e'); }
    } else {
      _log_('[*] PHP-CGI 参数注入 执行: $cmd');
      try { final out = await _cgiSvc().execRce(cmd); _log_(out != null && out.isNotEmpty ? '[+] 输出:\n$out' : '[-] 无输出'); }
      catch (e) { _log_('[!] 异常: $e'); }
    }
    if (mounted) setState(() => _running = false);
  }

  @override
  void dispose() { _urlCtrl.dispose(); _phpPathCtrl.dispose(); _cmdCtrl.dispose(); _timeoutCtrl.dispose(); _logScroll.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => VulhubExpCardShell(
    running: _running, log: _log, logScroll: _logScroll,
    onClearLog: () => setState(() => _log = ''),
    leftPanel: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      vSecTitle('目标配置'),
      vTf(_urlCtrl, '目标 URL', 'http://target.com:8080/'),
      const SizedBox(height: 8),
      vTf(_phpPathCtrl, 'PHP 文件路径', '/index.php'),
      const SizedBox(height: 8),
      vTf(_timeoutCtrl, '超时(s)', '10', type: TextInputType.number),
      const SizedBox(height: 16),
      vSecTitle('漏洞类型'),
      Row(children: [
        _tabBtn('PHP 8.1.0-dev 后门', 0),
        const SizedBox(width: 8),
        _tabBtn('CVE-2012-1823 CGI', 1),
      ]),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: AppColors.bgDark, borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.border)),
        child: Text(
          _tab == 0
              ? '通过 User-Agentt 头发送 zerodium 触发器执行 PHP 代码\n影响版本: PHP 8.1.0-dev (2021-03-28 供应链攻击)'
              : '通过 URL 参数 -d allow_url_include=on 注入 PHP 代码\n影响版本: PHP-CGI < 5.3.12 / < 5.4.2',
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
