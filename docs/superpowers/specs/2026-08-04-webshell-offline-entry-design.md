# WebShell Offline Entry Design

## Goal

Avoid a second, automatic connectivity check when a WebShell is already shown
as offline in the management menu.

## Current behavior

The menu stores the result of its five-second background connectivity check in
`Webshell.status`. `WebshellInteractivePage` ignores that value, initializes
its local state as checking, and always starts `_checkConnection()` from
`initState`. This makes an already-offline entry display a yellow indicator and
spinner while it repeats a potentially slow request.

## Design

`WebshellInteractivePage` will initialize its local connection state from
`widget.webshell.status`:

- `status == 1`: start in the connected state and run the existing initial
  verification.
- `status != 1`: start in the disconnected state, show the existing failure
  banner immediately, and do not call `_checkConnection()` automatically.

The existing **Reconnect** action remains the explicit way to start a new
check for an offline entry. Its behavior, including the command fallback, is
unchanged.

## Testing

Extract the initial-state decision to a small, pure helper in the interactive
page module (or a nearby focused utility) and cover both persisted statuses:
online starts checking; offline starts disconnected without checking. A widget
test may be added only if the current page dependencies permit it without
network I/O.

## Scope

No connector protocol, network timeout, or database schema changes are part of
this fix.
