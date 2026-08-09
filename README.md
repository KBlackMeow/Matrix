# Matrix

Matrix is a cross-platform desktop application for managing WebShells and carrying out authorized security assessments. It brings target organization, interactive access, payload management, exploit checks, tunneling, reverse shells, and AI-assisted operations into one workspace.

> [!WARNING]
> Matrix is intended only for systems you own or are explicitly authorized to test. Unauthorized access is illegal and may cause serious harm.

## Features

- **Project workspaces** — Organize targets, WebShells, payloads, tunnels, and MCP access by project.
- **WebShell management** — Connect to supported PHP, JSP, ASP, and ASPX WebShells through multiple connector types.
- **Interactive operations** — Execute commands, browse and transfer files, inspect system information and processes, and perform supported privilege-escalation checks.
- **Reverse-shell terminal** — Start and manage interactive reverse-shell sessions in a full terminal interface.
- **Payload library** — Manage built-in and imported payloads and upload them from the file manager.
- **Exploit modules** — Run supported checks and authorized testing workflows for Apache Shiro, ThinkPHP, ZenTao, Struts2, Spring, Apache HTTP Server, Drupal, PHP, Tomcat, WebLogic, XXL-JOB, and Nacos targets.
- **Intranet tunneling** — Manage FRP connections and SUO5/SUO6 SOCKS proxy tunnels.
- **MCP Server** — Give MCP-compatible AI assistants controlled access to the WebShell operations in the currently selected project.
- **Local storage** — Keep project and connection data in a local SQLite database on the desktop running Matrix.

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
