import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../exp/vulhub/spring_exp_service.dart';
import '../../theme/app_theme.dart';

class SpringExpPage extends StatelessWidget {
  const SpringExpPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgElevated,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).pop()),
        title: Row(children: [
          const Icon(Icons.local_florist, color: AppColors.primary),
          const SizedBox(width: 8),
          Text('Spring Framework RCE (CVE-2022-22963/22965/2018-1273/2017-8046/2016-4977)',
              style: AppTextStyles.heading(size: 14, color: AppColors.primary)),
        ]),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _infoCard(Icons.local_florist, 'Spring Framework RCE',
                'Spring4Shell / Spring Cloud Function / Spring Data SpEL 注入系列'),
            const SizedBox(height: 16),
            const Expanded(child: _SpringCard()),
          ],
        ),
      ),
    );
  }
}

class _SpringCard extends StatefulWidget {
  const _SpringCard();
  @override
  State<_SpringCard> createState() => _SpringCardState();
}

class _SpringCardState extends State<_SpringCard> {
  final _urlCtrl = TextEditingController();
  final _cmdCtrl = TextEditingController(text: 'id');
  final _timeoutCtrl = TextEditingController();
  final _logScroll = ScrollController();

  SpringVulnType _selected = SpringVulnType.springCloudFunction;
  String _log = '';
  bool _running = false;

  void _appendLog(String line) {
    setState(() {
      final lines = _log.isEmpty ? <String>[] : _log.split('\n');
      lines.add(line);
      if (lines.length > 500) lines.removeRange(0, lines.length - 500);
      _log = lines.join('\n');
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients) {
        _logScroll.animateTo(_logScroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100), curve: Curves.easeOut);
      }
    });
  }

  SpringExpService _svc() => SpringExpService(
        url: _urlCtrl.text.trim(),
        timeout: Duration(seconds: int.tryParse(_timeoutCtrl.text.trim()) ?? 10),
      );

  Future<void> _check() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) { _appendLog('[!] 请输入目标 URL'); return; }
    setState(() => _running = true);
    _appendLog('[*] 检测 ${_selected.label}...');
    try {
      final r = await _svc().checkSingle(_selected);
      _appendLog(r.vulnerable ? '[+] ${r.vulnName}: ${r.detail}' : '[-] 未检测到 ${r.vulnName}');
    } catch (e) {
      _appendLog('[!] 异常: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _checkAll() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) { _appendLog('[!] 请输入目标 URL'); return; }
    setState(() => _running = true);
    _appendLog('[*] 批量检测所有 Spring CVE...');
    try {
      final svc = _svc();
      for (final t in SpringVulnType.values) {
        _appendLog('[*] 检测 ${t.label}...');
        final r = await svc.checkSingle(t);
        _appendLog(r.vulnerable ? '[+] ${r.vulnName}: ${r.detail}' : '[-] ${r.vulnName}');
      }
    } catch (e) {
      _appendLog('[!] 异常: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _execRce() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) { _appendLog('[!] 请输入目标 URL'); return; }
    final cmd = _cmdCtrl.text.trim().isEmpty ? 'id' : _cmdCtrl.text.trim();
    setState(() => _running = true);
    _appendLog('[*] 执行命令 (${_selected.label}): $cmd');
    try {
      final out = await _svc().execRce(_selected, cmd);
      if (out != null && out.isNotEmpty) {
        _appendLog('[+] 输出:\n$out');
      } else {
        _appendLog('[-] 无输出（该漏洞可能无直接回显）');
      }
    } catch (e) {
      _appendLog('[!] 异常: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose(); _cmdCtrl.dispose(); _timeoutCtrl.dispose(); _logScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _cardShell(
      running: _running, log: _log, logScroll: _logScroll,
      onClearLog: () => setState(() => _log = ''),
      leftPanel: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _secTitle('目标配置'),
          _tf(_urlCtrl, '目标 URL', 'http://target.com:8080/'),
          const SizedBox(height: 8),
          _tf(_timeoutCtrl, '超时(s)', '10', type: TextInputType.number),
          const SizedBox(height: 16),
          _secTitle('漏洞选择'),
          DropdownButtonFormField<SpringVulnType>(
            initialValue: _selected,
            isExpanded: true,
            dropdownColor: AppColors.bgElevated,
            style: AppTextStyles.body(size: 11, color: AppColors.textPrimary),
            items: SpringVulnType.values
                .map((t) => DropdownMenuItem(value: t, child: Text(t.label, overflow: TextOverflow.ellipsis)))
                .toList(),
            onChanged: _running ? null : (t) => t != null ? setState(() => _selected = t) : null,
            decoration: _inputDec('CVE', ''),
          ),
          const SizedBox(height: 8),
          Row(children: [
            _actionBtn('检测', _check),
            const SizedBox(width: 8),
            _actionBtn('检测全部', _checkAll),
          ]),
          const SizedBox(height: 16),
          _secTitle('命令执行'),
          _tf(_cmdCtrl, '命令', 'id'),
          const SizedBox(height: 8),
          _actionBtn('执行命令', _execRce),
        ]),
      ),
    );
  }
}

