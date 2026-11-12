#!/usr/bin/env bash
# Rebuild the Matrix-owned Godzilla payload engines in data/godzilla/.
#
# Requirements:
#   - javac (JDK 8+) for the JSP engine
#   - base64
#   - optional: csc or mcs for the ASPX engine (skipped when absent)
#
# The PHP and ASP engines are source-only and need no compiler.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC="$ROOT/tool/godzilla_engine"
OUT="$ROOT/data/godzilla"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$OUT"

header() { printf '# Matrix-owned Godzilla %s engine (source: tool/godzilla_engine/%s)\n' "$1" "$2"; }

# ── PHP ──────────────────────────────────────────────────────────────────
echo "[1/4] PHP engine"
python3 - "$SRC/matrix_godzilla.php" "$OUT/matrix_godzilla.php.b64" <<'PY'
import base64, pathlib, sys
src = pathlib.Path(sys.argv[1]).read_text()
body = src[len('<?php'):].lstrip('\n') if src.startswith('<?php') else src
out = pathlib.Path(sys.argv[2])
out.write_text('# Matrix-owned Godzilla PHP engine (source: tool/godzilla_engine/matrix_godzilla.php)\n'
               + base64.b64encode(body.encode()).decode() + '\n')
print('      %d bytes -> %s' % (len(body.encode()), out.name))
PY

# ── JSP ──────────────────────────────────────────────────────────────────
echo "[2/4] JSP engine"
javac --release 8 -d "$TMP" "$SRC/MatrixGodzillaEngine.java"
if [ ! -f "$TMP/MatrixGodzillaEngine.class" ]; then
  echo "      ERROR: compile produced no class file" >&2
  exit 1
fi
if ls "$TMP"/MatrixGodzillaEngine\$*.class >/dev/null 2>&1; then
  echo "      ERROR: engine produced nested classes; the standard JSP shell" >&2
  echo "             only defineClass()es a single class." >&2
  exit 1
fi
{ header JSP MatrixGodzillaEngine.java; base64 < "$TMP/MatrixGodzillaEngine.class"; } \
  > "$OUT/matrix_godzilla.class.b64"
echo "      $(stat -f%z "$TMP/MatrixGodzillaEngine.class" 2>/dev/null || stat -c%s "$TMP/MatrixGodzillaEngine.class") bytes"

# ── ASP ──────────────────────────────────────────────────────────────────
echo "[3/4] ASP engine"
{ header ASP matrix_godzilla.asp; base64 < "$SRC/matrix_godzilla.asp"; } \
  > "$OUT/matrix_godzilla.asp.b64"
echo "      $(wc -c < "$SRC/matrix_godzilla.asp" | tr -d ' ') bytes"

# ── ASPX ─────────────────────────────────────────────────────────────────
echo "[4/4] ASPX engine"
CSC=""
if command -v csc >/dev/null 2>&1; then CSC="csc"; fi
if [ -z "$CSC" ] && command -v mcs >/dev/null 2>&1; then CSC="mcs"; fi
if [ -n "$CSC" ]; then
  "$CSC" -target:library -out:"$TMP/matrix_godzilla.dll" "$SRC/MatrixGodzillaEngine.cs"
  { header ASPX MatrixGodzillaEngine.cs; base64 < "$TMP/matrix_godzilla.dll"; } \
    > "$OUT/matrix_godzilla.dll.b64"
  echo "      built with $CSC"
else
  echo "      SKIPPED: no csc/mcs on PATH."
  echo "      The ASPX connector still works against sessions already seeded by"
  echo "      a regular Godzilla client; fresh sessions need the DLL."
fi

echo
echo "Done. Assets in $OUT:"
ls -1 "$OUT"
