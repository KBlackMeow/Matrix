import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../exp/thinkphp/thinkphp_exp_service.dart';
import '../theme/app_theme.dart';

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
              'ThinkPHP 漏洞利用',
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
                          'ThinkPHP 3.x / 5.x / 6.x 漏洞检测与 RCE 利用',
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
  final _logScrollController = ScrollController();

  String _log = '';
  bool _running = false;
  /// 检测到的所有 RCE 漏洞（用于下拉选择）
  List<ThinkphpVulnType> _detectedRceVulns = [];
  /// 当前选中的 RCE 漏洞（用于执行命令 / GetShell）
  ThinkphpVulnType? _selectedRceVuln;
  ThinkphpVulnType _selectedCheckType = ThinkphpVulnType.tp5022_5129;

  void _appendLog(String line) {
    setState(() {
      final existing = _log.isEmpty ? <String>[] : _log.split('\n');
      existing.add(line);
      const maxLines = 500;
      final trimmed =
          existing.length > maxLines ? existing.sublist(existing.length - maxLines) : existing;
      _log = trimmed.join('\n');
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
        timeout: Duration(seconds: int.tryParse(_timeoutController.text.trim()) ?? 10),
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
        timeout: Duration(seconds: int.tryParse(_timeoutController.text.trim()) ?? 10),
      );
      const rceTypes = [
        ThinkphpVulnType.tp50,
        ThinkphpVulnType.tp5010,
        ThinkphpVulnType.tp5022_5129,
        ThinkphpVulnType.tp5023,
        ThinkphpVulnType.tp5024_5130,
        ThinkphpVulnType.tp3,
        ThinkphpVulnType.tp3LogRce,
      ];
      final results = await svc.checkAllRce();
      final found = <ThinkphpVulnType>[];
      for (var i = 0; i < results.length; i++) {
        final r = results[i];
        if (r.vulnerable) {
          _appendLog('[+] ${r.vulnName}');
          _appendLog('[i] ${r.detail}');
          found.add(rceTypes[i]);
        } else {
          _appendLog('[-] ${r.vulnName}');
        }
      }
      setState(() {
        _detectedRceVulns = found;
        _selectedRceVuln = found.isNotEmpty ? found.first : null;
      });
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
        timeout: Duration(seconds: int.tryParse(_timeoutController.text.trim()) ?? 10),
      );
      final results = await svc.checkAll();
      final found = <ThinkphpVulnType>[];
      for (var i = 0; i < results.length; i++) {
        final r = results[i];
        if (r.vulnerable) {
          _appendLog('[+] ${r.vulnName}');
          _appendLog('[i] ${r.detail}');
          final t = ThinkphpVulnType.values[i];
          if (t.supportsRce) found.add(t);
        } else {
          _appendLog('[-] ${r.vulnName}');
        }
      }
      setState(() {
        _detectedRceVulns = found;
        _selectedRceVuln = found.isNotEmpty ? found.first : null;
      });
      if (found.isEmpty) _appendLog('[!] 未发现 RCE 漏洞');
    } catch (e) {
      _appendLog('[!] 异常: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _handleExeRce() async {
    final url = _urlController.text.trim();
    final cmd = _cmdController.text.trim().isEmpty ? 'id' : _cmdController.text.trim();
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
    _appendLog('[*] 执行命令 ($vuln.label): $cmd');
    try {
      final svc = ThinkphpExpService(
        url: url,
        timeout: Duration(seconds: int.tryParse(_timeoutController.text.trim()) ?? 10),
      );
      final out = await svc.exeRce(vuln, cmd);
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
      final shellContent = await rootBundle.loadString('assets/defaults/payloads/php_behinder.php');
      final svc = ThinkphpExpService(
        url: url,
        timeout: Duration(seconds: int.tryParse(_timeoutController.text.trim()) ?? 10),
      );
      final shellUrl = await svc.getShell(vuln, shellContent);
      if (shellUrl != null) {
        _appendLog('[+] GetShell 成功: $shellUrl');
      } else {
        _appendLog('[-] GetShell 失败');
      }
    } catch (e) {
      _appendLog('[!] 异常: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _cmdController.dispose();
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
                          decoration: _inputDecoration('目标 URL', 'https://target.com/'),
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
                                dropdownColor: AppColors.bgElevated,
                                style: AppTextStyles.body(size: 11, color: AppColors.textPrimary),
                                items: ThinkphpVulnType.values
                                    .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
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
                                  dropdownColor: AppColors.bgElevated,
                                  style: AppTextStyles.body(size: 11, color: AppColors.textPrimary),
                                  items: _detectedRceVulns
                                      .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
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
                          decoration: _inputDecoration('命令', 'id'),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _actionBtn(
                              '执行命令',
                              _handleExeRce,
                              enabled: _selectedRceVuln != null,
                            ),
                            const SizedBox(width: 8),
                            _actionBtn(
                              'GetShell',
                              _handleGetShell,
                              enabled: _selectedRceVuln != null,
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
                            child: Text(
                              _log.isEmpty ? '> 等待操作' : _log,
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
}
