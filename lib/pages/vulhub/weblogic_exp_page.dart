import 'package:flutter/material.dart';

import '../../app/constants.dart';
import '../../exp/vulhub/misc_http_exp_service.dart';
import '../../theme/app_theme.dart';
import '_vulhub_page_helpers.dart';
import 'base_vulhub_exp_page.dart';

class WebLogicExpPage extends BaseVulhubExpPage {
  const WebLogicExpPage({super.key});

  @override
  State<WebLogicExpPage> createState() => _WebLogicPageState();
}

class _WebLogicPageState extends BaseVulhubExpPageState<WebLogicExpPage> {
  @override
  IconData get pageIcon => Icons.dns;

  @override
  String get appBarTitle =>
      'Oracle WebLogic CVE-2017-10271 / CVE-2020-14882 RCE';

  @override
  String get cardTitle => 'Oracle WebLogic RCE';

  @override
  String get cardSubtitle =>
      'XMLDecoder 反序列化 + 控制台未授权 RCE';

  final _urlCtrl      = TextEditingController();
  final _cmdCtrl      = TextEditingController(text: 'id');
  final _timeoutCtrl  = TextEditingController();
  // 0=CVE-2017-10271  1=CVE-2020-14882
  int _tab = 0;

  WebLogicExpService _svc() => WebLogicExpService(
        baseUrl: _urlCtrl.text.trim(),
        timeout: Duration(seconds: timeoutFrom(_timeoutCtrl)),
      );

  Future<void> _check() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog('[!] 请输入目标 URL');
      return;
    }
    setState(() => running = true);
    if (_tab == 0) {
      appendLog('[*] 检测 CVE-2017-10271 XMLDecoder 端点...');
      try {
        final r = await _svc().checkCve201710271();
        appendLog(r.vulnerable ? '[+] ${r.vulnName}: ${r.detail}' : '[-] 未检测到');
      } catch (e) {
        appendLog('[!] 异常: $e');
      }
    } else if (_tab == 1) {
      appendLog('[*] 检测 CVE-2020-14882 控制台路径绕过...');
      try {
        final r = await _svc().checkCve202014882();
        appendLog(r.vulnerable ? '[+] ${r.vulnName}: ${r.detail}' : '[-] 未检测到');
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
      appendLog('[*] CVE-2017-10271 XMLDecoder RCE: $cmd');
      try {
        final out = await _svc().execRceCve201710271(cmd);
        appendLog(out != null ? '[+] 响应:\n$out' : '[-] 无响应');
      } catch (e) {
        appendLog('[!] 异常: $e');
      }
    } else if (_tab == 1) {
      appendLog('[*] CVE-2020-14882 控制台 RCE: $cmd');
      try {
        final out = await _svc().execRceCve202014882(cmd);
        appendLog(out != null ? '[+] 响应:\n$out' : '[-] 无响应');
      } catch (e) {
        appendLog('[!] 异常: $e');
      }
    }
    if (mounted) setState(() => running = false);
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
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
          vTf(_urlCtrl, '目标 URL', 'http://localhost:7001'),
          const SizedBox(height: 8),
          vTf(
            _timeoutCtrl,
            '超时(s)',
            '${AppConstants.defaultHttpTimeoutSeconds}',
            type: TextInputType.number,
          ),
          const SizedBox(height: 16),
          vSecTitle('CVE 选择'),
          Row(
            children: [
              _tabBtn('CVE-2017-10271 (WebLogic < 10.3.6)', 0),
              const SizedBox(width: 6),
              _tabBtn('CVE-2020-14882 (WebLogic 12.2.1.3)', 1),
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
              switch (_tab) {
                0 => 'XMLDecoder 反序列化 → /wls-wsat/CoordinatorPortType\n无直接回显，需结合 OOB/写文件验证',
                _ => '控制台路径绕过 → /console/css/%252e%252e%252fconsole.portal\n无直接回显',
              },
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
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: _tab == idx
                ? AppColors.primary.withValues(alpha: 0.2)
                : AppColors.bgDark,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _tab == idx
                  ? AppColors.primary.withValues(alpha: 0.6)
                  : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: AppTextStyles.caption(
              size: 10,
              color: _tab == idx ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
        ),
      );
}
