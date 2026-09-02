#!/bin/bash
# Compile-check all tests (excluding intentional-fail abi_probes) and examples.
# No GPU or libwgpu_native.so required — catches API drift at compile time.
set -euo pipefail
cd "$(dirname "$0")/.."

FILES=(
  tests/test_types.mojo
  tests/test_alloc_guard.mojo
  tests/test_handle_newtypes.mojo
  tests/test_lifetimes_string_view.mojo
  tests/test_structs.mojo
  tests/test_native_ext.mojo
  tests/test_callback_abi.mojo
  tests/test_gpu_compile.mojo
  tests/test_instance.mojo
  tests/test_device.mojo
  tests/test_buffer.mojo
  tests/test_shader.mojo
  tests/test_bind_group.mojo
  tests/test_compute_pipeline.mojo
  tests/test_render_pipeline.mojo
  tests/test_texture.mojo
  tests/test_texture_sample.mojo
  tests/test_sampler.mojo
  tests/test_command_encoder.mojo
  tests/test_pipeline_layout.mojo
  tests/test_query_set.mojo
  tests/test_debug_groups.mojo
  tests/test_preflight.mojo
  tests/test_error_scope.mojo
  tests/test_render_bundle.mojo
  tests/test_add_ref.mojo
  tests/test_spirv.mojo
  tests/test_log_bridge.mojo
  examples/enumerate_adapters.mojo
  examples/compute_add.mojo
  examples/compute_add_v2.mojo
  examples/clear_screen.mojo
  examples/triangle_window.mojo
  examples/fire_simulation.mojo
  examples/plasma.mojo
  examples/metaballs.mojo
  examples/raymarch.mojo
  tools/render_shader_gif.mojo
  examples/texture_sample.mojo
  examples/input_demo.mojo
  examples/native_extensions.mojo
  hello.mojo
)

FAILED=0
for f in "${FILES[@]}"; do
  printf "  check %-50s" "$f"
  if mojo build -I . "$f" -o /dev/null 2>/tmp/cc_err; then
    echo "OK"
  else
    echo "FAIL"
    cat /tmp/cc_err | grep "error:" | head -3 | sed 's/^/    /'
    FAILED=$((FAILED + 1))
  fi
done

if [ "$FAILED" -gt 0 ]; then
  echo ""
  echo "check-compile: $FAILED file(s) FAILED"
  exit 1
fi

# ---------------------------------------------------------------------------
# Build the whole package, the way the conda recipe and `Consume path` CI do.
#
# Compiling the files above is NOT equivalent: Mojo only fully checks `def`
# bodies that are referenced, and nothing in the list above reaches wgpu/_core/,
# so that subtree went entirely unchecked. A trait left with an empty body after
# a removal compiled fine here and broke the packaged build — caught by CI, not
# by this script. Building the package closes that gap.
#
# Warnings are failures: they were invisible before this step existed, which is
# how 31 of them accumulated unnoticed.
# ---------------------------------------------------------------------------
echo ""
printf "  %-56s" "package wgpu (full-tree compile)"
PKG_LOG=$(mktemp)
PKG_OUT=$(mktemp -d)/wgpu.mojopkg
if ! mojo package wgpu -o "$PKG_OUT" -I . 2>"$PKG_LOG"; then
  echo "FAIL"
  grep -E " error:" "$PKG_LOG" | head -10 | sed 's/^/    /'
  rm -f "$PKG_LOG"
  echo ""
  echo "check-compile: package build FAILED"
  exit 1
fi
# Only source-level warnings count; `mojo package`/.mojopkg are deprecated at
# the CLI level, which is the recipe's business, not this tree's.
PKG_WARN=$(grep -cE "^[[:alnum:]_/.-]+\.mojo:[0-9]+:[0-9]+: warning:" "$PKG_LOG" || true)
if [ "$PKG_WARN" -gt 0 ]; then
  echo "WARN"
  grep -E "^[[:alnum:]_/.-]+\.mojo:[0-9]+:[0-9]+: warning:" "$PKG_LOG" | head -12 | sed 's/^/    /'
  rm -f "$PKG_LOG"
  echo ""
  echo "check-compile: $PKG_WARN source warning(s) in the packaged build"
  exit 1
fi
rm -f "$PKG_LOG" "$PKG_OUT"
echo "OK"

echo ""
echo "check-compile: ALL PASSED"
