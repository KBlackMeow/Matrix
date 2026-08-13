import 'persistence_methods.dart';

/// Parse exploitability tokens from check output.
/// Lines starting with EXPLOIT:OK: → satisfied, EXPLOIT:FAIL: → blocked.
ExploitabilityResult parseExploitability(String raw) {
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
  return ExploitabilityResult(
    level: blocked.isEmpty ? ExploitabilityLevel.ready : ExploitabilityLevel.blocked,
    satisfied: satisfied,
    blocked: blocked,
  );
}

/// Strip EXPLOIT: prefixed lines from raw output before detection parsing.
String stripExploitLines(String raw) {
  return raw
      .split('\n')
      .where((l) => !l.trim().startsWith('EXPLOIT:'))
      .join('\n');
}

/// Dispatch a check output to the per-method detection parser, attaching the
/// parsed exploitability assessment to the result.
DetectionResult parseDetection(String methodId, String raw) {
  if (raw.startsWith('[Error]')) {
    return DetectionResult.error(raw);
  }

  // Parse exploitability from EXPLOIT: prefixed lines
  final exploitability = parseExploitability(raw);

  // Strip exploitability lines before passing to detection parsers
  final detectionRaw = stripExploitLines(raw);

  final result = switch (methodId) {
    'cron_job' => parseCron(detectionRaw),
    'bashrc_backdoor' => parseBashrc(detectionRaw),
    'ssh_authorized_keys' => parseSshKeys(detectionRaw),
    'systemd_service' => parseSystemd(detectionRaw),
    'profile_d' => parseProfileD(detectionRaw),
    'initd_script' => parseInitd(detectionRaw),
    'inetd_backdoor' => parseInetd(detectionRaw),
    'suid_shell' => parseSuid(detectionRaw),
    'root_user' => parseRootUser(detectionRaw),
    'hidden_account' => parseHiddenAccount(detectionRaw),
    _ => DetectionResult(
        verdict: DetectionVerdict.found,
        summary: detectionRaw.length > 120 ? '${detectionRaw.substring(0, 120)}…' : detectionRaw,
        rawOutput: raw,
        confidence: 0.3,
      ),
  };

  // Attach exploitability to the result
  return DetectionResult(
    verdict: result.verdict,
    summary: result.summary,
    rawOutput: raw, // keep full raw output including EXPLOIT lines
    details: result.details,
    confidence: result.confidence,
    exploitability: exploitability,
  );
}

/// Deploy command reported success (`DEPLOY_OK` marker).
bool parseDeploySuccess(String raw) {
  return raw.contains('DEPLOY_OK');
}

/// Verify command confirmed persistence (`VERIFY_OK:` or an `id` uid=0 line).
bool parseVerifySuccess(String raw) {
  return raw.contains('VERIFY_OK') ||
      raw.contains('uid=0(root)') ||
      raw.contains('euid=0(root)');
}
