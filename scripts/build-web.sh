#!/bin/bash
# Build the web examples (#14) to build/web/<app>.{mjs,wasm} plus the host page.
#
# Route (measured; see the web-target notes in README):
#   mojo build -D WGPU_TARGET=web --emit llvm   host-lowered IR, wasm-safe ABI
#   scripts/wasm_retarget.py ... emscripten     triple + datalayout for emcc
#   emcc -sMEMORY64 -c                          wasm64 object
#   em++ --use-port=emdawnwebgpu                link; emdawnwebgpu is C++
# A wasm-ld signature-mismatch warning means a call's C ABI disagrees with the
# header (the by-value WGPUStringView trap), so it fails the build.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/web-env.sh
[ -x "$EMCC" ] || { echo "build-web: no emcc at $EMCC; run 'pixi run setup-emsdk'" >&2; exit 1; }

OUT=build/web
mkdir -p "$OUT"
APPS=("$@")
[ ${#APPS[@]} -gt 0 ] || APPS=(triangle compute)

"$EMCC" -O2 -sMEMORY64=1 -c ffi/wasm/kgen_em.c -o "$OUT/kgen_em.o" 2> /dev/null

for app in "${APPS[@]}"; do
  src="examples/web/${app}_web.mojo"
  mojo build -D WGPU_TARGET=web --emit llvm -I . -I examples/web -o "$OUT/$app.ll" "$src"
  python3 -I scripts/wasm_retarget.py "$OUT/$app.ll" "$OUT/${app}_em.ll" emscripten 2> /dev/null
  "$EMCC" -O2 -sMEMORY64=1 -c "$OUT/${app}_em.ll" -o "$OUT/$app.o" 2>&1 | grep -v "MEMORY64 is deprecated" || true
  exports=$(grep -A1 '^@export' "$src" | grep -oE '^def [a-z_0-9]+' | sed 's/def /_/' | paste -sd, -)
  "$EMXX" -O2 -sMEMORY64=1 --use-port=emdawnwebgpu \
    -sMODULARIZE=1 -sEXPORT_ES6=1 -sENVIRONMENT=web -sALLOW_MEMORY_GROWTH=1 \
    -sEXPORTED_FUNCTIONS="$exports" -sEXPORTED_RUNTIME_METHODS=HEAPU8,stringToNewUTF8,lengthBytesUTF8 \
    "$OUT/$app.o" "$OUT/kgen_em.o" -o "$OUT/$app.mjs" > "$OUT/$app.link.log" 2>&1 \
    || { cat "$OUT/$app.link.log" >&2; exit 1; }
  if grep -qi "signature mismatch" "$OUT/$app.link.log"; then
    grep -i "signature mismatch" "$OUT/$app.link.log" >&2
    echo "build-web: $app: C ABI mismatch against the browser's webgpu.h" >&2
    exit 1
  fi
  echo "build-web: $OUT/$app.wasm ($(stat -c %s "$OUT/$app.wasm") bytes)"
done
cp web/*.html web/*.mjs "$OUT/"
