# MCP safety fixes

## Scope

Remove the command-line MCP entry point. Matrix will expose the MCP server only
from the in-app control page over loopback HTTP.

## Changes

1. Give each HTTP MCP connection its own `SessionPool`, so `shell_use` and
   cached connector state cannot affect another client.
2. Make the JSP agent decode the encrypted body parameter `path_b64` whenever
   a caller requests `path`. This preserves non-ASCII file paths.
3. Validate that the application database already exists and contains the
   expected schema before the MCP service starts. A missing or invalid database
   fails visibly instead of creating an unusable empty SQLite file.
4. Limit activity logs to operation metadata. Do not log command text, file
   contents, base64 download data, passwords, or tool output.

## Out of scope

Authentication, access tokens, upload/download size limits, and the CLI MCP
server are not part of this change.

## Verification

Add focused tests for session isolation, body-encoded non-ASCII paths,
database validation, and log redaction. Run the targeted tests and the full
Flutter test suite.
