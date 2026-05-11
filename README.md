# Matrix

> A next-generation customizable Webshell management tool built with Flutter, supporting macOS / Windows / Linux.

---

## Key Features

### Webshell Management

Multi-protocol connectors covering mainstream Webshell types:

| Type | Connector |
| ---- | --------- |
| PHP  | eval, passthru, base64+rot13 obfuscation, Behinder 3.0 (AES) |
| JSP  | Behinder 3.0, Runtime exec, ClassLoader bytecode loader |
| ASP  | WScript.Shell |
| ASPX | .NET Process |

Interactive capabilities:

- Interactive terminal
- Visual file manager (upload / download / delete / rename)
- Select files from the payload library and upload to the current remote directory
- System information collection (OS, privileges, network, processes)
- Privilege escalation vector checks (SUID, passwordless sudo, kernel version)
- Reverse shell generation

### Payload Management

- Built-in common payloads for PHP / JSP / ASP / ASPX
- Import payloads from local files and copy, download, or convert to Base64 in detail view
- Base64 storage and download support for binary payloads
- Upload payload library files directly from the Webshell file manager to the target directory

### Vulnerability Exploits (EXP)

| Framework / Component | Vulnerability |
| --------------------- | ------------- |
| Apache Shiro | CVE-2016-4437 |
| ThinkPHP | CVE-2018-20062 / CVE-2019-9082 / CNVD-2022-86535 |
| Zentao | CVE-2024-24216 |
| Apache Struts2 | S2-032 / S2-045 / S2-053 / S2-057 / S2-059 |
| Spring Framework | CVE-2022-22963 / CVE-2022-22965 / CVE-2018-1273 / CVE-2017-8046 |
| Apache HTTP Server | CVE-2021-41773 |
| Drupal | CVE-2018-7600 |
| Apache Tomcat | CVE-2017-12615 |
| Oracle WebLogic | CVE-2017-10271 / CVE-2020-14882 |
| XXL-JOB | Unauthenticated Executor RCE |
| Nacos | CVE-2021-29441 |

### Intranet Tunneling

Reverse access and SOCKS-style bridging from the desktop client:

- Built-in FRP client
- **SUO5** proxy: deploy PHP / JSP / ASPX tunnel stubs from the payload library and expose a **local SOCKS5** port; per-project profiles, concurrent tunnels, connectivity probe, and traffic stats

---

## Quick Start

```bash
flutter pub get
flutter run -d macos    # or windows / linux
```

> The current focus is desktop platforms (macOS / Windows / Linux). Flutter Web is not an official support target.

---

## Disclaimer

This tool is intended only for authorized penetration testing and security research. Any use against unauthorized systems is strictly prohibited. Users are solely responsible for all legal consequences.
