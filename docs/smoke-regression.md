# Matrix Minimal Smoke Regression

## Scope

- Project management
- Webshell CRUD and entry to interactive page
- Payload and dictionary management
- Vulhub page entry actions

## Quick Automated Checks

- `flutter test`
- `flutter analyze lib/exp/thinkphp/thinkphp_exp_service.dart lib/exp/thinkphp/thinkphp_v5_exp.dart lib/exp/thinkphp/thinkphp_v6_exp.dart`

## Manual Checklist

- Project management: create/edit/delete a project.
- Webshell management: create/edit/delete a webshell under a selected project.
- Webshell interaction: open one record and verify page loads and command panel is responsive.
- Payload management: create/edit/delete one payload and verify list refreshes.
- Dictionary management: create/edit/delete one dictionary entry and verify list refreshes.
- Vulhub entries: open each Vulhub EXP page from `EXP管理` and trigger one basic detection action per page.

## Pass Criteria

- No crash during each operation.
- UI state updates after create/edit/delete.
- Navigation to target pages succeeds.
- Detection actions return logs or expected error messages without blocking the UI.
