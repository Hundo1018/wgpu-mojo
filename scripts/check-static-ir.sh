#!/bin/bash
# Static link mode (-D WGPU_LINK=static, issue #13) must leave the wgpu calls as
# plain `declare`s in the IR (wasm imports, or link-time symbols natively) and
# no dlopen path at all. Uses a headless example: the GLFW canvas still
# dlopens GLFW by design, so it is out of scope here.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC=${1:-examples/compute_add.mojo}
mkdir -p build/static
IR=build/static/$(basename "$SRC" .mojo).ll
mojo build -D WGPU_LINK=static --emit llvm -I . -o "$IR" "$SRC"

declares=$(grep -cE '^declare .*@wgpu' "$IR" || true)
dl_hits=$(grep -cE 'dlopen|dlsym|dlclose|OwnedDLHandle' "$IR" || true)
echo "static IR ($SRC): $declares wgpu declares, $dl_hits dlopen/dlsym/dlclose/OwnedDLHandle references"
grep -E '^declare .*@wgpu' "$IR" | sed -E 's/.*@(wgpu[A-Za-z0-9_]+).*/  \1/' | sort -u | head -50
if [ "$declares" -eq 0 ]; then echo "FAIL: no wgpu declares" >&2; exit 1; fi
if [ "$dl_hits" -ne 0 ]; then
  grep -nE 'dlopen|dlsym|dlclose|OwnedDLHandle' "$IR" | head -5 >&2
  echo "FAIL: static IR still references the dynamic loader" >&2; exit 1
fi
