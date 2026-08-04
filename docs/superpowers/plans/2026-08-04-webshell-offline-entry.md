# WebShell Offline Entry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve a known-offline WebShell's red status when opening its interactive page, rather than immediately starting another connectivity check.

**Architecture:** A pure helper maps persisted `Webshell.status` to the interactive page's initial UI state. The page uses that state to decide whether to call `_checkConnection()` from `initState`; explicit reconnect behavior stays unchanged.

**Tech Stack:** Flutter, Dart, flutter_test.

## Global Constraints

- `status == 1` means online; every other value is offline.
- Do not change connector protocols, request timeouts, or the reconnect action.
- Write and run the regression test before production code.

---

### Task 1: Initial connection-state helper and page initialization

**Files:**
- Create: `lib/pages/webshell_initial_connection_state.dart`
- Create: `test/pages/webshell_initial_connection_state_test.dart`
- Modify: `lib/pages/webshell_interactive_page.dart:35-85`

**Interfaces:**
- Produces: `WebshellInitialConnectionState.fromPersistedStatus(int status)` with `isConnected` and `shouldCheckOnOpen` booleans.
- Consumes: `Webshell.status` in `WebshellInteractivePage.initState`.

- [x] **Step 1: Write the failing test**

```dart
test('offline persisted status does not start a connectivity check', () {
  final state = WebshellInitialConnectionState.fromPersistedStatus(0);

  expect(state.isConnected, isFalse);
  expect(state.shouldCheckOnOpen, isFalse);
});

test('online persisted status starts a connectivity check', () {
  final state = WebshellInitialConnectionState.fromPersistedStatus(1);

  expect(state.isConnected, isTrue);
  expect(state.shouldCheckOnOpen, isTrue);
});
```

- [x] **Step 2: Run the test to verify it fails**

Run: `flutter test test/pages/webshell_initial_connection_state_test.dart`

Expected: failure because `WebshellInitialConnectionState` does not exist.

- [x] **Step 3: Write the minimal implementation**

```dart
class WebshellInitialConnectionState {
  final bool isConnected;
  final bool shouldCheckOnOpen;

  const WebshellInitialConnectionState({
    required this.isConnected,
    required this.shouldCheckOnOpen,
  });

  factory WebshellInitialConnectionState.fromPersistedStatus(int status) {
    final isOnline = status == 1;
    return WebshellInitialConnectionState(
      isConnected: isOnline,
      shouldCheckOnOpen: isOnline,
    );
  }
}
```

Initialize `_isConnected` from the helper in `initState` and call
`_checkConnection()` only when `shouldCheckOnOpen` is true. Keep `_isChecking`
false for a persisted offline entry.

- [x] **Step 4: Run focused tests to verify they pass**

Run: `flutter test test/pages/webshell_initial_connection_state_test.dart`

Expected: both tests pass.

- [x] **Step 5: Run static analysis**

Run: `flutter analyze`

Expected: exit code 0.
