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

echo ""
echo "check-symbols: ALL PASSED ($EXPECTED_N/$EXPECTED_N resolve)"
