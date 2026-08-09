# Matrix

Matrix is a cross-platform desktop application for managing WebShells and carrying out authorized security assessments. It brings target organization, interactive access, payload management, exploit checks, tunneling, reverse shells, and AI-assisted operations into one workspace.

> [!WARNING]
> Matrix is intended only for systems you own or are explicitly authorized to test. Unauthorized access is illegal and may cause serious harm.

## Features

### Project Workspaces

- Create, edit, and delete projects for separate assessment scopes.
- Store a target URL and project description.
- Keep WebShells, exploit targets, SUO tunnel profiles, and MCP access scoped to the selected project.
- Open a project's WebShell, exploit, tunnel, or MCP workspace directly from the project list.

### WebShell Management

- Add, edit, delete, and test saved WebShell connections.
- Check all saved WebShells and preserve their last known online or offline status.
- Configure aliases, URLs, passwords or parameter keys, connector types, and supported GET or POST methods.
- Auto-detect a responsive connector for a supplied target.
- Work with PHP, JSP, classic ASP, and ASP.NET targets through the following connectors:

| Target | Connectors |
| --- | --- |
| PHP | Eval, Base64 + ROT13, Behinder-compatible encrypted payloads, and passthru command shells |
| JSP | ClassLoader agent, Behinder-compatible AES payloads, dynamic-bytecode Behinder v2, and Runtime command shells |
| ASP | WScript command shells |
| ASPX | Command shells and Behinder-compatible encrypted payloads |

### Interactive WebShell Workspace

Each saved WebShell opens into an operational workspace with:

- **Terminal** — Run commands, switch between integrated and split-input modes, use command history and completion, and maintain the remote working directory.
- **File manager** — Browse directories; preview text and supported source files; upload, download, write, and delete files where the selected connector supports the operation.
- **Payload upload** — Select an item from the payload library and upload it to the current remote directory.
- **Payload obfuscation** — Obfuscate supported payloads before upload and recognize or deobfuscate supported content when viewing files.
- **System information** — Inspect operating-system, runtime, user, hostname, server address, document root, working directory, and related host details returned by the target.
- **Process management** — List running processes and terminate a selected process when supported.
- **Linux privilege checks** — Review identity and sudo access, kernel and distribution information, SUID/SGID files, capabilities, cron jobs, writable paths, PATH hijacking opportunities, accounts, shell history, SSH keys, and exposed configuration credentials.
- **Reverse shell** — Configure a listener and send a built-in script, Bash, or shell command to open a full interactive terminal.
- **One-click tunneling** — Upload or inject a compatible SUO5/SUO6 payload and create a tunnel profile from the active WebShell.

Some operations depend on the target operating system and connector capabilities. For example, Linux privilege checks are hidden for ASP and ASPX targets, and connectors without file-write support cannot upload or modify files.

### Payload Library

- Use the bundled WebShell, tunneling, and supporting payloads.
- Import additional text or binary payload files.
- Preview text payloads and identify binary payloads without rendering unsafe content.
- Copy text directly or copy any payload as Base64.
- Export payloads to local files.
- Upload a selected payload to a WebShell temporary directory with progress and cancellation support.
- Keep bundled defaults protected while allowing imported payloads to be deleted.

### Exploit Modules

Matrix groups its supported checks and exploitation workflows by project. Current modules include:

| Target | Covered vulnerabilities or workflows |
| --- | --- |
| Apache Shiro | CVE-2016-4437, `rememberMe` detection, key testing, payload injection, and supported memory-shell workflows |
| ThinkPHP | CVE-2018-20062, CVE-2019-9082, CNVD-2022-86535, command execution, and supported GetShell workflows |
| ZenTao | CVE-2024-24216 detection and supported repository-configuration WebShell workflow |
| Apache Struts2 | S2-032, S2-045, S2-053, S2-057, and S2-059 |
| Spring Framework | CVE-2022-22963, CVE-2022-22965, CVE-2018-1273, and CVE-2017-8046 |
| Apache HTTP Server | CVE-2021-41773 |
| Drupal | CVE-2018-7600, also known as Drupalgeddon 2 |
| PHP | PHP 8.1.0-dev `User-Agentt` backdoor and CVE-2012-1823 PHP-CGI argument injection |
| Apache Tomcat | CVE-2017-12615 |
| Oracle WebLogic | CVE-2017-10271 and CVE-2020-14882 |
| XXL-JOB | Supported XXL-JOB access and command-execution checks |
| Nacos | CVE-2021-29441 |

Available actions vary by module and can include detection, command execution, payload delivery, and reverse-shell startup. A module being listed does not mean every target version or deployment is exploitable.

### Reverse-Shell Terminal

