#!/bin/bash
# Build the web examples to build/web/<app>.ll: wasm64 IR for the shared wasm-ld
# toolchain (#15; linking and the JS translation layer are #16/#17).
#
#   mojo build -D WGPU_TARGET=web --emit llvm   host-lowered IR
#   scripts/wasm_retarget.py ... wasm64         triple + datalayout for llc
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=build/web
mkdir -p "$OUT"
APPS=("$@")
[ ${#APPS[@]} -gt 0 ] || APPS=(triangle compute)

for app in "${APPS[@]}"; do
  mojo build -D WGPU_TARGET=web --emit llvm -I . -I examples/web -o "$OUT/$app.host.ll" "examples/web/${app}_web.mojo"
  python3 -I scripts/wasm_retarget.py "$OUT/$app.host.ll" "$OUT/$app.ll" wasm64
  echo "build-web: $OUT/$app.ll ($(stat -c %s "$OUT/$app.ll") bytes)"
done
