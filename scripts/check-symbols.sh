#!/bin/bash
# Verify that every wgpu-native symbol this binding resolves is actually
# exported by the libwgpu_native we build against.
#
# Why this exists: FFI symbols are resolved lazily at each call site, so a
# binding naming a symbol upstream has renamed compiles cleanly and only fails
# when that code path first runs. `check-compile` cannot see it, and a symbol
# with no test coverage stays green forever. wgpu-native v29 renamed the
# push-constant entry points to *SetImmediates exactly this way.
#
# Needs no GPU and no display — only the shared library.
set -euo pipefail
cd "$(dirname "$0")/.."

case "$(uname -s)" in
  Darwin) DEFAULT_LIB="ffi/lib/libwgpu_native.dylib" ;;
  *)      DEFAULT_LIB="ffi/lib/libwgpu_native.so" ;;
esac
LIB="${WGPU_NATIVE_LIB:-$DEFAULT_LIB}"

if [ ! -f "$LIB" ]; then
  if [ -n "${CONDA_PREFIX:-}" ] && [ -f "$CONDA_PREFIX/lib/$(basename "$LIB")" ]; then
    LIB="$CONDA_PREFIX/lib/$(basename "$LIB")"
  else
    echo "check-symbols: library not found: $LIB" >&2
    echo "  Run scripts/setup-native.sh first, or set WGPU_NATIVE_LIB." >&2
    exit 1
  fi
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Symbols the binding expects:
#   - Mojo resolves them by string literal, e.g. self._wgpu.call["wgpuXxx"]
#   - the C bridge calls them directly, e.g. wgpuXxx(...)
# The `wgpu[A-Z]` shape matches the C API only: it skips WGPU* type names and
# the bridge's own wgpu_mojo_* exports.
grep -rhoE '"wgpu[A-Z][A-Za-z0-9_]*"' wgpu/ wgpu_max/ 2>/dev/null \
  | tr -d '"' > "$TMP/expected.raw"
grep -ohE '\bwgpu[A-Z][A-Za-z0-9_]*[[:space:]]*\(' ffi/*.c 2>/dev/null \
  | sed 's/[[:space:]]*($//; s/($//' | tr -d '(' >> "$TMP/expected.raw"
sort -u "$TMP/expected.raw" > "$TMP/expected"

# Symbols the library actually exports (macOS nm prefixes a leading underscore).
if [ "$(uname -s)" = "Darwin" ]; then
  nm -gU "$LIB" 2>/dev/null | awk '{print $NF}' | sed 's/^_//'
else
  nm -D --defined-only "$LIB" 2>/dev/null | awk '{print $NF}'
fi | grep -oE '^wgpu[A-Z][A-Za-z0-9_]*$' | sort -u > "$TMP/exported"

comm -23 "$TMP/expected" "$TMP/exported" > "$TMP/missing"

EXPECTED_N=$(wc -l < "$TMP/expected" | tr -d ' ')
EXPORTED_N=$(wc -l < "$TMP/exported" | tr -d ' ')
MISSING_N=$(wc -l < "$TMP/missing" | tr -d ' ')

echo "check-symbols: $LIB"
echo "  symbols exported by library : $EXPORTED_N"
echo "  symbols resolved by binding : $EXPECTED_N"

if [ "$MISSING_N" -gt 0 ]; then
  echo ""
  echo "  $MISSING_N symbol(s) resolved by the binding are NOT exported:"
  sed 's/^/    - /' "$TMP/missing"
  echo ""
  echo "check-symbols: FAILED — these call sites would fail at runtime."
  echo "  Either the library is the wrong version, or upstream renamed them."
  exit 1
fi

# ---------------------------------------------------------------------------
# Second check: symbols that resolve but are unimplemented stubs.
#
# wgpu-native exports `unimplemented!()` stubs for parts of webgpu.h it has not
# built yet. They link fine, so the resolution check above cannot see them —
# but calling one panics in Rust across the FFI boundary and *aborts the
# process*. A binding that names one is a landmine with no Mojo-level error.
#
# Two shapes, detected two ways:
#   named   — unimplemented!("wgpuX is not implemented"), found via `strings`
#   generic — bare unimplemented!(), a tiny body hitting `ud2` early
# ---------------------------------------------------------------------------

if ! command -v objdump >/dev/null 2>&1; then
  echo ""
  echo "  note: objdump not found, skipping the unimplemented-stub check"
  echo ""
  echo "check-symbols: ALL PASSED ($EXPECTED_N/$EXPECTED_N resolve)"
  exit 0
fi

strings -a "$LIB" 2>/dev/null \
  | grep -oE 'wgpu[A-Za-z0-9_]+ is not implemented' \
  | sed 's/ is not implemented//' > "$TMP/unimpl.raw"

objdump -d "$LIB" 2>/dev/null | awk '
  /^[0-9a-f]+ <.*>:$/ { if (sym != "" && ud) print sym; sym=$2; gsub(/[<>:]/,"",sym); n=0; ud=0; next }
  /^ *[0-9a-f]+:/     { n++; if ($0 ~ /ud2/ && n <= 10) ud=1 }
  END                 { if (sym != "" && ud) print sym }
' | grep -E '^wgpu[A-Z]' >> "$TMP/unimpl.raw"

sort -u "$TMP/unimpl.raw" > "$TMP/unimpl"
comm -12 "$TMP/expected" "$TMP/unimpl" > "$TMP/bound_unimpl"

ALLOW="scripts/known-unimplemented.txt"
if [ -f "$ALLOW" ]; then
  grep -vE '^[[:space:]]*(#|$)' "$ALLOW" | awk '{print $1}' | sort -u > "$TMP/allow"
else
  : > "$TMP/allow"
fi

comm -23 "$TMP/bound_unimpl" "$TMP/allow" > "$TMP/new_unimpl"
KNOWN_N=$(wc -l < "$TMP/bound_unimpl" | tr -d ' ')
NEW_N=$(wc -l < "$TMP/new_unimpl" | tr -d ' ')

echo "  unimplemented stubs in library: $(wc -l < "$TMP/unimpl" | tr -d ' ')"
echo "  ...of those, bound here       : $KNOWN_N ($ALLOW records them)"

if [ "$NEW_N" -gt 0 ]; then
  echo ""
  echo "  $NEW_N newly-bound symbol(s) are unimplemented stubs:"
  sed 's/^/    - /' "$TMP/new_unimpl"
  echo ""
  echo "check-symbols: FAILED — calling any of these aborts the process."
  echo "  Remove the binding, or add it to $ALLOW with a reason if it is"
  echo "  bound deliberately and guarded from callers."
  exit 1
fi

echo ""
echo "check-symbols: ALL PASSED ($EXPECTED_N/$EXPECTED_N resolve)"
