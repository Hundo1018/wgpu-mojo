#!/usr/bin/env bash
# Install the built package from a conda channel into a throwaway project.
#
# consume.yml already proves the `pixi add --git` path works. That path builds
# the source with pixi-build-mojo, which packages only the Mojo code -- so it
# can never catch a mistake in what the *conda* package ships. The published
# package is the one users actually install, and until this script existed
# nothing exercised it.
#
# The project is created in a fresh temporary directory with its own pixi
# environment: no repo checkout on the path, no -I flag, no ffi/lib, and no
# LD_LIBRARY_PATH from an activated dev environment. If the package is not
# self-contained, this fails.
#
# Usage: scripts/check-consume-channel.sh <rattler-build output dir>
set -euo pipefail
cd "$(dirname "$0")/.."

# Defaults to check-recipe.sh's default output directory, so the pair runs as
#   pixi run check-recipe && pixi run check-consume-channel
CHANNEL_DIR="${1:-${TMPDIR:-/tmp}/wgpu-mojo-recipe-check}"
if [ ! -d "$CHANNEL_DIR" ]; then
    echo "Error: $CHANNEL_DIR does not exist." >&2
    echo "Run 'pixi run check-recipe' first, or pass an output directory." >&2
    exit 1
fi
CHANNEL_DIR="$(cd "$CHANNEL_DIR" && pwd)"   # file:// URLs must be absolute

# ---------------------------------------------------------------------------
# Actually isolate the consumer
# ---------------------------------------------------------------------------
# Run through `pixi run check-consume-channel` and this script inherits
# PIXI_PROJECT_MANIFEST and friends pointing at *this* repo. Current pixi warns
# and falls back to the local manifest, so the test still passed -- on tolerance,
# not on isolation. Drop them so the throwaway project is genuinely standalone.
unset PIXI_PROJECT_MANIFEST PIXI_PROJECT_ROOT PIXI_ENVIRONMENT_NAME \
      PIXI_ENVIRONMENT_PLATFORMS PIXI_PROJECT_NAME PIXI_PROJECT_VERSION \
      PIXI_EXE PIXI_IN_SHELL CONDA_PREFIX CONDA_DEFAULT_ENV
# LD_LIBRARY_PATH is set by this repo's [activation] to ffi/lib, which would let
# the consumer resolve native libraries from the checkout instead of from the
# installed package -- the exact failure this gate exists to catch.
unset LD_LIBRARY_PATH DYLD_LIBRARY_PATH

