#!/usr/bin/env bash
# conda.recipe/build.sh — build the wgpu-mojo conda package.
#
# Runs inside rattler-build with $PREFIX pointing at the host environment, so
# `wgpu-native` and `glfw` (declared as host dependencies) are already installed
# there. Nothing is downloaded here: the previous revision of this recipe
# curl'd a prebuilt libwgpu_native from GitHub Releases, which made the build
# non-reproducible and left the resulting package unable to declare what ABI it
# actually contained.
#
# Produces, all into $PREFIX:
#   lib/mojo/wgpu.mojoc     the compiled Mojo package
#   lib/libwgpu_mojo_cb.*   the C callback bridge (wgpu-native async APIs)
#   lib/libglfw_input_cb.*  the GLFW keyboard/mouse bridge (RenderCanvas)
set -euo pipefail

case "$(uname -s)" in
    Linux)
        LIB_EXT="so"
        RPATH_FLAGS=(-Wl,-rpath,'$ORIGIN')
        ;;
    Darwin)
        LIB_EXT="dylib"
        RPATH_FLAGS=(-Wl,-rpath,@loader_path)
        ;;
    *)
        echo "conda.recipe/build.sh: unsupported platform $(uname -s)" >&2
        exit 1
        ;;
esac

CC_BIN="${CC:-gcc}"

# ---------------------------------------------------------------------------
# ABI guard: the wgpu-native we link against must be the one we are pinned to
# ---------------------------------------------------------------------------
# wgpu-native renumbered the entire 0x0003xxxx SType enum in the v29.0.0.0 ->
# v29.0.1.1 *patch* release. A mismatched library still loads and still runs --
# it just misreads every extras chain. The version constraint in recipe.yaml is
# the first line of defence; this is the second, and it compares the actual
# header bytes rather than trusting a version string.
#
# ffi/include/webgpu/wgpu.h is the pinned copy vendored in this repo;
# $PREFIX/include/wgpu.h is the one shipped by the conda-forge wgpu-native
# package we just installed. For the pinned version these are byte-identical.
PINNED_HEADER="ffi/include/webgpu/wgpu.h"
INSTALLED_HEADER="$PREFIX/include/wgpu.h"

if [ ! -f "$INSTALLED_HEADER" ]; then
    echo "Error: $INSTALLED_HEADER is missing." >&2
    echo "The wgpu-native host dependency did not install its header." >&2
    exit 1
fi

if ! cmp -s "$PINNED_HEADER" "$INSTALLED_HEADER"; then
    echo "Error: wgpu-native ABI mismatch." >&2
    echo "  pinned    : $PINNED_HEADER" >&2
    echo "  installed : $INSTALLED_HEADER" >&2
    echo "" >&2
    echo "The installed wgpu-native is not the revision this binding's SType and" >&2
    echo "feature constants were written against. Bump the wgpu_native_version in" >&2
    echo "recipe.yaml and ffi/wgpu-native-meta/wgpu-native-git-tag together, and" >&2
    echo "re-vendor ffi/include/webgpu/*.h, before building." >&2
    diff "$PINNED_HEADER" "$INSTALLED_HEADER" | head -20 >&2 || true
    exit 1
fi
echo "==> wgpu-native ABI guard: pinned header matches the installed package"

# ---------------------------------------------------------------------------
# C callback bridge — wgpu-native's async APIs need real C function pointers
# ---------------------------------------------------------------------------
# ffi/wgpu_callbacks.c includes "include/webgpu/webgpu.h" relative to its own
# directory, so it compiles against the vendored headers checked above. Only
# the link target comes from $PREFIX.
echo "==> Building libwgpu_mojo_cb.${LIB_EXT}"
mkdir -p ffi/lib
"$CC_BIN" -shared -fPIC \
    -o "ffi/lib/libwgpu_mojo_cb.${LIB_EXT}" \
    ffi/wgpu_callbacks.c \
    -L"$PREFIX/lib" -lwgpu_native \
    "${RPATH_FLAGS[@]}"

# ---------------------------------------------------------------------------
# GLFW input bridge — needed by wgpu.rendercanvas.RenderCanvas
# ---------------------------------------------------------------------------
# Unlike the previous revision this is NOT best-effort. wgpu.rendercanvas is
# part of the wgpu package, so a package that ships it without this bridge
# fails at runtime, not at install time -- the exact failure mode this recipe
# exists to eliminate.
echo "==> Building libglfw_input_cb.${LIB_EXT}"
"$CC_BIN" -shared -fPIC \
    -o "ffi/lib/libglfw_input_cb.${LIB_EXT}" \
    rendercanvas-mojo/ffi/glfw_input_callbacks.c \
    -L"$PREFIX/lib" -lglfw \
    "${RPATH_FLAGS[@]}"

install -d "$PREFIX/lib"
install -m 755 "ffi/lib/libwgpu_mojo_cb.${LIB_EXT}"  "$PREFIX/lib/"
install -m 755 "ffi/lib/libglfw_input_cb.${LIB_EXT}" "$PREFIX/lib/"

# ---------------------------------------------------------------------------
# Compiled Mojo package
# ---------------------------------------------------------------------------
# `mojo precompile` (not the deprecated `mojo package`) emitting .mojoc into
# $PREFIX/lib/mojo is what makes `from wgpu import ...` resolve with no -I flag
# in a consumer's environment.
#
# wgpu_max/ is deliberately not built here: it imports `max`, and keeping it out
# of the package is what keeps `max` off every consumer's dependency path.
echo "==> Compiling the wgpu Mojo package"
install -d "$PREFIX/lib/mojo"
mojo precompile wgpu -o "$PREFIX/lib/mojo/wgpu.mojoc" -I .

echo "==> Installed:"
ls -l "$PREFIX/lib/mojo/wgpu.mojoc" \
      "$PREFIX/lib/libwgpu_mojo_cb.${LIB_EXT}" \
      "$PREFIX/lib/libglfw_input_cb.${LIB_EXT}"
