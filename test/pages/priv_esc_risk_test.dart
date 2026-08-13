import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/pages/priv_esc_risk.dart';

void main() {
  test('groups risks by confidence and omits empty groups', () {
    final groups = groupPrivEscRisks(const [
      PrivEscRisk(
        title: 'Kernel version',
        evidence: 'Linux 5.4.0',
        level: PrivEscRiskLevel.needsVerification,
      ),
      PrivEscRisk(
        title: 'Passwordless sudo',
        evidence: 'NOPASSWD: ALL',
        level: PrivEscRiskLevel.confirmed,
      ),
    ]);

    expect(groups.map((group) => group.level), [
      PrivEscRiskLevel.confirmed,
      PrivEscRiskLevel.needsVerification,
    ]);
  });

  test('strict mode only retains risks with direct privilege proof', () {
    final confirmed = confirmedPrivEscRisks(const [
      PrivEscRisk(
        title: 'Sudo without password',
        evidence: 'NOPASSWD: ALL',
        hasDirectPrivilegeProof: true,
      ),
      PrivEscRisk(
        title: 'Writable logrotate rule',
        evidence: 'A rule file is writable',
      ),
    ]);

    expect(confirmed.map((risk) => risk.title), ['Sudo without password']);
  });
}
