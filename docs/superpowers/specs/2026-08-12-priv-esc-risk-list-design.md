# Privilege-Escalation Risk List Design

## Goal

Replace the privilege-escalation page's mixed checklist, raw output, and suggestions with a compact post-scan risk list that makes each identified risk and its safe verification command immediately readable.

## Scope

- Preserve every existing scan command and result-analysis rule, including the user's uncommitted additions.
- Replace the default checklist-centric presentation with scan status plus parsed risk results.
- Do not add execution of privilege-escalation payloads from this page. The page remains a discovery and verification surface.

## User Flow

1. The user starts a scan or re-runs the last scan.
2. The control bar reports one aggregate progress value, for example `正在扫描 8 / 24`.
3. When scanning ends, parsed findings appear as risk cards, sorted by confidence.
4. A user reads the evidence and the fully expanded verification command, then copies a command with one click if needed.
5. The user can expand a card only when they need the underlying scan output.

## Information Architecture

The page has exactly two persistent regions.

### Scan control bar

- Title: `提权风险扫描`.
- Status: scan count while idle; aggregate `completed / total` progress while scanning; latest result count when complete.
- Primary action: `开始扫描` before results exist, otherwise `重新扫描`.
- Secondary action: `清空结果`, shown only when results exist and disabled while a scan runs.
- No individual check controls or empty check-result sections are displayed in the default view.

### Risk results

Findings are rendered in this exact order:

1. `已确认风险` — strong evidence from the completed scans; red accent.
2. `待验证风险` — a plausible route needing human confirmation of its environment or prerequisites; amber accent.
3. `信息线索` — relevant but non-actionable observations; muted accent.

Empty categories are omitted. When no finding is produced, show a calm empty state: `扫描完成，未发现已识别风险。` If every command fails, use a distinct incomplete-state message and retain the available error details.

## Risk Card

Each card contains, in this order:

- Severity and confidence label.
- Risk title.
- Short evidence sentence derived from the matched scan result.
- `验证命令` code block, fully expanded by default. Every command row has an adjacent copy button; copying shows a brief confirmation without changing page layout.
- An optional collapsed `查看检测详情` control that shows the associated raw result and the check command. This is the only location for raw output.

Copy actions copy exactly the visible command text. Comment-only lines are not presented as copyable verification commands. Risk cards do not expose exploitation or destructive actions.

## State and Error Handling

- A scan runs sequentially using the existing command execution service and shows one aggregate progress state rather than interleaving output into the list.
- Existing result values stay in memory until a scan completes or the user clears them, so the interface never presents a partial new result set as final.
- Failed checks contribute to a concise incomplete-scan indicator; they never create a false negative or a risk card.
- Re-scanning replaces the prior results only after the new scan ends.

## Component Boundaries

- `PrivEscTab`: owns scan lifecycle, temporary versus committed scan results, analysis invocation, and page-level actions.
- `PrivEscScanBar`: displays scan state and invokes start, rescan, and clear callbacks.
- `PrivEscRiskList`: groups non-empty findings and selects the empty/incomplete state.
- `PrivEscRiskCard`: renders evidence, copyable verification commands, and expandable technical detail.

The existing finding model will be extended or renamed so it carries confidence level, verification commands, and optional source-result details. Parsing stays in a testable non-widget boundary.

## Verification

Tests must establish that:

- findings sort into confirmed, needs-verification, and informational groups in that order;
- no empty group is rendered;
- every verification command is visible and copyable;
- raw check output is hidden until explicitly expanded;
- no-finding and incomplete-scan states are distinct;
- existing parsers still produce their corresponding findings after the UI refactor.
