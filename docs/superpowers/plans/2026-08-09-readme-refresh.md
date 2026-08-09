# README Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the root README with an accurate English user guide that includes Matrix's current MCP capabilities.

**Architecture:** This is a documentation-only change. `README.md` remains the single user-facing entry point, with sections ordered from product overview and installation through first use, MCP, security notes, and source builds.

**Tech Stack:** Markdown, Flutter desktop command-line tooling

## Global Constraints

- English only.
- User-oriented language; avoid internal architecture details.
- Do not claim mobile or Flutter Web support.
- Describe only functionality verified in the repository.
- Do not change application code, configuration, or release artifacts.
- Keep build-from-source instructions concise.

---

### Task 1: Rewrite the user README

**Files:**
- Modify: `README.md`
- Reference: `pubspec.yaml`
- Reference: `lib/pages/mcp_server_page.dart`
- Reference: `lib/mcp/handlers.dart`

**Interfaces:**
- Consumes: Matrix version, supported desktop targets, built-in features, MCP endpoint, and MCP tool groups from the referenced files.
- Produces: A standalone English guide for packaged-build users and users building from source.

- [ ] **Step 1: Replace the existing README structure**

Write sections for overview, features, supported platforms, installation, getting started, MCP Server, local data and security, building from source, and disclaimer. Make MCP a top-level feature and document the default local endpoint `http://127.0.0.1:3000/mcp`.

- [ ] **Step 2: Verify factual claims against the repository**

Run:

```bash
rg -n "version:|host: '127.0.0.1'|port: port|path: '/mcp'|registerTool" pubspec.yaml lib/pages/mcp_server_page.dart lib/mcp/handlers.dart
```

Expected: version `1.2.0+1`, loopback binding, configurable port defaulting to `3000`, `/mcp` path, and registered MCP tools supporting the documented operation groups.

- [ ] **Step 3: Check Markdown and scope**

Run:

```bash
git diff --check
git diff -- README.md
```

Expected: no whitespace errors; only the approved English user documentation appears in the README diff.

- [ ] **Step 4: Review commands**

Run:

```bash
flutter --version
```

Expected: Flutter is installed and the documented `flutter pub get` and `flutter run -d <platform>` commands use valid Flutter CLI syntax.
