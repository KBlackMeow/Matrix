# Read-Only Privilege-Escalation Proof Design

## Goal

Show a privilege-escalation risk only when a fixed, non-mutating validation proof has produced the complete evidence required for that specific path.

## Scope

- Keep the existing discovery scan as the first stage.
- Add a second stage only for an allowlisted set of paths.
- Every second-stage command must be read-only: no file writes, process changes, container creation, privilege-shell spawn, configuration changes, or persistence.
- A missing result, unexpected output, command error, or timeout is not a risk.

## Validation Paths

### Passwordless sudo

The discovery result must contain a passwordless `ALL` rule. The proof command is `sudo -n -l`; it must return a passwordless `ALL` rule. Only then render a confirmed sudo risk.

### SUID allowlist

The discovery result must contain an allowlisted SUID executable. Its proof command must run only a side-effect-free identity query through the candidate's documented safe mode. The output must explicitly show effective UID `0`. Unsupported executables stay as discovery-only evidence and never render a risk.

### Docker and LXD

Group membership alone is insufficient. A confirmed risk needs group membership plus an accessible local daemon socket verified by `docker version` or `lxc info`; the output must identify a responsive daemon. The verification command must not create an image, container, or profile.

### Logrotate

The discovery result must identify a specific current-user-writable rule file. The proof must establish that `/etc/logrotate.conf` includes `/etc/logrotate.d`, that the named file exists and remains writable to the current user, and that logrotate's debug output loads that exact rule. Any missing element suppresses the risk.

## Results

- A risk card contains the proof name, exact evidence, validation command, and validation output.
- The risk list contains confirmed paths only. It does not show potential or informational paths.
- The scan header distinguishes discovery progress from proof progress and marks an incomplete run when any proof fails.

## Testing

Use fixtures for every validator's confirmed, rejected, and errored output. Assert that only confirmed fixtures generate cards and that every generated proof command is in the read-only allowlist.
