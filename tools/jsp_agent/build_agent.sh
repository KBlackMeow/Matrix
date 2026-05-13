#!/usr/bin/env bash
# 编译 M.java → M.class → 单行 Base64 → ../../data/jsp_agent_M.b64
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
OUT="$SCRIPT_DIR/../../data/jsp_agent_M.b64"
JAVAC="${JAVA_HOME:-}/bin/javac"
[[ -x "$JAVAC" ]] || JAVAC="/Library/Java/JavaVirtualMachines/jdk-1.8.jdk/Contents/Home/bin/javac"
[[ -x "$JAVAC" ]] || JAVAC="javac"
"$JAVAC" -source 8 -target 8 M.java
base64 < M.class | tr -d '\r\n' >"$OUT"
echo "OK $OUT ($(wc -c <"$OUT" | tr -d ' ') bytes)"
echo "Then: flutter clean && flutter pub get && flutter run"
