# Read-Only Privilege-Escalation Proof Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace inference-based privilege-escalation findings with evidence-backed, read-only proof results.

**Architecture:** Add a standalone proof-rule module that maps discovery output to a fixed sequence of allowlisted validation commands and parses only exact confirmation markers. `PrivEscTab` runs discovery first, then schedules the read-only proofs and sends only confirmed `PrivEscRisk` records to the list UI.

**Tech Stack:** Flutter, Dart 3.11, Material widgets, `flutter_test`.

## Global Constraints

- Validation commands must never write files, change permissions, create a container/profile/image, spawn an interactive privileged shell, or modify configuration.
- A missing marker, malformed output, command failure, or timeout must not produce a risk.
- A card may only show commands from the proof-rule allowlist and must show the proof output in its collapsed details.
- Keep all existing discovery commands; discovery findings without a completed proof remain hidden from the risk list.

---

### Task 1: Define testable proof rules

**Files:**

- Create: `lib/pages/priv_esc_proof_rules.dart`
- Create: `test/pages/priv_esc_proof_rules_test.dart`

**Interfaces:**

- Produces `PrivEscProofCandidate`, `PrivEscProofCommand`, `PrivEscProofResult`, and `PrivEscProofRules`.
- `PrivEscProofRules.candidates(Map<String, String?> discovery)` returns only candidates whose discovery predicate matched.
- `PrivEscProofRules.confirm(candidate, output)` returns a `PrivEscRisk?`; it returns `null` unless every required marker is present.

- [ ] **Step 1: Write the failing sudo proof tests**

```dart
test('confirms sudo only after a second NOPASSWD ALL proof', () {
  const candidate = PrivEscProofCandidate.sudoAll();

  expect(
    PrivEscProofRules.confirm(candidate, '(ALL) NOPASSWD: ALL'),
    isA<PrivEscRisk>(),
  );
  expect(PrivEscProofRules.confirm(candidate, 'sudo: a password is required'), isNull);
});
```

Add equivalent confirmed, rejected, and malformed-output tests for Docker, LXD, and logrotate. Add a test that the complete command allowlist contains no `>`, `>>`, `chmod`, `rm`, `docker run`, `lxc init`, `sudo -i`, or shell-spawn token.

- [ ] **Step 2: Run the proof-rule tests and verify red**

Run: `flutter test test/pages/priv_esc_proof_rules_test.dart`

Expected: FAIL because `priv_esc_proof_rules.dart` does not exist.

- [ ] **Step 3: Implement immutable candidate and proof types**

```dart
class PrivEscProofCandidate {
  const PrivEscProofCandidate({
    required this.id,
    required this.title,
    required this.discoveryEvidence,
    required this.commands,
  });

  final String id;
  final String title;
  final String discoveryEvidence;
  final List<PrivEscProofCommand> commands;
}

class PrivEscProofCommand {
  const PrivEscProofCommand(this.command, this.requiredMarkers);
  final String command;
  final List<Pattern> requiredMarkers;
}
```

Use these exact proof commands:

```text
sudo -n -l
docker version --format '{{.Server.Version}}' 2>/dev/null
lxc info 2>/dev/null
test -w <path> && grep -Fxq 'include /etc/logrotate.d' /etc/logrotate.conf && logrotate -d /etc/logrotate.conf 2>&1
```

For logrotate, candidate discovery must parse only paths after the `--- writable ---` marker and generate a candidate only for an absolute path under `/etc/logrotate.d/`.

- [ ] **Step 4: Run the proof-rule tests and verify green**

Run: `flutter test test/pages/priv_esc_proof_rules_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit the proof rules**

```bash
git add lib/pages/priv_esc_proof_rules.dart test/pages/priv_esc_proof_rules_test.dart
git commit -m "feat: add read-only privilege proof rules"
```

### Task 2: Add allowlisted SUID proof candidates

**Files:**

- Modify: `lib/pages/priv_esc_proof_rules.dart`
- Modify: `test/pages/priv_esc_proof_rules_test.dart`

**Interfaces:**

- `PrivEscProofRules.candidates` accepts `esc_vectors/suid` discovery output.
- Each supported SUID candidate exposes exactly one non-mutating identity command.

- [ ] **Step 1: Write failing SUID tests**

```dart
test('only produces an SUID risk when a supported candidate returns euid zero', () {
  final candidate = PrivEscProofRules.candidates({
    'esc_vectors/suid': '/usr/bin/find',
  }).single;

  expect(PrivEscProofRules.confirm(candidate, 'uid=1000(user) euid=0(root)'), isNotNull);
  expect(PrivEscProofRules.confirm(candidate, 'uid=1000(user) euid=1000(user)'), isNull);
});