- Configure and start or stop a local listener.
- Track multiple active and disconnected sessions.
- Open each connected session in a full xterm-based terminal.
- Use script-backed pseudo-terminal mode on compatible Unix-like targets or a Bash/shell fallback where `script` is unavailable.
- Reuse the configured listener from WebShell and exploit workflows.

### Intranet Tunneling

- **FRP client** — Save multiple profiles, configure server and local or remote endpoints, duplicate profiles with conflict-safe names and ports, start or stop a profile, and inspect connection logs.
- **SUO5/SUO6 SOCKS proxy** — Save project-scoped tunnel profiles, select the protocol per profile, test the remote handshake, run multiple SUO5 sessions, and monitor connection, traffic, and runtime logs.
- **WebShell integration** — Create a tunnel from the interactive WebShell workspace and prefill the target URL automatically.

### AI Integration Through MCP

- Start or stop an MCP server inside Matrix for the selected project.
- Use a configurable local port with Streamable HTTP at `/mcp`.
- Expose WebShell configuration, command execution, remote file operations, upload and download workflows, system information, environment variables, and process management to compatible AI assistants.
- Isolate connection sessions, serialize conflicting remote writes, restrict WebShell records to the active project, and display calls in an activity log.
- Bind only to `127.0.0.1` and `localhost` rather than exposing the service to the network.

See [MCP Server](#mcp-server) for setup and safety details.

### Local Application Features

- Store projects, WebShells, payload metadata, and connection profiles in a local SQLite database.
- Seed and update bundled payloads without replacing user-imported payloads.
- Switch the application interface between English, Chinese, and Japanese.
- Use the vendored xterm component with CJK rendering adjustments for terminal sessions.

## Supported Platforms

Matrix targets:

- macOS
- Windows
- Linux

Mobile platforms and Flutter Web are not official support targets.

## Installation

Download the appropriate package from [GitHub Releases](https://github.com/KBlackMeow/Matrix/releases), when available, and follow the normal installation process for your operating system.

You can also build Matrix from source using the instructions below.

## Getting Started

1. Open **Projects** and create a project for the authorized assessment.
2. Select the project and open **Webshell**.
3. Add a WebShell URL, password, script type, connector type, and HTTP method.
4. Check its connection status, then open it to access the terminal, file manager, system information, process list, and supported privilege-escalation tools.
5. Use **Payloads**, **Exploits**, **Terminal**, **FRP Client**, or **suo5/suo6** as required by the engagement.

Matrix keeps actions scoped to the selected project where applicable. Verify the active project and target before running any operation.

## MCP Server

Matrix includes a local [Model Context Protocol](https://modelcontextprotocol.io/) server that allows an MCP-compatible AI assistant to work with the selected project's WebShells.

To use it:

1. Select or enter a project in Matrix.
2. Open **MCP**.
3. Choose the local port and start the server.
4. Connect your MCP client to the endpoint displayed by Matrix.

The default endpoint is:

```text
http://127.0.0.1:3000/mcp
```

The MCP server uses Streamable HTTP and provides tools for:

- Listing, adding, selecting, and removing WebShell configurations
- Executing commands on a selected WebShell
- Listing, reading, writing, uploading, downloading, and deleting files
- Reading system information, the home directory, and environment variables
- Listing and terminating processes

For safety, the server binds to the local loopback interface and limits WebShell access to the active project. MCP calls are shown in the activity log. Review every action requested by an AI client, especially command execution, file writes, deletions, and process termination.

## Local Data and Security

- Matrix stores its database and working data locally on your computer.
- WebShell credentials are sensitive. Protect the operating-system account and backups that contain Matrix data.
- MCP uploads and downloads use a Matrix-managed local workspace; the application may ask you to select it on macOS.
- Stop MCP, tunnel, and reverse-shell services when they are no longer needed.
- Treat generated payloads and downloaded remote files as untrusted content.

## Build from Source

Install a Flutter SDK compatible with the Dart SDK requirement in [`pubspec.yaml`](pubspec.yaml), then run:

```bash
flutter pub get
flutter run -d macos    # or windows / linux
```

To create a release build for the current platform:

```bash
flutter build macos --release      # macOS
flutter build windows --release    # Windows
flutter build linux --release      # Linux
```

Platform-specific Flutter desktop tooling is required. Builds must be produced on their corresponding host operating system.

## Disclaimer

Matrix is provided solely for authorized penetration testing, defensive security validation, education, and research. Do not use it to access, disrupt, modify, or extract data from any system without explicit permission.

You are responsible for obtaining authorization, defining the scope of each assessment, protecting collected data, and complying with all applicable laws, contracts, and organizational policies. The authors and contributors accept no responsibility for misuse or damage caused by this software.

## License

See [LICENSE](LICENSE).
