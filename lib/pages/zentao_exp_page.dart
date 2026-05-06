import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, Clipboard, ClipboardData;

import '../app/constants.dart';
import '../database/database_helper.dart';
import '../exp/zentao/zentao_exp_service.dart';
import '../models/project.dart';
import '../models/webshell.dart';
import '../theme/app_theme.dart';
import 'webshell_interactive_page.dart';

/// 禅道 Repo RCE + 冰蝎 WebShell 写入页面
class ZentaoExpPage extends StatelessWidget {
  const ZentaoExpPage({super.key});

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
            const Icon(Icons.storage, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              'Zentao CVE-2024-24216 · GetShell',
              style: AppTextStyles.heading(size: 14, color: AppColors.primary),
            ),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.bgCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppColors.primary.withValues(alpha: 0.2),
                          AppColors.primary.withValues(alpha: 0.08),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.4),
                        width: 1,
                      ),
                    ),
                    child: const Icon(Icons.storage, color: AppColors.primary, size: 22),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Zentao CVE-2024-24216 · GetShell',
                          style: AppTextStyles.heading(
                            size: 14,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '利用禅道 Repo 配置写入冰蝎 WebShell，一键 GetShell',
                          style: AppTextStyles.caption(
                            size: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Expanded(child: _ZentaoExpCard()),
          ],
        ),
      ),
    );
  }
}

class _ZentaoExpCard extends StatefulWidget {
  const _ZentaoExpCard();

  @override
  State<_ZentaoExpCard> createState() => _ZentaoExpCardState();
}

class _ZentaoExpCardState extends State<_ZentaoExpCard> {
  final _urlController = TextEditingController();
  final _timeoutController = TextEditingController(text: '10');
  final _passwordController = TextEditingController(
    text: AppConstants.defaultShellPassword,
  );
  final _logScrollController = ScrollController();

  String _log = '';
  bool _running = false;

