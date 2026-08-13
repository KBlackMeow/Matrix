import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/pages/priv_esc_risk.dart';
import 'package:matrix/pages/priv_esc_risk_list.dart';
import 'package:matrix/pages/priv_esc_vectors.dart';

void main() {
  Widget testApp(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('shows every verification command with a copy action', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        const PrivEscRiskList(
          risks: [
            PrivEscRisk(
              title: 'Passwordless sudo',
              evidence: 'NOPASSWD: ALL',
              level: PrivEscRiskLevel.confirmed,
              commands: ['sudo -l'],
            ),
          ],
        ),
      ),
    );

    expect(find.text('已确认风险'), findsOneWidget);
    expect(find.text('sudo -l'), findsOneWidget);
    expect(find.byTooltip('复制验证命令'), findsOneWidget);
  });

  testWidgets('hides details until expanded', (tester) async {
    await tester.pumpWidget(
      testApp(
        const PrivEscRiskList(
          risks: [
            PrivEscRisk(
              title: 'Passwordless sudo',
              evidence: 'NOPASSWD: ALL',
              level: PrivEscRiskLevel.confirmed,
              rawOutput: 'raw sudo output',
            ),
          ],
        ),
      ),
    );

    expect(find.text('raw sudo output'), findsNothing);
    await tester.tap(find.text('查看检测详情'));
    await tester.pumpAndSettle();
    expect(find.text('raw sudo output'), findsOneWidget);
  });

  testWidgets('distinguishes no findings from an incomplete scan', (
    tester,
  ) async {
    await tester.pumpWidget(testApp(const PrivEscRiskList(risks: [])));
    expect(find.text('扫描完成，未发现已识别风险。'), findsOneWidget);

    await tester.pumpWidget(
      testApp(const PrivEscRiskList(risks: [], scanIncomplete: true)),
    );
    expect(find.text('扫描未完整完成，暂未生成可识别风险。'), findsOneWidget);
  });

  testWidgets('shows execute button only for confirmed candidate risks', (
    tester,
  ) async {
    const candidate = PrivEscCandidate(
      vectorId: 'suid',
      binPath: '/usr/bin/find',
      evidence: 'e',
    );
    await tester.pumpWidget(
      testApp(
        const PrivEscRiskList(
          risks: [
            PrivEscRisk(
              title: 'SUID find',
              evidence: '发现 SUID 二进制',
              level: PrivEscRiskLevel.confirmed,
              candidate: candidate,
            ),
          ],
          onExecute: _noopExecute,
        ),
      ),
    );
    expect(find.text('生成提权命令链并执行'), findsOneWidget);
  });

  testWidgets('hides execute button for informational risks', (tester) async {
    await tester.pumpWidget(
      testApp(
        const PrivEscRiskList(
          risks: [
            PrivEscRisk(
              title: 'capabilities lead',
              evidence: 'cap_dac_read_search',
              level: PrivEscRiskLevel.informational,
            ),
          ],
          onExecute: _noopExecute,
        ),
      ),
    );
    expect(find.text('生成提权命令链并执行'), findsNothing);
  });
}

void _noopExecute(PrivEscRisk risk) {}
