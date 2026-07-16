#!/usr/bin/env bash
# setup-native.sh — install wgpu-native and compile the Mojo callback bridge
#
# Run once after `pixi add --git https://github.com/Hundo1018/wgpu-mojo wgpu-mojo`
# to install the native runtime libraries that pixi-build-mojo cannot bundle.
#
# Requires: curl, unzip, gcc (all available in a typical pixi/conda environment).
# Installs to: $CONDA_PREFIX/lib/  (where the wgpu loader searches first).

set -euo pipefail

WGPU_TAG="v29.0.0.0"
REPO_RAW="https://raw.githubusercontent.com/Hundo1018/wgpu-mojo/main"

# ---------------------------------------------------------------------------
# Platform detection
# ---------------------------------------------------------------------------
OS=$(uname -s)
ARCH=$(uname -m)

case "${OS}-${ARCH}" in
    Linux-x86_64)
        WGPU_ASSET="wgpu-linux-x86_64-release.zip"
        LIB_EXT="so"
        LIB_PREFIX="lib"
        CB_OUT="libwgpu_mojo_cb.so"
        GLFW_CB_OUT="libglfw_input_cb.so"
        LINK_FLAGS="-Wl,-rpath,\$ORIGIN"
        ;;
    Darwin-arm64)
        WGPU_ASSET="wgpu-macos-aarch64-release.zip"
        LIB_EXT="dylib"
        LIB_PREFIX="lib"
        CB_OUT="libwgpu_mojo_cb.dylib"
        GLFW_CB_OUT="libglfw_input_cb.dylib"
        LINK_FLAGS="-Wl,-rpath,\$ORIGIN"
        ;;
    Darwin-x86_64)
        WGPU_ASSET="wgpu-macos-x86_64-release.zip"
        LIB_EXT="dylib"
        LIB_PREFIX="lib"
        CB_OUT="libwgpu_mojo_cb.dylib"
        GLFW_CB_OUT="libglfw_input_cb.dylib"
        LINK_FLAGS="-Wl,-rpath,\$ORIGIN"
        ;;
    *)
        echo "Unsupported platform: ${OS}-${ARCH}" >&2
        exit 1
        ;;
esac

WGPU_LIB="${LIB_PREFIX}wgpu_native.${LIB_EXT}"

# ---------------------------------------------------------------------------
# Resolve install prefix
# ---------------------------------------------------------------------------
if [[ -z "${CONDA_PREFIX:-}" ]]; then
    echo "Error: CONDA_PREFIX is not set. Activate your pixi/conda environment first:" >&2
    echo "  pixi shell   (from your project directory)" >&2
    exit 1
fi
INSTALL_DIR="${CONDA_PREFIX}/lib"
mkdir -p "${INSTALL_DIR}"

echo "==> Installing wgpu-native ${WGPU_TAG} + callback bridge"
echo "    Target: ${INSTALL_DIR}"

# ---------------------------------------------------------------------------
# Download wgpu-native
# ---------------------------------------------------------------------------
TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT

echo "--> Downloading ${WGPU_ASSET} ..."
curl -fsSL --retry 3 \
    "https://github.com/gfx-rs/wgpu-native/releases/download/${WGPU_TAG}/${WGPU_ASSET}" \
    -o "${TMP}/wgpu.zip"

unzip -q "${TMP}/wgpu.zip" -d "${TMP}/wgpu"

cp "${TMP}/wgpu/lib/${WGPU_LIB}" "${INSTALL_DIR}/"
echo "    Installed ${WGPU_LIB}"

# Keep headers for C compilation below
INCLUDE_DIR="${TMP}/wgpu/include/webgpu"

# ---------------------------------------------------------------------------
# Download and compile the Mojo callback bridge (libwgpu_mojo_cb)
# ---------------------------------------------------------------------------
echo "--> Compiling Mojo callback bridge ..."
curl -fsSL "${REPO_RAW}/ffi/wgpu_callbacks.c" -o "${TMP}/wgpu_callbacks.c"

gcc -shared -fPIC \
    -o "${TMP}/${CB_OUT}" \
    "${TMP}/wgpu_callbacks.c" \
    -I"${TMP}/wgpu" \
    -L"${INSTALL_DIR}" -lwgpu_native \
    ${LINK_FLAGS}

cp "${TMP}/${CB_OUT}" "${INSTALL_DIR}/"
echo "    Installed ${CB_OUT}"

# ---------------------------------------------------------------------------
# Compile the GLFW input callback bridge (optional — needed for RenderCanvas)
# ---------------------------------------------------------------------------
if command -v glfw-config &>/dev/null || [[ -f "${CONDA_PREFIX}/lib/libglfw.${LIB_EXT}" ]] || \
   [[ -f "${CONDA_PREFIX}/lib/libglfw3.${LIB_EXT}" ]]; then
    echo "--> Compiling GLFW input callback bridge ..."
    curl -fsSL "${REPO_RAW}/rendercanvas-mojo/ffi/glfw_input_callbacks.c" \
        -o "${TMP}/glfw_input_callbacks.c"

    GLFW_LINK="-lglfw"
    # Try libglfw3 if libglfw is not present
    if [[ ! -f "${CONDA_PREFIX}/lib/libglfw.${LIB_EXT}" ]] && \
       [[ -f "${CONDA_PREFIX}/lib/libglfw3.${LIB_EXT}" ]]; then
        GLFW_LINK="-lglfw3"
    fi

    gcc -shared -fPIC \
        -o "${TMP}/${GLFW_CB_OUT}" \
        "${TMP}/glfw_input_callbacks.c" \
        -L"${CONDA_PREFIX}/lib" ${GLFW_LINK} \
        -Wl,-rpath,"${CONDA_PREFIX}/lib" \
        ${LINK_FLAGS} 2>/dev/null \
    && cp "${TMP}/${GLFW_CB_OUT}" "${INSTALL_DIR}/" \
    && echo "    Installed ${GLFW_CB_OUT}" \
    || echo "    Skipped ${GLFW_CB_OUT} (GLFW link failed — windowed examples unavailable)"
else
    echo "--> GLFW not found — skipping ${GLFW_CB_OUT} (windowed examples unavailable)"
    echo "    Install GLFW via conda: pixi add glfw"
fi

# ---------------------------------------------------------------------------
# Verify
# ---------------------------------------------------------------------------
echo ""
echo "==> Installed files:"
ls -lh "${INSTALL_DIR}/${WGPU_LIB}" \
       "${INSTALL_DIR}/${CB_OUT}" \
       "${INSTALL_DIR}/${GLFW_CB_OUT}" 2>/dev/null || true

echo ""
cat <<'EOF'
==> Done. Test with (mojo has no -c flag, so use a file):

cat > wgpu_check.mojo <<'MOJO'
from wgpu import Instance


def main() raises:
    _ = Instance()
    print("wgpu OK")
MOJO
mojo run wgpu_check.mojo
EOF
