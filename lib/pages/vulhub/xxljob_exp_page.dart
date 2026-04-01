import 'package:flutter/material.dart';
import '../../exp/vulhub/misc_http_exp_service.dart';
import '../../theme/app_theme.dart';
import '_vulhub_page_helpers.dart';

class XxlJobExpPage extends StatelessWidget {
  const XxlJobExpPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.bgDark,
        appBar: AppBar(
          backgroundColor: AppColors.bgElevated, elevation: 0,
          leading: IconButton(icon: const Icon(Icons.schedule), onPressed: () => Navigator.of(context).pop()),
          title: Row(children: [
            const Icon(Icons.schedule, color: AppColors.primary), const SizedBox(width: 8),
            Text('XXL-JOB 未授权访问执行器 RCE',
                style: AppTextStyles.heading(size: 14, color: AppColors.primary)),
          ]),
        ),
        body: Padding(padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            vulhubInfoCard(Icons.schedule, 'XXL-JOB 未授权 RCE', '执行器接口未授权，通过 GLUE_SHELL 类型提交任意 Shell 命令 (2.2.0)'),
            const SizedBox(height: 16),
            const Expanded(child: _XxlCard()),
          ]),
        ),
      );
}

class _XxlCard extends StatefulWidget {
  const _XxlCard();
  @override
  State<_XxlCard> createState() => _XxlCardState();
}

class _XxlCardState extends State<_XxlCard> {
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

  XxlJobExpService _svc() => XxlJobExpService(baseUrl: _urlCtrl.text.trim(), timeout: Duration(seconds: int.tryParse(_timeoutCtrl.text.trim()) ?? 10));

  Future<void> _check() async {
    if (_urlCtrl.text.trim().isEmpty) { _log_('[!] 请输入目标 URL'); return; }
    setState(() => _running = true); _log_('[*] 检测 XXL-JOB 执行器未授权...');
    try { final r = await _svc().check(); _log_(r.vulnerable ? '[+] ${r.vulnName}: ${r.detail}' : '[-] 未检测到或已修复'); }
    catch (e) { _log_('[!] 异常: $e'); }
    finally { if (mounted) setState(() => _running = false); }
  }

  Future<void> _exec() async {
    if (_urlCtrl.text.trim().isEmpty) { _log_('[!] 请输入目标 URL'); return; }
    final cmd = _cmdCtrl.text.trim().isEmpty ? 'id' : _cmdCtrl.text.trim();
    setState(() => _running = true); _log_('[*] 提交 GLUE_SHELL 命令: $cmd');
    try {
      final out = await _svc().execRce(cmd);
      _log_(out != null && out.isNotEmpty ? '[+] 响应:\n$out' : '[-] 无响应');
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
      vTf(_urlCtrl, '执行器 URL', 'http://target.com:9999/'),
      const SizedBox(height: 8),
      vTf(_timeoutCtrl, '超时(s)', '10', type: TextInputType.number),
      const SizedBox(height: 8),
      vBtn('检测未授权', _running ? null : _check),
      const SizedBox(height: 16),
      vSecTitle('命令执行（无回显，结合 OOB 验证）'),
      vTf(_cmdCtrl, '命令', 'id'),
      const SizedBox(height: 8),
      vBtn('提交命令', _running ? null : _exec),
    ])),
  );
}
