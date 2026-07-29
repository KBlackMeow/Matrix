# MCP safety fixes

## Scope

Remove the command-line MCP entry point. Matrix will expose the MCP server only
from the in-app control page over loopback HTTP.

## Changes

1. Give each HTTP MCP connection its own `SessionPool`, so `shell_use` and
   cached connector state cannot affect another client.
2. Make the JSP agent decode the encrypted body parameter `path_b64` whenever
   a caller requests `path`. This preserves non-ASCII file paths.

## Out of scope

Authentication, access tokens, upload/download size limits, database-path
validation, activity-log redaction, and the CLI MCP server are not part of
this change.

## Verification

Add focused tests for session isolation and body-encoded non-ASCII paths. Run
the targeted tests and the full Flutter test suite.
