import 'priv_esc_vectors.dart';

enum PrivEscRiskLevel { confirmed, needsVerification, informational }

class PrivEscRisk {
  const PrivEscRisk({
    required this.title,
    required this.evidence,
    this.commands = const [],
    this.verificationCommands = const [],
    this.level = PrivEscRiskLevel.confirmed,
    this.verified,
    this.hasDirectPrivilegeProof = false,
    this.checkCommand,
    this.rawOutput,
    this.candidate,
  });

  final String title;
  final String evidence;

  /// Commands shown to the user. The UI treats comment-only rows as guidance.
  final List<String> commands;
  final List<String> verificationCommands;
  final PrivEscRiskLevel level;
  final bool? verified;

  /// True only when the collected output itself proves an immediately usable
  /// privileged execution path, without assuming versions or side conditions.
  final bool hasDirectPrivilegeProof;
  final String? checkCommand;
  final String? rawOutput;

  /// The exploitable instance backing this risk; non-null when a chain can be
  /// built (a landing method + params) and executed.
  final PrivEscCandidate? candidate;

  bool get isConfirmed => verified ?? level == PrivEscRiskLevel.confirmed;
}

class PrivEscRiskGroup {
  const PrivEscRiskGroup(this.level, this.risks);

  final PrivEscRiskLevel level;
  final List<PrivEscRisk> risks;
}

List<PrivEscRiskGroup> groupPrivEscRisks(Iterable<PrivEscRisk> risks) {
  final allRisks = risks.toList(growable: false);
  return [
    for (final level in PrivEscRiskLevel.values)
      if (allRisks.where((risk) => risk.level == level).isNotEmpty)
        PrivEscRiskGroup(
          level,
          allRisks.where((risk) => risk.level == level).toList(growable: false),
        ),
  ];
}

List<PrivEscRisk> confirmedPrivEscRisks(Iterable<PrivEscRisk> risks) => risks
    .where((risk) => risk.hasDirectPrivilegeProof)
    .toList(growable: false);