test('does not create a candidate for an unallowlisted SUID binary', () {
  expect(PrivEscProofRules.candidates({'esc_vectors/suid': '/usr/bin/passwd'}), isEmpty);
});
```

- [ ] **Step 2: Run SUID tests and verify red**

Run: `flutter test test/pages/priv_esc_proof_rules_test.dart`

Expected: FAIL because SUID candidates are not implemented.

- [ ] **Step 3: Implement only documented safe identity checks**

Support only allowlisted binaries whose identity invocation is non-mutating and bounded. Encode the exact commands in the rule module; no path from discovery output may be interpolated into a command unless it matches the complete allowlisted absolute path.

- [ ] **Step 4: Run SUID proof tests and verify green**

Run: `flutter test test/pages/priv_esc_proof_rules_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit the SUID proofs**

```bash
git add lib/pages/priv_esc_proof_rules.dart test/pages/priv_esc_proof_rules_test.dart
git commit -m "feat: verify allowlisted SUID proof paths"
```

### Task 3: Run proofs after discovery and render evidence

**Files:**

- Modify: `lib/pages/priv_esc_tab.dart`
- Modify: `lib/pages/priv_esc_risk.dart`
- Modify: `lib/pages/priv_esc_risk_list.dart`
- Modify: `test/pages/priv_esc_risk_list_test.dart`

**Interfaces:**

- Consumes `PrivEscProofRules.candidates(discoveryResults)` and `PrivEscProofRules.confirm(candidate, output)`.
- Produces only `PrivEscRisk(hasDirectPrivilegeProof: true)` entries.

- [ ] **Step 1: Write the failing UI proof-output test**

```dart
testWidgets('renders proof output only for a confirmed risk', (tester) async {
  await tester.pumpWidget(testApp(const PrivEscRiskList(
    risks: [PrivEscRisk(
      title: 'Passwordless sudo', evidence: 'Second sudo proof matched',
      hasDirectPrivilegeProof: true,
      checkCommand: 'sudo -n -l', rawOutput: '(ALL) NOPASSWD: ALL',
    )],
  )));

  await tester.tap(find.text('查看检测详情'));
  await tester.pumpAndSettle();
  expect(find.text('(ALL) NOPASSWD: ALL'), findsOneWidget);
});
```

- [ ] **Step 2: Run the UI test and verify red**

Run: `flutter test test/pages/priv_esc_risk_list_test.dart`

Expected: FAIL because the proof lifecycle is not connected to the risk list.

- [ ] **Step 3: Implement sequential proof execution**

After discovery commands complete, obtain candidates, execute each fixed proof command through `WebshellService.executeCommand`, and call `confirm`. Store only non-null proof results as visible risks. Retain proof command and raw output in each risk. A failed proof sets the scan-incomplete indicator but adds no card.

- [ ] **Step 4: Replace title-matching command lookup**

Remove `_verificationCommandsFor`, `_sourceFor`, `_rawOutputFor`, and `_checkCommandFor` from `PrivEscTab`. The card must consume the proof command/output carried by `PrivEscRisk`, so a card cannot accidentally show a discovery command as a proof.

- [ ] **Step 5: Run targeted checks and full regression suite**

Run: `flutter analyze lib/pages/priv_esc_tab.dart lib/pages/priv_esc_risk.dart lib/pages/priv_esc_risk_list.dart lib/pages/priv_esc_proof_rules.dart && flutter test`

Expected: Analyzer reports no diagnostics for changed files and all tests pass.

- [ ] **Step 6: Commit lifecycle and UI integration**

```bash
git add lib/pages/priv_esc_tab.dart lib/pages/priv_esc_risk.dart lib/pages/priv_esc_risk_list.dart lib/pages/priv_esc_proof_rules.dart test/pages/priv_esc_risk_list_test.dart
git commit -m "feat: show confirmed privilege proof results"
```
