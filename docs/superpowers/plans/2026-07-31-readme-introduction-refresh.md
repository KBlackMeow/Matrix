# README Introduction Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the verbose English README introduction with a concise, accurate project overview.

**Architecture:** Keep README.md as the only product-facing artifact. Replace the detailed feature and vulnerability inventories with four short capability groups, retain the existing desktop Flutter start command, and retain an authorization-only disclaimer.

**Tech Stack:** Markdown; Flutter CLI documentation.

## Global Constraints

- The README remains English and concise.
- Describe Matrix only as a Flutter desktop application for authorized webshell management and security testing.
- Do not change application code, build configuration, or security functionality.
- Retain the macOS, Windows, and Linux support scope and the Flutter quick-start command.

---

### Task 1: Refresh README landing content

**Files:**
- Modify: `README.md:1-73`
- Test: `README.md` rendered by a CommonMark-compatible Markdown viewer

**Interfaces:**
- Consumes: Application capabilities documented in `docs/superpowers/specs/2026-07-31-readme-introduction-design.md`.
- Produces: A concise English landing README for repository visitors.

- [ ] **Step 1: Replace the README content with the following Markdown**

```markdown
# Matrix

Matrix is a Flutter desktop application for authorized webshell management and security testing on macOS, Windows, and Linux.

## Highlights

- **Webshell operations** — Connect to common PHP, JSP, ASP, and ASPX webshells; work with terminals, files, and host information.
- **Payload library** — Manage built-in and imported payloads, then upload them directly from the file manager.
- **Security testing** — Run supported exploit checks, privilege-escalation checks, and reverse-shell generation during authorized assessments.
- **Intranet tunneling** — Use built-in FRP and SUO5/SUO6 SOCKS tunneling for approved remote-access workflows.

## Quick Start

```bash
flutter pub get
flutter run -d macos    # or windows / linux
```

Matrix currently targets desktop platforms. Flutter Web is not an official support target.

## Disclaimer

Matrix is intended solely for authorized penetration testing and security research. Do not use it against systems without explicit permission; you are responsible for complying with all applicable laws and policies.
```

- [ ] **Step 2: Inspect Markdown structure and required wording**

Run: `rg -n '^# |^## |Webshell operations|Payload library|Security testing|Intranet tunneling|flutter run -d macos|authorized' README.md`

Expected: one title, three section headings, four highlight bullets, the macOS command, and authorization wording.

- [ ] **Step 3: Review the rendered content**

Open `README.md` in a Markdown viewer and confirm that the Highlights list, Quick Start code block, and Disclaimer are readable without horizontal scrolling.

- [ ] **Step 4: Commit the documentation update**

```bash
git add README.md
git commit -m "docs: refresh README introduction"
```
