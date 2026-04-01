import 'package:flutter/material.dart';
import '../../exp/vulhub/misc_http_exp_service.dart';
import '../../theme/app_theme.dart';
import '_vulhub_page_helpers.dart';

class SolrExpPage extends StatelessWidget {
  const SolrExpPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.bgDark,
        appBar: AppBar(
          backgroundColor: AppColors.bgElevated, elevation: 0,
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).pop()),
          title: Row(children: [
            const Icon(Icons.search, color: AppColors.primary), const SizedBox(width: 8),
            Text('Apache Solr CVE-2017-12629 RunExecutableListener RCE',
                style: AppTextStyles.heading(size: 14, color: AppColors.primary)),
          ]),
        ),
        body: Padding(padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            vulhubInfoCard(Icons.search, 'Apache Solr CVE-2017-12629', '通过 Listener 配置 RunExecutableListener 执行任意命令（< 7.1.0）'),
            const SizedBox(height: 16),
            const Expanded(child: _SolrCard()),
          ]),
        ),
      );
}

class _SolrCard extends StatefulWidget {
  const _SolrCard();
  @override
  State<_SolrCard> createState() => _SolrCardState();
}

class _SolrCardState extends State<_SolrCard> {
  final _urlCtrl = TextEditingController();
  final _coreCtrl = TextEditingController(text: 'demo');
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

  SolrExpService _svc() => SolrExpService(baseUrl: _urlCtrl.text.trim(), coreName: _coreCtrl.text.trim().isEmpty ? 'demo' : _coreCtrl.text.trim(), timeout: Duration(seconds: int.tryParse(_timeoutCtrl.text.trim()) ?? 10));

  Future<void> _check() async {
    if (_urlCtrl.text.trim().isEmpty) { _log_('[!] 请输入目标 URL'); return; }
    setState(() => _running = true); _log_('[*] 检测 Solr 服务...');
    try { final r = await _svc().check(); _log_(r.vulnerable ? '[+] ${r.vulnName}: ${r.detail}' : '[-] Solr 不可访问或未检测到'); }
    catch (e) { _log_('[!] 异常: $e'); }
    finally { if (mounted) setState(() => _running = false); }
  }

  Future<void> _exec() async {
    if (_urlCtrl.text.trim().isEmpty) { _log_('[!] 请输入目标 URL'); return; }
    final cmd = _cmdCtrl.text.trim().isEmpty ? 'id' : _cmdCtrl.text.trim();
    setState(() => _running = true); _log_('[*] 注册 RunExecutableListener + 触发 commit: $cmd');
    try {
      final out = await _svc().execRce(cmd);
      _log_(out != null ? '[+] $out' : '[-] 执行失败');
    } catch (e) { _log_('[!] 异常: $e'); }
    finally { if (mounted) setState(() => _running = false); }
  }

  @override
  void dispose() { _urlCtrl.dispose(); _coreCtrl.dispose(); _cmdCtrl.dispose(); _timeoutCtrl.dispose(); _logScroll.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => VulhubExpCardShell(
    running: _running, log: _log, logScroll: _logScroll,
    onClearLog: () => setState(() => _log = ''),
    leftPanel: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      vSecTitle('目标配置'),
      vTf(_urlCtrl, '目标 URL', 'http://target.com:8983/'),
      const SizedBox(height: 8),
      vTf(_coreCtrl, 'Core 名称', 'demo'),
      const SizedBox(height: 8),
      vTf(_timeoutCtrl, '超时(s)', '10', type: TextInputType.number),
      const SizedBox(height: 8),
      vBtn('检测 Solr', _running ? null : _check),
      const SizedBox(height: 16),
      vSecTitle('命令执行（无回显，结合 OOB 验证）'),
      vTf(_cmdCtrl, '命令', 'id'),
      const SizedBox(height: 8),
      vBtn('注入并触发', _running ? null : _exec),
    ])),
  );
}