if ! ls "$CHANNEL_DIR"/*/*.conda >/dev/null 2>&1; then
    echo "Error: no .conda packages under $CHANNEL_DIR" >&2
    echo "Run scripts/check-recipe.sh first." >&2
    exit 1
fi

# rattler-build writes repodata.json as it builds, but regenerate it so the
# channel reflects every package currently in the directory.
echo "==> Indexing local channel: $CHANNEL_DIR"
pixi exec rattler-index fs "$CHANNEL_DIR" >/dev/null

# Declare only the platform being tested. A local channel built on one machine
# holds one subdir, and pixi solves every declared platform -- listing both
# supported platforms here fails on "no candidates" for the absent one, which
# says nothing about the package.
case "$(uname -s)-$(uname -m)" in
    Linux-x86_64)  PLATFORM="linux-64"  ;;
    Darwin-arm64)  PLATFORM="osx-arm64" ;;
    *)
        echo "Error: unsupported platform $(uname -s)-$(uname -m)" >&2
        exit 1
        ;;
esac

PROJECT="$(mktemp -d)"
trap 'rm -rf "$PROJECT"' EXIT
echo "==> Fresh consumer project: $PROJECT ($PLATFORM)"

cat > "$PROJECT/pixi.toml" <<TOML
[workspace]
name = "wgpu-consumer-channel"
channels = ["file://${CHANNEL_DIR}", "https://conda.modular.com/max", "conda-forge"]
platforms = ["${PLATFORM}"]
version = "0.1.0"

[dependencies]
mojo = ">=1.0.0,<2"
TOML

# ---------------------------------------------------------------------------
# Assertion 1 (no GPU required): the package resolves and both native
# libraries load out of the installed environment.
# ---------------------------------------------------------------------------
cat > "$PROJECT/smoke.mojo" <<'MOJO'
from wgpu import Instance
from wgpu.diagnostics import check_symbols, preflight


def main() raises:
    var missing = check_symbols()
    if len(missing) != 0:
        raise Error("missing symbols: " + String(len(missing)))
    print(preflight())
MOJO

# ---------------------------------------------------------------------------
# Assertion 2 (needs an adapter): a real compute round trip through the
# consumed package -- upload, dispatch, read back, verify.
# ---------------------------------------------------------------------------
cat > "$PROJECT/compute.mojo" <<'MOJO'
from wgpu.gpu import GPU
from wgpu._ffi.types import WGPUBufferUsage

comptime N = 1024
comptime ADD_WGSL = """
@group(0) @binding(0) var<storage, read>       buf_a : array<f32>;
@group(0) @binding(1) var<storage, read>       buf_b : array<f32>;
@group(0) @binding(2) var<storage, read_write> buf_c : array<f32>;
@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) gid : vec3<u32>) {
    let i = gid.x;
    if (i < arrayLength(&buf_a)) { buf_c[i] = buf_a[i] + buf_b[i]; }
}
"""


def main() raises:
    var gpu = GPU.wgpu()
    var a = gpu.buffer[Float32](N, WGPUBufferUsage.STORAGE | WGPUBufferUsage.COPY_DST, "a")
    var b = gpu.buffer[Float32](N, WGPUBufferUsage.STORAGE | WGPUBufferUsage.COPY_DST, "b")
    var c = gpu.buffer[Float32](N, WGPUBufferUsage.STORAGE | WGPUBufferUsage.COPY_SRC, "c")

    var xs = List[Float32](capacity=N)
    var ys = List[Float32](capacity=N)
    for i in range(N):
        xs.append(Float32(i))
        ys.append(Float32(i) * 2.0)
    gpu.write(a, xs)
    gpu.write(b, ys)

    var prog = gpu.compile_compute(
        ADD_WGSL, entry_point="main", n_storage_buffers=3,
        read_only_bindings=[0, 1], label="vec_add",
    )
    gpu.dispatch(prog^, [a.handle(), b.handle(), c.handle()], N // 64, 1, 1, "dispatch")
    _ = a
    _ = b

    var result = gpu.read[Float32](c)
    for i in range(N):
        var expected = Float32(i) * 3.0
        if abs(result[i] - expected) > 1e-4:
            raise Error("mismatch at " + String(i))
    print("compute round trip OK — all", N, "elements correct")
MOJO

echo "==> pixi add wgpu-mojo"
( cd "$PROJECT" && pixi add wgpu-mojo )

echo ""
echo "==> Assertion 1: package resolves, native libraries load"
SMOKE_OUT="$(cd "$PROJECT" && pixi run mojo run smoke.mojo)"
echo "$SMOKE_OUT"

# ---------------------------------------------------------------------------
# Only attempt the GPU assertion when preflight actually found an adapter.
# A build machine without one is not a failure; silently skipping without
# saying so would be.
# ---------------------------------------------------------------------------
ADAPTERS="$(printf '%s\n' "$SMOKE_OUT" | sed -n 's/.*adapters found: \([0-9]\+\).*/\1/p' | head -1)"
echo ""
if [ "${ADAPTERS:-0}" -gt 0 ]; then
    echo "==> Assertion 2: compute round trip on a real adapter"
    ( cd "$PROJECT" && pixi run mojo run compute.mojo )
else
    echo "==> Assertion 2 SKIPPED: no GPU adapter in this environment"
    echo "    (assertion 1 still proves the package is self-contained)"
fi

echo ""
echo "==> Consumed from channel successfully."
