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
echo ""
echo "check-compile: ALL PASSED"
