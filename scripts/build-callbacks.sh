#!/bin/bash
# Build the C callback bridges from the working tree.
#
# Why this is a script and not a one-liner: scripts/setup-native.sh compiles the
# bridge from the *published* ffi/wgpu_callbacks.c and installs it into
# $CONDA_PREFIX/lib. loader.mojo's three-stage lookup can resolve that copy
# before ffi/lib, so after editing the bridge locally you would keep running the
# stale one — the symptom is "symbol not found: wgpu_mojo_*" at runtime, or
# worse, silently old behaviour. So: if a copy exists in the environment, this
# refreshes it too, and the two cannot drift apart.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p ffi/lib

gcc -shared -fPIC -o ffi/lib/libwgpu_mojo_cb.so ffi/wgpu_callbacks.c \
    -Iffi/include -Lffi/lib -L"$CONDA_PREFIX/lib" -lwgpu_native \
    -Wl,-rpath,'$ORIGIN' -Wl,-rpath,"$CONDA_PREFIX/lib"

gcc -shared -fPIC -o ffi/lib/libglfw_input_cb.so \
    rendercanvas-mojo/ffi/glfw_input_callbacks.c \
    -L"$CONDA_PREFIX/lib" -lglfw \
    -Wl,-rpath,'$ORIGIN' -Wl,-rpath,"$CONDA_PREFIX/lib"

for lib in libwgpu_mojo_cb.so libglfw_input_cb.so; do
  if [ -n "${CONDA_PREFIX:-}" ] && [ -f "$CONDA_PREFIX/lib/$lib" ]; then
    cp "ffi/lib/$lib" "$CONDA_PREFIX/lib/$lib"
    echo "  refreshed shadowing copy: \$CONDA_PREFIX/lib/$lib"
  fi
done
