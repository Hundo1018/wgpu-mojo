#!/bin/bash
# Compile-check the opt-in wgpu_max bridge (package + its test and example).
#
# `mojo precompile wgpu` is the whole-package backstop for the core library, but
# it deliberately does not reach wgpu_max -- that separation is the entire point
# of the opt-in design. This script is wgpu_max's equivalent backstop:
# `mojo precompile` compiles every method, including ones no test happens to call.
#
# Warnings are failures here for the same reason they are in check-compile.sh:
# without that rule they accumulate unnoticed. (Four had, by the time this gate
# was added.) Only source-level warnings count -- a bare CLI-level warning is the
# recipe's business, not this tree's.
#
# Run via: pixi run -e maxinterop check-compile-max
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=$(mktemp -d)
LOG=$(mktemp)
trap 'rm -rf "${OUT}" "${LOG}"' EXIT

# Absolute paths appear in `mojo build` diagnostics, relative ones in precompile's.
SRC_WARN='^[[:alnum:]_/.-]+\.mojo:[0-9]+:[0-9]+: warning:'

# run_step <label> <cmd...> -- fails on a non-zero exit or any source warning.
run_step() {
    local label="$1"; shift
    printf '  %-52s' "${label}"
    if ! "$@" 2>"${LOG}"; then
        echo "FAIL"
        grep -E ' error:' "${LOG}" | head -10 | sed 's/^/    /'
        echo ""
        echo "check-compile-max: ${label} FAILED"
        exit 1
    fi
    local n
    n=$(grep -cE "${SRC_WARN}" "${LOG}" || true)
    if [ "${n}" -gt 0 ]; then
        echo "WARN"
        grep -E "${SRC_WARN}" "${LOG}" | head -12 | sed 's/^/    /'
        echo ""
        echo "check-compile-max: ${n} source warning(s) in ${label}"
        exit 1
    fi
    echo "OK"
}

run_step "precompile wgpu_max" \
    mojo precompile wgpu_max -I . -o "${OUT}/wgpu_max.mojoc"

for f in tests/test_max_interop.mojo examples/max_interop.mojo; do
    run_step "check ${f}" \
        mojo build -I . "${f}" -o "${OUT}/$(basename "${f}" .mojo)"
done

echo ""
echo "check-compile-max: ALL PASSED"
