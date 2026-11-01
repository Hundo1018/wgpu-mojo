# Sourced by the web build scripts (#14). Pins the browser toolchain and points
# emcc at it. The emdawnwebgpu port version is fixed by the Emscripten release,
# and its webgpu.h is part of the ABI contract the same way wgpu-native's is:
# `pixi run check-web-struct-layout` compares it against structs.mojo.
EMSCRIPTEN_VERSION=6.0.13
EMDAWNWEBGPU_VERSION=v20260423.175430

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export EMSDK_DIR="${EMSDK_DIR:-$ROOT/build/emsdk}"
export EM_CACHE="${EM_CACHE:-$ROOT/build/em-cache}"
export EM_CONFIG="$EMSDK_DIR/.emscripten"
# emcc needs Python >= 3.10; the pixi env's python3 qualifies, an older one
# earlier on PATH (micromamba's 3.9 here) does not.
export EMSDK_PYTHON="${EMSDK_PYTHON:-$(command -v python3)}"
EMCC="$EMSDK_DIR/upstream/emscripten/emcc"
EMXX="$EMSDK_DIR/upstream/emscripten/em++"
DAWN_INCLUDE="$EM_CACHE/ports/emdawnwebgpu/emdawnwebgpu_pkg/webgpu/include"
