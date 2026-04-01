import 'package:flutter/material.dart';

import '../../app/constants.dart';
import '../../exp/vulhub/misc_http_exp_service.dart';
import '_vulhub_page_helpers.dart';
import 'base_vulhub_exp_page.dart';

class HttpdExpPage extends BaseVulhubExpPage {
  const HttpdExpPage({super.key});

  @override
  State<HttpdExpPage> createState() => _HttpdPageState();
}

class _HttpdPageState extends BaseVulhubExpPageState<HttpdExpPage> {
  @override
  IconData get pageIcon => Icons.http;

  @override
  String get appBarTitle => 'Apache HTTP Server CVE-2021-41773 路径穿越 + CGI RCE';

  @override
  String get cardTitle => 'Apache HTTPd CVE-2021-41773';

  @override
  String get cardSubtitle => '路径规范化缺陷 — 文件读取 + CGI 命令执行 (Apache 2.4.49)';

  final _urlCtrl = TextEditingController();
  final _cmdCtrl = TextEditingController(text: 'id');
  final _fileCtrl = TextEditingController(text: '/etc/passwd');
  final _timeoutCtrl = TextEditingController();

  ApacheHttpdExpService _svc() => ApacheHttpdExpService(
        baseUrl: _urlCtrl.text.trim(),
        timeout: Duration(seconds: timeoutFrom(_timeoutCtrl)),
      );

  Future<void> _check() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog('[!] 请输入目标 URL');
      return;
    }
    setState(() => running = true);
    appendLog('[*] 检测 CVE-2021-41773 路径穿越...');
    try {
      final r = await _svc().check();
      appendLog(r.vulnerable ? '[+] ${r.vulnName}: ${r.detail}' : '[-] 未检测到漏洞');
    } catch (e) {
      appendLog('[!] 异常: $e');
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  Future<void> _readFile() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog('[!] 请输入目标 URL');
      return;
    }
    final path = _fileCtrl.text.trim().isEmpty ? '/etc/passwd' : _fileCtrl.text.trim();
    setState(() => running = true);
    appendLog('[*] 读取文件: $path');
    try {
      final out = await _svc().readFile(path);
      appendLog(out != null && out.isNotEmpty ? '[+] 文件内容:\n$out' : '[-] 读取失败或文件不存在');
    } catch (e) {
      appendLog('[!] 异常: $e');
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  Future<void> _execRce() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog('[!] 请输入目标 URL');
      return;
    }
    final cmd = _cmdCtrl.text.trim().isEmpty ? 'id' : _cmdCtrl.text.trim();
    setState(() => running = true);
    appendLog('[*] CGI RCE 执行: $cmd');
    try {
      final out = await _svc().execRce(cmd);
      appendLog(out != null && out.isNotEmpty ? '[+] 输出:\n$out' : '[-] 无输出（CGI 可能未启用）');
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
    _fileCtrl.dispose();
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
          vTf(
            _timeoutCtrl,
            '超时(s)',
            '${AppConstants.defaultHttpTimeoutSeconds}',
            type: TextInputType.number,
          ),
          const SizedBox(height: 16),
          vSecTitle('路径穿越文件读取'),
          vTf(_fileCtrl, '文件路径', '/etc/passwd'),
          const SizedBox(height: 8),
          Row(
            children: [
              vBtn('检测漏洞', running ? null : _check),
              const SizedBox(width: 8),
              vBtn('读取文件', running ? null : _readFile),
            ],
          ),
          const SizedBox(height: 16),
          vSecTitle('CGI RCE（需 mod_cgi 启用）'),
          vTf(_cmdCtrl, '命令', 'id'),
          const SizedBox(height: 8),
          vBtn('执行命令', running ? null : _execRce),
        ],
      ),
    );
  }
}
