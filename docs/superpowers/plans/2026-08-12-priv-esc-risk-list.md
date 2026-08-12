# Privilege-Escalation Risk List Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the cluttered privilege-escalation checklist UI with a concise, evidence-led risk list containing copyable verification commands.

**Architecture:** Move the presentation-neutral finding model and result classification out of `PrivEscTab`, while preserving the existing scan command inventory and parsing rules. `PrivEscTab` owns an atomic scan session and renders a compact scan bar plus a dedicated risk-list widget; raw scan output is available only as an expandable per-risk detail.

**Tech Stack:** Flutter, Dart 3.11, Material 3 widgets, `flutter_test`.

## Global Constraints

- Preserve every existing scan item, command, and parser, including the current uncommitted additions in `lib/pages/priv_esc_tab.dart`.
- Show only verified, non-destructive verification commands in the default card command area; do not expose exploitation commands from this UI.
- Group results in exact order: confirmed, needs verification, informational; omit empty groups.
- A re-scan must not replace visible findings until its complete result set has been analysed.
- Do not add runtime dependencies.

---

### Task 1: Extract and classify risk findings

**Files:**

- Create: `lib/pages/priv_esc_risk_analysis.dart`
- Create: `test/pages/priv_esc_risk_analysis_test.dart`
- Modify: `lib/pages/priv_esc_tab.dart:6-767`

**Interfaces:**

- Consumes: `Map<String, String?>` keyed as `<group>/<item>` and existing scan group/item definitions.
- Produces: `PrivEscRisk`, `PrivEscRiskLevel`, and `analyzePrivEscResults(Map<String, String?> results)`.
- `PrivEscRisk` fields: `title`, `evidence`, `level`, `verificationCommands`, `checkCommand`, and `rawOutput`.

- [ ] **Step 1: Write the failing analysis tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/pages/priv_esc_risk_analysis.dart';

void main() {
  test('classifies passwordless sudo as a confirmed risk with a verification command', () {
    final risks = analyzePrivEscResults({
      'current_priv/sudo': 'User test may run the following commands:\n    (ALL) NOPASSWD: ALL',
    });

    expect(risks.single.level, PrivEscRiskLevel.confirmed);
    expect(risks.single.verificationCommands, ['sudo -l']);
  });

  test('classifies a kernel version as a risk requiring verification', () {
    final risks = analyzePrivEscResults({'sys_info/kernel': 'Linux host 5.4.0 x86_64'});

    expect(risks.single.level, PrivEscRiskLevel.needsVerification);
    expect(risks.single.verificationCommands, ['uname -a']);
  });

  test('groups risks by confidence without emitting empty groups', () {
    final groups = groupPrivEscRisks([
      const PrivEscRisk(title: 'clue', evidence: '', level: PrivEscRiskLevel.informational),
      const PrivEscRisk(title: 'confirmed', evidence: '', level: PrivEscRiskLevel.confirmed),
    ]);

    expect(groups.map((group) => group.level), [
      PrivEscRiskLevel.confirmed,
      PrivEscRiskLevel.informational,
    ]);
  });
}
```

- [ ] **Step 2: Run the new tests and verify the expected red failure**

Run: `flutter test test/pages/priv_esc_risk_analysis_test.dart`

Expected: FAIL because `priv_esc_risk_analysis.dart` and its public API do not yet exist.

- [ ] **Step 3: Add the minimal public risk model and grouping function**

```dart
enum PrivEscRiskLevel { confirmed, needsVerification, informational }

class PrivEscRisk {
  const PrivEscRisk({
    required this.title,
    required this.evidence,
    required this.level,
    this.verificationCommands = const [],
    this.checkCommand,
    this.rawOutput,
  });

  final String title;
  final String evidence;
  final PrivEscRiskLevel level;
  final List<String> verificationCommands;
  final String? checkCommand;
  final String? rawOutput;
}

List<PrivEscRiskGroup> groupPrivEscRisks(Iterable<PrivEscRisk> risks) => [
  for (final level in PrivEscRiskLevel.values)
    if (risks.where((risk) => risk.level == level).isNotEmpty)
      PrivEscRiskGroup(level, risks.where((risk) => risk.level == level).toList()),
];
```

Port each existing `_analyzeResults` condition into `analyzePrivEscResults`, retaining its detection predicate and evidence extraction. Replace displayed action payloads with the scan item's safe verification command; preserve the original matching output in `rawOutput` and its source command in `checkCommand`.

- [ ] **Step 4: Run the analysis tests and verify green**

Run: `flutter test test/pages/priv_esc_risk_analysis_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit the focused extraction**

```bash
git add lib/pages/priv_esc_risk_analysis.dart test/pages/priv_esc_risk_analysis_test.dart lib/pages/priv_esc_tab.dart
git commit -m "refactor: extract privilege escalation risk analysis"
```

### Task 2: Build the compact risk-list presentation

**Files:**

- Create: `lib/pages/priv_esc_risk_list.dart`
- Create: `test/pages/priv_esc_risk_list_test.dart`
- Modify: `lib/pages/priv_esc_tab.dart:790-1280`

**Interfaces:**

- Consumes: `List<PrivEscRisk> risks`, `bool scanIncomplete`, `VoidCallback onCopy(String)`, and a `Map<String, String>` of check errors.
- Produces: `PrivEscRiskList`, which renders all risk categories and their card details.

- [ ] **Step 1: Write the failing widget tests**

