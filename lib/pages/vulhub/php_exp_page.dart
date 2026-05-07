import 'package:flutter/material.dart';

import '../../app/constants.dart';
import '../../exp/vulhub/misc_http_exp_service.dart';
import '../../theme/app_theme.dart';
import '_vulhub_page_helpers.dart';
import 'base_vulhub_exp_page.dart';

class PhpExpPage extends BaseVulhubExpPage {
  const PhpExpPage({super.key});

  @override
  State<PhpExpPage> createState() => _PhpPageState();
}

class _PhpPageState extends BaseVulhubExpPageState<PhpExpPage> {
  @override
  IconData get pageIcon => Icons.php;

  @override
  String get appBarTitle => 'PHP 8.1.0-dev 后门 / CVE-2012-1823 PHP-CGI RCE';

  @override
  String get cardTitle => 'PHP RCE 系列';

  @override
  String get cardSubtitle => 'PHP 8.1.0-dev User-Agentt 后门 + CVE-2012-1823 PHP-CGI 参数注入';

  final _urlCtrl = TextEditingController();
  final _phpPathCtrl = TextEditingController(text: '/index.php');
  final _cmdCtrl = TextEditingController(text: 'id');
  final _timeoutCtrl = TextEditingController();
  int _tab = 0; // 0 = backdoor, 1 = cgi

  PhpBackdoorExpService _backdoorSvc() => PhpBackdoorExpService(
        baseUrl: _urlCtrl.text.trim(),
        phpPath:
            _phpPathCtrl.text.trim().isEmpty ? '/index.php' : _phpPathCtrl.text.trim(),
        timeout: Duration(seconds: timeoutFrom(_timeoutCtrl)),
      );

  PhpCgiExpService _cgiSvc() => PhpCgiExpService(
        baseUrl: _urlCtrl.text.trim(),
        phpPath:
            _phpPathCtrl.text.trim().isEmpty ? '/index.php' : _phpPathCtrl.text.trim(),
        timeout: Duration(seconds: timeoutFrom(_timeoutCtrl)),
      );

  Future<void> _check() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog('[!] 请输入目标 URL');
      return;
    }
    setState(() => running = true);
    if (_tab == 0) {
      appendLog('[*] 检测 PHP 8.1.0-dev User-Agentt 后门...');
      try {
        final r = await _backdoorSvc().check();
        appendLog(r.vulnerable ? '[+] ${r.vulnName}: ${r.detail}' : '[-] 未检测到后门');
      } catch (e) {
        appendLog('[!] 异常: $e');
      }
    } else {
      appendLog('[*] 检测 CVE-2012-1823 PHP-CGI...');
      try {
        final r = await _cgiSvc().check();
        appendLog(r.vulnerable ? '[+] ${r.vulnName}: ${r.detail}' : '[-] 未检测到 PHP-CGI 漏洞');
      } catch (e) {
        appendLog('[!] 异常: $e');
      }
    }
    if (mounted) setState(() => running = false);
  }

  Future<void> _exec() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog('[!] 请输入目标 URL');
      return;
    }
    final cmd = _cmdCtrl.text.trim().isEmpty ? 'id' : _cmdCtrl.text.trim();
    setState(() => running = true);
    if (_tab == 0) {
      appendLog('[*] PHP 8.1.0-dev 后门 执行: $cmd');
      try {
        final out = await _backdoorSvc().execRce(cmd);
        appendLog(out != null && out.isNotEmpty ? '[+] 输出:\n$out' : '[-] 无输出');
      } catch (e) {
        appendLog('[!] 异常: $e');
      }
    } else {
      appendLog('[*] PHP-CGI 参数注入 执行: $cmd');
      try {
        final out = await _cgiSvc().execRce(cmd);
        appendLog(out != null && out.isNotEmpty ? '[+] 输出:\n$out' : '[-] 无输出');
      } catch (e) {
        appendLog('[!] 异常: $e');
      }
    }
    if (mounted) setState(() => running = false);
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _phpPathCtrl.dispose();
    _cmdCtrl.dispose();
    _timeoutCtrl.dispose();
    super.dispose();
  }

  @override
  Widget buildLeftPanel(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          vSecTitle('目标配置'),
          vTf(_urlCtrl, '目标 URL', 'http://localhost:8080'),
          const SizedBox(height: 8),
          vTf(_phpPathCtrl, 'PHP 文件路径', '/index.php'),
          const SizedBox(height: 8),
          vTf(
            _timeoutCtrl,
            '超时(s)',
            '${AppConstants.defaultHttpTimeoutSeconds}',
            type: TextInputType.number,
          ),
          const SizedBox(height: 16),
          vSecTitle('漏洞类型'),
          Row(
            children: [
              _tabBtn('PHP 8.1.0-dev 后门', 0),
              const SizedBox(width: 8),
              _tabBtn('CVE-2012-1823 (PHP-CGI < 5.3.12 / < 5.4.2)', 1),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.bgDark,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              _tab == 0
                  ? '通过 User-Agentt 头发送 zerodium 触发器执行 PHP 代码\n影响版本: PHP 8.1.0-dev (2021-03-28 供应链攻击)'
                  : '通过 URL 参数 -d allow_url_include=on 注入 PHP 代码\n影响版本: PHP-CGI < 5.3.12 / < 5.4.2',
              style: AppTextStyles.caption(
                size: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 8),
          vBtn('检测漏洞', running ? null : _check),
          const SizedBox(height: 16),
          vSecTitle('命令执行'),
          vTf(_cmdCtrl, '命令', 'id'),
          const SizedBox(height: 8),
          vBtn('执行命令', running ? null : _exec),
        ],
      ),
    );
  }

  Widget _tabBtn(String label, int idx) => GestureDetector(
    onTap: running ? null : () => setState(() => _tab = idx),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _tab == idx ? AppColors.primary.withValues(alpha: 0.2) : AppColors.bgDark,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _tab == idx ? AppColors.primary.withValues(alpha: 0.6) : AppColors.border),
      ),
      child: Text(label, style: AppTextStyles.caption(size: 11, color: _tab == idx ? AppColors.primary : AppColors.textSecondary)),
    ),
  );
}
