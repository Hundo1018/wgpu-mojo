#!/bin/bash
# Compile-check the opt-in wgpu_max bridge (package + its test and example).
#
# `mojo package wgpu` is the whole-package backstop for the core library, but it
# deliberately does not reach wgpu_max -- that separation is the entire point of
# the opt-in design. This script is wgpu_max's equivalent backstop: `mojo package`
# compiles every method, including ones no test happens to call.
#
# Run via: pixi run -e maxinterop check-compile-max
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=$(mktemp -d)
trap 'rm -rf "${OUT}"' EXIT

printf '  %-52s' "package wgpu_max"
mojo package wgpu_max -I . -o "${OUT}/wgpu_max.mojopkg"
echo "OK"

for f in tests/test_max_interop.mojo examples/max_interop.mojo; do
    printf '  %-52s' "check ${f}"
    mojo build -I . "${f}" -o "${OUT}/$(basename "${f}" .mojo)"
    echo "OK"
done

echo ""
echo "check-compile-max: ALL PASSED"