```dart
testWidgets('shows every verification command and offers a copy button', (tester) async {
  await tester.pumpWidget(testApp(const PrivEscRiskList(
    risks: [PrivEscRisk(
      title: 'Passwordless sudo', evidence: 'NOPASSWD: ALL',
      level: PrivEscRiskLevel.confirmed, verificationCommands: ['sudo -l'],
    )],
  )));

  expect(find.text('已确认风险'), findsOneWidget);
  expect(find.text('sudo -l'), findsOneWidget);
  expect(find.byTooltip('复制验证命令'), findsOneWidget);
});

testWidgets('keeps raw output collapsed until the user requests details', (tester) async {
  await tester.pumpWidget(testApp(const PrivEscRiskList(risks: [/* risk with rawOutput */])));

  expect(find.text('raw sudo output'), findsNothing);
  await tester.tap(find.text('查看检测详情'));
  await tester.pump();
  expect(find.text('raw sudo output'), findsOneWidget);
});
```

Add a third widget test that supplies no risks and asserts `扫描完成，未发现已识别风险。`, and a fourth that supplies `scanIncomplete: true` and asserts the distinct incomplete-scan text.

- [ ] **Step 2: Run the widget tests and verify the expected red failure**

Run: `flutter test test/pages/priv_esc_risk_list_test.dart`

Expected: FAIL because `PrivEscRiskList` does not yet exist.

- [ ] **Step 3: Implement the list and card widgets**

```dart
class PrivEscRiskList extends StatelessWidget {
  const PrivEscRiskList({
    super.key,
    required this.risks,
    required this.onCopy,
    this.scanIncomplete = false,
  });

  final List<PrivEscRisk> risks;
  final ValueChanged<String> onCopy;
  final bool scanIncomplete;
}
```

Render the grouped risks with red, amber, and muted accents. A card must display its title, evidence, every `verificationCommands` entry in a visible code row, and an `IconButton` with tooltip `复制验证命令`. Put `rawOutput` and `checkCommand` behind an `ExpansionTile` labelled `查看检测详情`. Do not render a card command row when the command is empty or comment-only.

- [ ] **Step 4: Replace the old mixed widgets in `PrivEscTab`**

Remove `_PrivEscSuggestionsCard`, `_PrivEscGroupWidget`, and `_PrivEscItemWidget` from the default page path. In `build`, call `analyzePrivEscResults(_results)` and pass its risks into `PrivEscRiskList`; use `Clipboard.setData` inside the `onCopy` callback and show the existing short copied snackbar.

- [ ] **Step 5: Run widget and static checks**

Run: `flutter test test/pages/priv_esc_risk_list_test.dart && flutter analyze lib/pages/priv_esc_tab.dart lib/pages/priv_esc_risk_analysis.dart lib/pages/priv_esc_risk_list.dart`

Expected: PASS with no analyzer diagnostics.

- [ ] **Step 6: Commit the risk-list UI**

```bash
git add lib/pages/priv_esc_tab.dart lib/pages/priv_esc_risk_list.dart test/pages/priv_esc_risk_list_test.dart
git commit -m "feat: simplify privilege escalation risk list"
```

### Task 3: Make re-scans atomic and expose aggregate status

**Files:**

- Modify: `lib/pages/priv_esc_tab.dart:57-293`
- Modify: `test/pages/priv_esc_tab_test.dart`

**Interfaces:**

- Consumes: Existing `_groups` scan inventory and `WebshellService.executeCommand`.
- Produces: A scan header with `开始扫描`, `重新扫描`, `清空结果`, aggregate progress, and atomic committed result state.

- [ ] **Step 1: Write the failing state tests**

Extract a package-visible `PrivEscScanSession` from `PrivEscTab` with an injected `Future<String> Function(String command)` runner. Write tests asserting a new session retains `visibleResults` until `commit()` and records failed commands without storing their error text as a successful scan result:

```dart
test('does not replace visible results until a scan session commits', () async {
  final session = PrivEscScanSession({'current_priv/sudo': 'old'});
  await session.record('current_priv/sudo', 'new');

  expect(session.visibleResults['current_priv/sudo'], 'old');
  session.commit();
  expect(session.visibleResults['current_priv/sudo'], 'new');
});
```

- [ ] **Step 2: Run the state tests and verify the expected red failure**

Run: `flutter test test/pages/priv_esc_tab_test.dart`

Expected: FAIL because `PrivEscScanSession` does not yet exist.

- [ ] **Step 3: Implement the session and connect it to the scan bar**

Keep the existing sequential scan order. Store successful values in a temporary result map and failures in a separate error map. Update only the progress counter while running; when all commands finish, commit the temporary map to `_results`, set `_scanIncomplete` from the error map, and update the risk list once. The control bar must use these exact labels: `开始扫描` before the first successful scan, `重新扫描` afterward, `清空结果` only with visible results, and `正在扫描 completed / total` while running.

- [ ] **Step 4: Run the page-state tests and all privilege-escalation tests**

Run: `flutter test test/pages/priv_esc_tab_test.dart test/pages/priv_esc_risk_analysis_test.dart test/pages/priv_esc_risk_list_test.dart`

Expected: PASS.

- [ ] **Step 5: Run the full verification suite**

Run: `flutter analyze && flutter test`

Expected: Both commands exit with status 0.

- [ ] **Step 6: Commit aggregate scan behavior**

```bash
git add lib/pages/priv_esc_tab.dart test/pages/priv_esc_tab_test.dart
git commit -m "feat: report privilege escalation scan progress"
```