// ── helpers ────────────────────────────────────────────────────────────────

Widget _infoCard(IconData icon, String title, String subtitle) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
  decoration: BoxDecoration(
    color: AppColors.bgCard, borderRadius: BorderRadius.circular(10),
    border: Border.all(color: AppColors.border),
    boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 2))],
  ),
  child: Row(children: [
    Container(
      width: 44, height: 44,
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [AppColors.primary.withValues(alpha: 0.2), AppColors.primary.withValues(alpha: 0.08)]),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
      ),
      child: Icon(icon, color: AppColors.primary, size: 22),
    ),
    const SizedBox(width: 16),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: AppTextStyles.heading(size: 14, color: AppColors.textPrimary)),
      const SizedBox(height: 4),
      Text(subtitle, style: AppTextStyles.caption(size: 12, color: AppColors.textSecondary)),
    ])),
  ]),
);

Widget _cardShell({
  required bool running, required String log, required ScrollController logScroll,
  required VoidCallback onClearLog, required Widget leftPanel,
}) {
  Color lineColor(String l) {
    if (l.startsWith('[+]')) return AppColors.primary;
    if (l.startsWith('[!]')) return AppColors.red;
    if (l.startsWith('[-]')) return AppColors.textMuted;
    if (l.startsWith('[*]')) return AppColors.cyan;
    if (l.startsWith('[i]')) return AppColors.cyan.withValues(alpha: 0.9);
    return AppColors.textSecondary;
  }
  TextSpan richLog() {
    if (log.isEmpty) return TextSpan(text: '> 等待操作', style: TextStyle(color: AppColors.textMuted, fontFamily: 'Monaco'));
    final lines = log.split('\n');
    final base = AppTextStyles.terminal(size: 12, color: AppColors.textSecondary);
    return TextSpan(children: [
      for (var i = 0; i < lines.length; i++)
        TextSpan(
          text: lines[i] + (i < lines.length - 1 ? '\n' : ''),
          style: base.copyWith(color: lineColor(lines[i]),
              fontWeight: lines[i].startsWith('[+]') || lines[i].startsWith('[!]') ? FontWeight.w600 : null),
        ),
    ]);
  }
  return Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: AppColors.bgCard, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Flexible(flex: 1, child: leftPanel),
      const SizedBox(width: 16),
      Flexible(
        flex: 1,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.bgDark, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
          child: Builder(builder: (context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(width: 6, height: 6, margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(shape: BoxShape.circle, color: running ? AppColors.primary : AppColors.textMuted)),
              Text(running ? '运行中' : '空闲',
                  style: AppTextStyles.caption(size: 11, color: running ? AppColors.primary : AppColors.textSecondary)),
              const Spacer(),
              TextButton.icon(
                onPressed: log.isEmpty ? null : () async {
                  await Clipboard.setData(ClipboardData(text: log));
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)));
                },
                icon: const Icon(Icons.copy, size: 14), label: const Text('复制'),
                style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary, textStyle: const TextStyle(fontSize: 11)),
              ),
              TextButton.icon(
                onPressed: log.isEmpty ? null : onClearLog,
                icon: const Icon(Icons.clear_all, size: 14), label: const Text('清空'),
                style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary, textStyle: const TextStyle(fontSize: 11)),
              ),
            ]),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 4),
            Expanded(child: SingleChildScrollView(controller: logScroll,
                child: SelectableText.rich(richLog(), style: AppTextStyles.terminal(size: 12, color: AppColors.textMuted)))),
          ])),
        ),
      ),
    ]),
  );
}

Widget _secTitle(String t) => Padding(
  padding: const EdgeInsets.only(bottom: 6),
  child: Row(children: [
    Container(width: 3, height: 14,
        decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 8),
    Text(t, style: AppTextStyles.heading(size: 12, color: AppColors.textSecondary)),
  ]),
);

InputDecoration _inputDec(String label, String hint) => InputDecoration(
  labelText: label, hintText: hint,
  hintStyle: AppTextStyles.caption(size: 11, color: AppColors.textMuted),
  floatingLabelBehavior: FloatingLabelBehavior.always,
  isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.6))),
);

Widget _tf(TextEditingController c, String label, String hint, {TextInputType? type}) =>
    TextField(controller: c, style: AppTextStyles.body(size: 12, color: AppColors.textPrimary),
        keyboardType: type, decoration: _inputDec(label, hint));

Widget _actionBtn(String label, VoidCallback? onPressed) => SizedBox(
  height: 32,
  child: ElevatedButton(
    onPressed: onPressed,
    style: ElevatedButton.styleFrom(textStyle: const TextStyle(fontSize: 11), padding: const EdgeInsets.symmetric(horizontal: 12)),
    child: Text(label),
  ),
);
