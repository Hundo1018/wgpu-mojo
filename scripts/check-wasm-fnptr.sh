#!/bin/bash
# Pin what `c_fn_ptr` yields on a wasm64 build (issue #13, request item 3),
# and that the web target's callbacks match clang's wasm C ABI (#14).
#
# Route (measured in ludens-engine tools/wasm/poc/FINDINGS.md): Mojo host IR ->
# scripts/wasm_retarget.py -> llc -> wasm-ld -mwasm64, then run under node.
# llc and wasm-ld must share an LLVM major, and Node >= 24 is needed for
# table64, so the tools come from `pixi exec`, pinned, and not from the default env.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=build/wasm
mkdir -p "$OUT"
TOOLS=(pixi exec --spec llvm-tools=23.1.4 --spec lld=23.1.4 --spec clang=23.1.4 --spec nodejs=24 --)

# Twice: a host build pins the by-value WGPUStringView mismatch, the web build
# (-D WGPU_TARGET=web, #14) shows the pointer-taking callback matching clang.
for mode in host web; do
  flags=()
  [ "$mode" = web ] && flags=(-D WGPU_TARGET=web)
  echo "== $mode build"
  pixi run mojo build "${flags[@]}" --emit llvm -I . -o "$OUT/fnptr_$mode.ll" tests/wasm/fnptr_probe.mojo
  "${TOOLS[@]}" bash -c "
    set -euo pipefail
    python3 -I scripts/wasm_retarget.py $OUT/fnptr_$mode.ll $OUT/fnptr_${mode}_w64.ll wasm64
    llc -O2 -mtriple=wasm64-unknown-unknown -mattr=+tail-call,+bulk-memory,+sign-ext,+mutable-globals \
        -filetype=obj -o $OUT/fnptr_$mode.o $OUT/fnptr_${mode}_w64.ll
    clang --target=wasm64-unknown-unknown -O2 -nostdlib -ffreestanding \
        -c -o $OUT/fnptr_caller.o tests/wasm/fnptr_caller.c
    wasm-ld -mwasm64 --no-entry --export-table --allow-undefined \
        --export=fnptr_add1 --export=fnptr_buffer_map_callback \
        -o $OUT/fnptr_$mode.wasm $OUT/fnptr_$mode.o $OUT/fnptr_caller.o
    node tests/wasm/fnptr_probe.mjs $OUT/fnptr_$mode.wasm $mode
  "
done
