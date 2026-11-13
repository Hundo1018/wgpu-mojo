#!/bin/bash
# Build the web examples to build/web/<app>.wasm (wasm64) (#15, #16).
#
#   mojo build -D WGPU_TARGET=web --emit llvm   host-lowered IR
#   scripts/wasm_retarget.py ... wasm64         triple + datalayout for llc
#   llc, clang (ffi/wasm/wasm_rt.c), wasm-ld    one module; every wgpu* stays an import
# Settings come from wasm.toml. llc and wasm-ld share an LLVM major, so they run
# from a pinned `pixi exec` environment, outside the default one.
set -euo pipefail
cd "$(dirname "$0")/.."

LLVM=$(sed -n 's/^llvm *= *"\(.*\)".*/\1/p' wasm.toml)
TOOLS=(pixi exec --spec "llvm-tools=$LLVM" --spec "lld=$LLVM" --spec "clang=$LLVM" --spec nodejs=24 --)
OUT=build/web
mkdir -p "$OUT"
APPS=("$@")
[ ${#APPS[@]} -gt 0 ] || APPS=(triangle compute texture)

"${TOOLS[@]}" clang --target=wasm64-unknown-unknown -O2 -nostdlib -ffreestanding -fno-builtin -mbulk-memory \
  -c ffi/wasm/wasm_rt.c -o "$OUT/wasm_rt.o"

for app in "${APPS[@]}"; do
  src="examples/web/${app}_web.mojo"
  mojo build -D WGPU_TARGET=web --emit llvm -I . -I examples/web -o "$OUT/$app.host.ll" "$src"
  python3 -I scripts/wasm_retarget.py "$OUT/$app.host.ll" "$OUT/$app.ll" wasm64
  exports=$(grep -A1 '^@export' "$src" | grep -oE '^def [a-z_0-9]+' | sed 's/def /--export=/' | tr '\n' ' ')
  "${TOOLS[@]}" bash -c "
    set -euo pipefail
    llc -O2 -mtriple=wasm64-unknown-unknown -mattr=+tail-call,+bulk-memory,+sign-ext,+mutable-globals \
        -filetype=obj -o $OUT/$app.o $OUT/$app.ll
    wasm-ld --fatal-warnings -mwasm64 --no-entry --export-memory --export-table --allow-undefined -z stack-size=1048576 \
        --export=mw_alloc --export=mw_free $exports -o $OUT/$app.wasm $OUT/$app.o $OUT/wasm_rt.o
    llvm-nm -u $OUT/$app.o | awk '{print \$2}' | grep -v '^wgpu' | grep -vxE '__indirect_function_table|__stack_pointer' \
        | grep -vxE 'KGEN_.*|dup|fclose|fdopen|fflush|write' > $OUT/$app.undefined || true
  "
  if [ -s "$OUT/$app.undefined" ]; then
    echo "build-web: $app: undefined symbols outside wgpu*:" >&2; cat "$OUT/$app.undefined" >&2; exit 1
  fi
  echo "build-web: $OUT/$app.wasm ($(stat -c %s "$OUT/$app.wasm") bytes)"
done
cp web/*.html web/*.mjs web/*.json scripts/webgpu_enum_strings.json "$OUT/"
# The shared JS runtime (ludens-wasm-rt) comes from the optional pixi `wasm` environment.
cp "$(pixi run -e wasm python3 -c 'import ludens_wasm_rt; print(ludens_wasm_rt.HOST_MJS)')" "$OUT/host.mjs"
