import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../app/constants.dart';
import '../../database/database_helper.dart';
import '../../exp/vulhub/struts2_exp_service.dart';
import '../../models/project.dart';
import '../../models/webshell.dart';
import '../../theme/app_theme.dart';
import '../webshell_interactive_page.dart';
import '_vulhub_page_helpers.dart';
import 'base_vulhub_exp_page.dart';
import '../../app/localization.dart';

class Struts2ExpPage extends BaseVulhubExpPage {
  final String? initialTargetUrl;

  const Struts2ExpPage({super.key, this.initialTargetUrl});

  @override
  State<Struts2ExpPage> createState() => _Struts2PageState();
}

class _Struts2PageState extends BaseVulhubExpPageState<Struts2ExpPage> {
  @override
  IconData get pageIcon => Icons.bolt;
  @override
  String get appBarTitle => S.vulhubStruts2Title;
  @override
  String get cardTitle => S.vulhubStruts2CardTitle;
  @override
  String get cardSubtitle => S.vulhubStruts2CardSubtitle;

  late final TextEditingController _urlCtrl;
  final _cmdCtrl = TextEditingController(text: 'id');
  final _timeoutCtrl = TextEditingController();
  final _pathCtrl = TextEditingController(text: 'struts2-showcase');
  final _passwordCtrl = TextEditingController(
    text: AppConstants.defaultShellPassword,
  );

