# README Refresh Design

## Goal

Replace the minimal root README with an English-only guide for ordinary Matrix users. The document should explain what Matrix does, how to obtain or start it, the main workflow, and the safety boundaries of the application.

## Audience

The primary audience is an authorized security tester using a packaged desktop build. Developer details are secondary and limited to a short source-build section.

## Structure

The README will contain:

1. A concise product overview and authorization warning.
2. Supported desktop platforms and current version information.
3. A feature overview covering project organization, WebShell operations, payloads, EXP modules, reverse shells, tunneling, and MCP.
4. Installation guidance for packaged releases and a short source-build fallback.
5. A first-use workflow from creating a project through opening an interactive WebShell session.
6. An MCP Server section describing its local endpoint, project scope, supported operation groups, and local-only binding.
7. Local-data and security notes.
8. The existing legal disclaimer in stronger, user-facing language.

## MCP Coverage

MCP is presented as a first-class feature. The README will explain that Matrix can expose the selected project's WebShell operations to MCP-compatible AI assistants over Streamable HTTP at `http://127.0.0.1:3000/mcp` by default. It will summarize WebShell management, command execution, file operations, transfers, system information, environment inspection, and process management. It will not include client-specific configuration examples.

## Constraints

- English only.
- User-oriented language; avoid internal architecture details.
- Do not claim mobile or Flutter Web support.
- Describe only functionality verified in the repository.
- Do not change application code, configuration, or release artifacts.
- Keep build-from-source instructions concise.

## Validation

Check all commands and feature claims against the current repository, confirm Markdown structure renders cleanly, and review the final diff for unsupported claims or accidental changes outside the README.