  void _appendLog(String line) {
    setState(() {
      final existing = _log.isEmpty ? <String>[] : _log.split('\n');
      existing.add(line);
      const maxLines = 400;
      final trimmed = existing.length > maxLines
          ? existing.sublist(existing.length - maxLines)
          : existing;
      _log = trimmed.join('\n');
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleGetShell() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      _appendLog('[!] 请输入禅道根路径，如 http://localhost:8080');
      return;
    }
    setState(() => _running = true);
    _appendLog('[*] 尝试利用禅道 Repo 配置写入冰蝎 WebShell...');
    try {
      final password = _passwordController.text.trim().isEmpty
          ? AppConstants.defaultShellPassword
          : _passwordController.text.trim();
      var shellContent = await rootBundle
          .loadString('assets/defaults/payloads/webshell/php_behinder.php');
      final key = md5.convert(utf8.encode(password)).toString().substring(0, 16);
      shellContent = shellContent.replaceFirst(RegExp(r'\$key="[0-9a-f]{16}"'), '\$key="$key"');
      final svc = ZentaoExpService(
        url: url,
        timeout: Duration(
          seconds: int.tryParse(_timeoutController.text.trim()) ??
              AppConstants.defaultHttpTimeoutSeconds,
        ),
      );
      String? shellUrl;
      shellUrl = await svc.getShell(
        shellContent: shellContent,
        onLog: _appendLog,
      );
      if (shellUrl != null) {
        _appendLog('[+] GetShell 成功: $shellUrl (Pass: $password)');
        if (mounted) await _openWebshellFromResult(context, shellUrl, password);
      } else {
        _appendLog('[-] GetShell 失败，请检查目标版本与访问路径');
      }
    } catch (e) {
      _appendLog('[!] 异常: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _openWebshellFromResult(
      BuildContext context, String shellUrl, String password) async {
    final now = DateTime.now();
    Webshell ws = Webshell(
      id: 0,
      projectId: 0,
      name: 'Zentao Repo WebShell',
      url: shellUrl,
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
      Project? project = await _showProjectPicker(context, db);
      if (project != null) {
        ws = await db.createWebshell(
          project.id,
          name: 'Zentao Repo WebShell',
          url: shellUrl,
          password: password,
          method: 'POST',
          type: 'php',
          connectorType: 'php_behinder',
        );
      }
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WebshellInteractivePage(webshell: ws),
      ),
    );
  }

  Future<Project?> _showProjectPicker(
      BuildContext context, DatabaseHelper db) async {
    final projects = await db.getAllProjects();
    if (projects.isEmpty) {
      return _showCreateProjectDialog(context, db);
    }
    return showDialog<Project>(
      context: context,
      builder: (ctx) => _ProjectPickerDialog(projects: projects),
    );
  }

  Future<Project?> _showCreateProjectDialog(
      BuildContext context, DatabaseHelper db) async {
    final nameController = TextEditingController();
    final domainController = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: Text('暂无项目',
            style: AppTextStyles.heading(color: AppColors.primary)),
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
                controller: nameController,
                autofocus: true,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  labelText: '项目名称',
                  hintText: '例如：禅道测试环境',
                  hintStyle: AppTextStyles.caption(
                      size: 11, color: AppColors.textMuted),
                  labelStyle: const TextStyle(color: AppColors.textSecondary),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.5)),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.primary),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: domainController,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  labelText: '域名或ID *',
                  hintText: '例如：zentaopms',
                  hintStyle: AppTextStyles.caption(
                      size: 11, color: AppColors.textMuted),
                  labelStyle: const TextStyle(color: AppColors.textSecondary),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.5)),
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
            child: Text('取消',
                style: AppTextStyles.body(color: AppColors.textSecondary)),
          ),
          FilledButton(
            onPressed: () {
              if (nameController.text.trim().isEmpty ||
                  domainController.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            style:
                FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: Text('创建',
                style: AppTextStyles.body(color: AppColors.bgDark)),
          ),
        ],
      ),
    );

    if (ok == true &&
        nameController.text.trim().isNotEmpty &&
        domainController.text.trim().isNotEmpty) {
      return db.createProject(
        nameController.text.trim(),
        domain: domainController.text.trim(),
      );
    }
    return null;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _timeoutController.dispose();
    _passwordController.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  Color _logLineColor(String line) {
    if (line.startsWith('[+]')) return AppColors.primary;
    if (line.startsWith('[!]')) return AppColors.red;
    if (line.startsWith('[-]')) return AppColors.textMuted;
    if (line.startsWith('[*]')) return AppColors.cyan;
    if (line.startsWith('[i]')) return AppColors.cyan.withValues(alpha: 0.9);
    return AppColors.textSecondary;
  }

  TextSpan _buildLogRichText(String log) {
    if (log.isEmpty) {
      return TextSpan(text: '> 等待操作', style: TextStyle(color: AppColors.textMuted, fontFamily: 'Monaco'));
    }
    final lines = log.split('\n');
    final spans = <TextSpan>[];
    final baseStyle = AppTextStyles.terminal(size: 12, color: AppColors.textSecondary);
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final color = _logLineColor(line);
      spans.add(TextSpan(
        text: line + (i < lines.length - 1 ? '\n' : ''),
        style: baseStyle.copyWith(color: color, fontWeight: line.startsWith('[+]') || line.startsWith('[!]') ? FontWeight.w600 : null),
      ));
    }
    return TextSpan(children: spans);
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.storage,
                    color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                'Zentao CVE-2024-24216 · GetShell',
                style: AppTextStyles.heading(
                    size: 14, color: AppColors.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Flexible(
                  flex: 1,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _sectionTitle('目标配置'),
                        TextField(
                          controller: _urlController,
                          style: AppTextStyles.body(
                              size: 12, color: AppColors.textPrimary),
                          decoration: _inputDecoration(
                            '禅道根路径',
                            'http://localhost:8080',
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _timeoutController,
                          style: AppTextStyles.body(
                              size: 12, color: AppColors.textPrimary),
                          decoration:
                              _inputDecoration('超时(s)', '10'),
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _passwordController,
                          style: AppTextStyles.body(
                              size: 12, color: AppColors.textPrimary),
                          decoration:
                              _inputDecoration(
                                'GetShell 密码',
                                AppConstants.defaultShellPassword,
                              ),
                        ),
                        const SizedBox(height: 16),
                        _sectionTitle('利用动作'),
                        _actionBtn('GetShell', _handleGetShell),
                      ],
                    ),
                  ),
                ),
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
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _running
                                    ? AppColors.primary
                                    : AppColors.textMuted,
                              ),
                            ),
                            Text(
                              _running ? '运行中' : '空闲',
                              style: AppTextStyles.caption(
                                size: 11,
                                color: _running
                                    ? AppColors.primary
                                    : AppColors.textSecondary,
                              ),
                            ),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: _log.isEmpty ? null : () async {
                                await Clipboard.setData(ClipboardData(text: _log));
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('已复制到剪贴板'), duration: Duration(seconds: 1)),
                                );
                              },
                              icon: const Icon(Icons.copy, size: 14),
                              label: const Text('复制'),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.textSecondary,
                                textStyle: const TextStyle(fontSize: 11),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _log.isEmpty ? null : () => setState(() => _log = ''),
                              icon: const Icon(Icons.clear_all, size: 14),
                              label: const Text('清空'),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.textSecondary,
                                textStyle: const TextStyle(fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                        const Divider(
                            height: 1, color: AppColors.border),
                        const SizedBox(height: 4),
                        Expanded(
                          child: SingleChildScrollView(
                            controller: _logScrollController,
                            child: SelectableText.rich(
                              _buildLogRichText(_log),
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
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(title,
              style: AppTextStyles.heading(
                  size: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String label, String hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle:
          AppTextStyles.caption(size: 11, color: AppColors.textMuted),
      floatingLabelBehavior: FloatingLabelBehavior.always,
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide:
            BorderSide(color: AppColors.primary.withValues(alpha: 0.6)),
      ),
    );
  }

  Widget _actionBtn(String label, VoidCallback onPressed) {
    return SizedBox(
      height: 32,
      child: ElevatedButton(
        onPressed: _running ? null : onPressed,
        style: ElevatedButton.styleFrom(
          textStyle: const TextStyle(fontSize: 11),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        child: Text(label),
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
      backgroundColor: AppColors.bgCard,
      title:
          Text('选择项目', style: AppTextStyles.heading(color: AppColors.primary)),
      content: SizedBox(
        width: 360,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: projects.length,
          itemBuilder: (ctx, i) {
            final p = projects[i];
            return ListTile(
              leading: const Icon(Icons.folder_outlined,
                  color: AppColors.primary, size: 20),
              title: Text(p.name,
                  style: AppTextStyles.body(
                      size: 13, color: AppColors.textPrimary)),
              subtitle: Text(p.domain,
                  style: AppTextStyles.caption(
                      size: 11, color: AppColors.textMuted)),
              onTap: () => Navigator.pop(context, p),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('取消',
              style: AppTextStyles.body(color: AppColors.textSecondary)),
        ),
      ],
    );
  }
}

