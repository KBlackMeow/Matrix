import 'package:flutter/material.dart';
import '../../exp/vulhub/misc_http_exp_service.dart';
import '../../theme/app_theme.dart';
import '_vulhub_page_helpers.dart';

class HttpdExpPage extends StatelessWidget {
  const HttpdExpPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.bgDark,
        appBar: AppBar(
          backgroundColor: AppColors.bgElevated, elevation: 0,
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).pop()),
          title: Row(children: [
            const Icon(Icons.http, color: AppColors.primary), const SizedBox(width: 8),
            Text('Apache HTTP Server CVE-2021-41773 路径穿越 + CGI RCE',
                style: AppTextStyles.heading(size: 14, color: AppColors.primary)),
          ]),
        ),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            vulhubInfoCard(Icons.http, 'Apache HTTPd CVE-2021-41773',
                '路径规范化缺陷 — 文件读取 + CGI 命令执行 (Apache 2.4.49)'),
            const SizedBox(height: 16),
            const Expanded(child: _HttpdCard()),
          ]),
        ),
      );
}

class _HttpdCard extends StatefulWidget {
  const _HttpdCard();
  @override
  State<_HttpdCard> createState() => _HttpdCardState();
}

class _HttpdCardState extends State<_HttpdCard> {
  final _urlCtrl = TextEditingController();
  final _cmdCtrl = TextEditingController(text: 'id');
  final _fileCtrl = TextEditingController(text: '/etc/passwd');
  final _timeoutCtrl = TextEditingController();
  final _logScroll = ScrollController();
  String _log = ''; bool _running = false;

  void _log_(String l) {
    setState(() {
      final lines = _log.isEmpty ? <String>[] : _log.split('\n');
      lines.add(l);
      if (lines.length > 500) lines.removeRange(0, lines.length - 500);
      _log = lines.join('\n');
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients) _logScroll.animateTo(_logScroll.position.maxScrollExtent, duration: const Duration(milliseconds: 100), curve: Curves.easeOut);
    });
  }

  ApacheHttpdExpService _svc() => ApacheHttpdExpService(
    baseUrl: _urlCtrl.text.trim(),
    timeout: Duration(seconds: int.tryParse(_timeoutCtrl.text.trim()) ?? 10),
  );

  Future<void> _check() async {
    if (_urlCtrl.text.trim().isEmpty) { _log_('[!] 请输入目标 URL'); return; }
    setState(() => _running = true);
    _log_('[*] 检测 CVE-2021-41773 路径穿越...');
    try {
      final r = await _svc().check();
      _log_(r.vulnerable ? '[+] ${r.vulnName}: ${r.detail}' : '[-] 未检测到漏洞');
    } catch (e) { _log_('[!] 异常: $e'); }
    finally { if (mounted) setState(() => _running = false); }
  }

  Future<void> _readFile() async {
    if (_urlCtrl.text.trim().isEmpty) { _log_('[!] 请输入目标 URL'); return; }
    final path = _fileCtrl.text.trim().isEmpty ? '/etc/passwd' : _fileCtrl.text.trim();
    setState(() => _running = true);
    _log_('[*] 读取文件: $path');
    try {
      final out = await _svc().readFile(path);
      _log_(out != null && out.isNotEmpty ? '[+] 文件内容:\n$out' : '[-] 读取失败或文件不存在');
    } catch (e) { _log_('[!] 异常: $e'); }
    finally { if (mounted) setState(() => _running = false); }
  }

  Future<void> _execRce() async {
    if (_urlCtrl.text.trim().isEmpty) { _log_('[!] 请输入目标 URL'); return; }
    final cmd = _cmdCtrl.text.trim().isEmpty ? 'id' : _cmdCtrl.text.trim();
    setState(() => _running = true);
    _log_('[*] CGI RCE 执行: $cmd');
    try {
      final out = await _svc().execRce(cmd);
      _log_(out != null && out.isNotEmpty ? '[+] 输出:\n$out' : '[-] 无输出（CGI 可能未启用）');
    } catch (e) { _log_('[!] 异常: $e'); }
    finally { if (mounted) setState(() => _running = false); }
  }

  @override
  void dispose() { _urlCtrl.dispose(); _cmdCtrl.dispose(); _fileCtrl.dispose(); _timeoutCtrl.dispose(); _logScroll.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => VulhubExpCardShell(
    running: _running, log: _log, logScroll: _logScroll,
    onClearLog: () => setState(() => _log = ''),
    leftPanel: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      vSecTitle('目标配置'),
      vTf(_urlCtrl, '目标 URL', 'http://target.com:8080/'),
      const SizedBox(height: 8),
      vTf(_timeoutCtrl, '超时(s)', '10', type: TextInputType.number),
      const SizedBox(height: 16),
      vSecTitle('路径穿越文件读取'),
      vTf(_fileCtrl, '文件路径', '/etc/passwd'),
      const SizedBox(height: 8),
      Row(children: [vBtn('检测漏洞', _running ? null : _check), const SizedBox(width: 8), vBtn('读取文件', _running ? null : _readFile)]),
      const SizedBox(height: 16),
      vSecTitle('CGI RCE（需 mod_cgi 启用）'),
      vTf(_cmdCtrl, '命令', 'id'),
      const SizedBox(height: 8),
      vBtn('执行命令', _running ? null : _execRce),
    ])),
  );
}