  Struts2VulnType _selected = Struts2VulnType.s2045;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: widget.initialTargetUrl ?? '');
  }

  Struts2ExpService _svc() => Struts2ExpService(
    url: _urlCtrl.text.trim(),
    timeout: Duration(seconds: timeoutFrom(_timeoutCtrl)),
  );

  Future<void> _check() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) {
      appendLog(S.expLogEnterTargetUrl);
      return;
    }
    setState(() => running = true);
    appendLog('[*] 检测 ${_selected.label}...');
    try {
      final r = await _svc().checkSingle(
        _selected,
        path: _pathCtrl.text.trim(),
      );
      if (r.vulnerable) {
        appendLog('[+] 存在漏洞: ${r.vulnName}');
        appendLog('[i] ${r.detail}');
      } else {
        appendLog('[-] 未检测到 ${r.vulnName}');
      }
    } catch (e) {
      appendLog(S.expLogException(e));
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  Future<void> _checkAll() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) {
      appendLog(S.expLogEnterTargetUrl);
      return;
    }
    setState(() => running = true);
    appendLog('[*] 批量检测所有 Struts2 CVE...');
    try {
      final svc = _svc();
      final path = _pathCtrl.text.trim();
      Struts2VulnType? firstHit;
      for (final t in Struts2VulnType.values) {
        appendLog('[*] 检测 ${t.label}...');
        final effectivePath = switch (t) {
          Struts2VulnType.s2053 => 'hello.action',
          _ => path,
        };
        final r = await svc.checkSingle(t, path: effectivePath);
        if (r.vulnerable) {
          appendLog('[+] ${r.vulnName}: ${r.detail}');
          firstHit ??= t;
        } else {
          appendLog('[-] ${r.vulnName}');
        }
      }
      if (firstHit != null && mounted) {
        setState(() {
          _selected = firstHit!;
          _pathCtrl.text = switch (firstHit) {
            Struts2VulnType.s2053 => 'hello.action',
            Struts2VulnType.s2057 => 'struts2-showcase',
            _ => _pathCtrl.text,
          };
        });
        appendLog('[*] 已自动选择首个命中漏洞: ${firstHit.label}');
      }
    } catch (e) {
      appendLog(S.expLogException(e));
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  Future<void> _execRce() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) {
      appendLog(S.expLogEnterTargetUrl);
      return;
    }
    final cmd = _cmdCtrl.text.trim().isEmpty ? 'id' : _cmdCtrl.text.trim();
    setState(() => running = true);
    appendLog('[*] 执行命令 (${_selected.label}): $cmd');
    try {
      final out = await _svc().execRce(
        _selected,
        cmd,
        path: _pathCtrl.text.trim(),
      );
      if (out != null && out.isNotEmpty) {
        appendLog('[+] 输出:\n$out');
      } else {
        appendLog('[-] 无输出或执行失败');
      }
    } catch (e) {
      appendLog(S.expLogException(e));
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  Future<void> _getShell() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) {
      appendLog(S.expLogEnterTargetUrl);
      return;
    }
    setState(() => running = true);
    appendLog('[*] GetShell (${_selected.label})...');
    try {
      final password = _passwordCtrl.text.trim().isEmpty
          ? AppConstants.defaultShellPassword
          : _passwordCtrl.text.trim();
      var shellContent = await rootBundle.loadString(
        'assets/defaults/payloads/webshell/jsp_behinder.jsp',
      );
      final key = md5
          .convert(utf8.encode(password))
          .toString()
          .substring(0, 16);
      shellContent = shellContent.replaceFirst(
        RegExp(r'String k="[0-9a-f]{16}"'),
        'String k="$key"',
      );
      final shellUrl = await _svc().getShell(
        _selected,
        shellContent,
        path: _pathCtrl.text.trim(),
        onLog: appendLog,
      );
      if (shellUrl != null && mounted) {
        await _openWebshellFromResult(shellUrl, password);
      }
    } catch (e) {
      appendLog(S.expLogException(e));
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  Future<void> _openWebshellFromResult(String shellUrl, String password) async {
    final now = DateTime.now();
    Webshell ws = Webshell(
      id: 0,
      projectId: 0,
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
      final project = await _showProjectPicker(db);
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
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => WebshellInteractivePage(webshell: ws)),
    );
  }

  Future<Project?> _showProjectPicker(DatabaseHelper db) async {
    final projects = await db.getAllProjects();
    if (!mounted) return null;
    if (projects.isEmpty) return _showCreateProjectDialog(db);
    return showDialog<Project>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          S.titleSelectProject,
          style: AppTextStyles.heading(color: AppColors.primary),
        ),
        content: SizedBox(
          width: 320,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: projects.length,
            itemBuilder: (_, i) => ListTile(
              title: Text(
                projects[i].name,
                style: AppTextStyles.body(color: AppColors.textPrimary),
              ),
              subtitle: Text(
                projects[i].domain,
                style: AppTextStyles.caption(color: AppColors.textSecondary),
              ),
              onTap: () => Navigator.pop(ctx, projects[i]),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              '跳过',
              style: AppTextStyles.body(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Future<Project?> _showCreateProjectDialog(DatabaseHelper db) async {
    if (!mounted) return null;
    final nameCtrl = TextEditingController();
    final domainCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          '暂无项目',
          style: AppTextStyles.heading(color: AppColors.primary),
        ),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '请先创建一个项目以保存 Webshell',
                style: AppTextStyles.caption(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtrl,
                autofocus: true,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  labelText: '项目名称',
                  hintText: '例如：目标站点',
                  hintStyle: AppTextStyles.caption(
                    size: 11,
                    color: AppColors.textMuted,
                  ),
                  labelStyle: const TextStyle(color: AppColors.textSecondary),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: AppColors.primary.withValues(alpha: 0.5),
                    ),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.primary),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: domainCtrl,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  labelText: '域名或ID *',
                  hintText: '例如：example.com',
                  hintStyle: AppTextStyles.caption(
                    size: 11,
                    color: AppColors.textMuted,
                  ),
                  labelStyle: const TextStyle(color: AppColors.textSecondary),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: AppColors.primary.withValues(alpha: 0.5),
                    ),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.primary),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              '取消',
              style: AppTextStyles.body(color: AppColors.textSecondary),
            ),
          ),
          FilledButton(
            onPressed: () {
              if (nameCtrl.text.trim().isEmpty ||
                  domainCtrl.text.trim().isEmpty) {
                return;
              }
              Navigator.pop(ctx, true);
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: Text(
              '创建',
              style: AppTextStyles.body(color: AppColors.bgDark),
            ),
          ),
        ],
      ),
    );
    if (ok == true &&
        nameCtrl.text.trim().isNotEmpty &&
        domainCtrl.text.trim().isNotEmpty) {
      return db.createProject(
        nameCtrl.text.trim(),
        domain: domainCtrl.text.trim(),
      );
    }
    return null;
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _cmdCtrl.dispose();
    _timeoutCtrl.dispose();
    _pathCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget buildLeftPanel(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          vSecTitle(S.sectionTargetConfig),
          vTf(_urlCtrl, S.fieldTargetUrl, 'http://localhost:8080'),
          const SizedBox(height: 8),
          vTf(_timeoutCtrl, S.fieldTimeout, '10', type: TextInputType.number),
          const SizedBox(height: 8),
          vTf(_pathCtrl, '路径 (005/007/052/053/057)', 'struts2-showcase'),
          const SizedBox(height: 16),
          vSecTitle(S.sectionVulnSelect),
          DropdownButtonFormField<Struts2VulnType>(
            initialValue: _selected,
            isExpanded: true,
            dropdownColor: AppColors.bgElevated,
            style: AppTextStyles.body(size: 11, color: AppColors.textPrimary),
            items: Struts2VulnType.values
                .map(
                  (t) => DropdownMenuItem(
                    value: t,
                    child: Text(t.label, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: running
                ? null
                : (t) {
                    if (t == null) return;
                    setState(() {
                      _selected = t;
                      _pathCtrl.text = switch (t) {
                        Struts2VulnType.s2053 => 'hello.action',
                        Struts2VulnType.s2057 => 'struts2-showcase',
                        _ => _pathCtrl.text,
                      };
                    });
                  },
            decoration: vInputDec('CVE', ''),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              vBtn('检测', running ? null : _check),
              const SizedBox(width: 8),
              vBtn('检测全部', running ? null : _checkAll),
            ],
          ),
          const SizedBox(height: 16),
          vSecTitle(S.sectionCmdExec),
          vTf(_cmdCtrl, S.fieldCommand, 'id'),
          const SizedBox(height: 8),
          vBtn(S.btnExecCmd, running ? null : _execRce),
          const SizedBox(height: 16),
          vSecTitle(S.sectionGetShell),
          vTf(_passwordCtrl, '冰蝎密码', 'mAtrix_911'),
          const SizedBox(height: 8),
          vBtn(S.btnGetShell, running ? null : _getShell),
        ],
      ),
    );
  }
}
