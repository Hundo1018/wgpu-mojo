#!/bin/bash
# Build and run tests with -D WGPU_LINK=static (issue #13).
#
# Static mode turns every wgpu call into an external_call, so the binary links
# libwgpu_native (and the log bridge archive) at build time instead of
# dlopen'ing them. `mojo run` cannot resolve those symbols in its JIT, so each
# test is built with `mojo build` and then executed.
#
#   scripts/test-static.sh --non-gpu        the `pixi run test` set
#   scripts/test-static.sh --gpu            every GPU test (needs an adapter)
#   scripts/test-static.sh tests/a.mojo...  explicit files
set -euo pipefail
cd "$(dirname "$0")/.."

NON_GPU=(
  tests/test_types.mojo tests/test_alloc_guard.mojo tests/test_handle_newtypes.mojo
  tests/test_lifetimes_string_view.mojo tests/test_structs.mojo
  tests/test_native_ext.mojo tests/test_callback_abi.mojo
)
GPU=(
  tests/test_instance.mojo tests/test_device.mojo tests/test_buffer.mojo
  tests/test_shader.mojo tests/test_bind_group.mojo tests/test_compute_pipeline.mojo
  tests/test_texture.mojo tests/test_texture_sample.mojo tests/test_sampler.mojo
  tests/test_command_encoder.mojo tests/test_pipeline_layout.mojo
  tests/test_error_scope.mojo tests/test_preflight.mojo tests/test_add_ref.mojo
  tests/test_spirv.mojo tests/test_log_bridge.mojo tests/test_debug_groups.mojo
  tests/test_query_set.mojo tests/test_render_pipeline.mojo
  tests/test_gpu_compile.mojo tests/test_render_bundle.mojo
  tests/test_native_v29_0_1.mojo tests/test_async.mojo tests/test_capture.mojo
)

case "${1:-}" in
  --non-gpu) FILES=("${NON_GPU[@]}") ;;
  --gpu)     FILES=("${GPU[@]}") ;;
  "")        echo "usage: $0 --non-gpu | --gpu | FILE..." >&2; exit 2 ;;
  *)         FILES=("$@") ;;
esac

PREFIX="${CONDA_PREFIX:?run through pixi}"
# Full path to the archive (not -l:), so the line also works with macOS ld.
CB_ARCHIVE="$PWD/ffi/lib/libwgpu_mojo_cb.a"
[ -f "$CB_ARCHIVE" ] || { echo "missing $CB_ARCHIVE; run: pixi run build-callbacks" >&2; exit 1; }
LINK=(
  -Xlinker "$CB_ARCHIVE"
  -Xlinker "-L$PREFIX/lib" -Xlinker "-L$PWD/ffi/lib" -Xlinker -lwgpu_native
  -Xlinker -rpath -Xlinker "$PREFIX/lib" -Xlinker -rpath -Xlinker "$PWD/ffi/lib"
)

OUT=build/static
mkdir -p "$OUT"
pass=0; fail=0; failed=()
for f in "${FILES[@]}"; do
  bin="$OUT/$(basename "$f" .mojo)"
  log="$bin.log"
  if ! mojo build -D WGPU_LINK=static -I . "${LINK[@]}" -o "$bin" "$f" >"$log" 2>&1; then
    echo "BUILD FAIL $f (log: $log)"; tail -5 "$log"; fail=$((fail+1)); failed+=("$f"); continue
  fi
  if "$bin" >"$log" 2>&1; then
    echo "PASS $f"; pass=$((pass+1))
  else
    echo "FAIL $f (log: $log)"; tail -8 "$log"; fail=$((fail+1)); failed+=("$f")
  fi
done
echo "static mode: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
