# wgpu-mojo

Mojo bindings for [wgpu-native](https://github.com/gfx-rs/wgpu-native), providing a lightweight WebGPU wrapper for Mojo applications with RAII-friendly GPU objects and GLFW-based examples.

## Requirements

- Mojo `>= 0.26.3`
- [Pixi](https://prefix.dev/) package manager
- `libwgpu_native.so` available at `ffi/lib/libwgpu_native.so`
- GLFW installed and available through your Conda environment
- Platform GPU drivers and runtime support for your system

## Platform Dependencies

This repository provides the Mojo wrapper and Pixi tasks, but does not bundle GPU drivers or native runtime libraries.

### Native library: `wgpu-native`

Download the correct pre-built binary from the [wgpu-native releases page](https://github.com/gfx-rs/wgpu-native/releases) and place it in `ffi/lib/`:

| Platform | Asset to download | File to copy |
|---|---|---|
| Linux x86-64 | `wgpu-linux-x86_64-release.zip` | `libwgpu_native.so` → `ffi/lib/` |
| macOS arm64 | `wgpu-macos-aarch64-release.zip` | `libwgpu_native.dylib` → `ffi/lib/` |
| macOS x86-64 | `wgpu-macos-x86_64-release.zip` | `libwgpu_native.dylib` → `ffi/lib/` |
| Windows x64 | `wgpu-windows-x86_64-release.zip` | `wgpu_native.dll` + `.lib` → `ffi/lib/` |

```bash
mkdir -p ffi/lib
# Linux example — replace the tag with the version matching wgpu-native-git-tag
TAG=$(cat ffi/wgpu-native-meta/wgpu-native-git-tag)
wget "https://github.com/gfx-rs/wgpu-native/releases/download/${TAG}/wgpu-linux-x86_64-release.zip"
unzip wgpu-linux-x86_64-release.zip -d /tmp/wgpu-native
cp /tmp/wgpu-native/libwgpu_native.so ffi/lib/
```

Verify: `ls -lh ffi/lib/libwgpu_native.so` before building callbacks.

### GPU drivers

| Platform | What you need |
|---|---|
| Linux | Vulkan drivers: `mesa-vulkan-drivers` + `libvulkan1` (Intel/AMD) or the NVIDIA proprietary stack |
| macOS | Metal is built into macOS — no extra drivers needed |
| Windows | D3D12 or Vulkan drivers — typically already installed with your GPU vendor's driver package |

### GLFW

GLFW is provided via Conda through Pixi on Linux. On macOS/Windows, install it via [brew](https://formulae.brew.sh/formula/glfw) or [vcpkg](https://vcpkg.io/) and ensure it is on your library path.

> **Note:** The Pixi workspace is currently configured for `linux-64`. On macOS or Windows you can still build and run the code manually with `mojo run -I . hello.mojo` after placing the correct native library in `ffi/lib/`.

## Setup

1. Install Mojo and Pixi.
2. Build the native callback libraries:

```bash
pixi run build-callbacks
pixi run build-callback-probe
```

3. Run the hello triangle example:

```bash
pixi run hello
```

If the window appears, the core runtime path is working: `wgpu-native` → FFI bridge → Mojo wrappers → GLFW window.

## Quick Start

### Hello Triangle

`hello.mojo` renders an RGB vertex-coloured triangle in a GLFW window. This is the exact pattern the file uses:

```mojo
from wgpu.gpu import GPU
from wgpu._ffi.types import OpaquePtr
from wgpu._ffi.structs import WGPUColor
from rendercanvas import RenderCanvas

comptime WGSL = """
struct VertexOut {
    @builtin(position) pos: vec4<f32>,
    @location(0)       col: vec3<f32>,
}
@vertex
fn vs_main(@builtin(vertex_index) i: u32) -> VertexOut {
    var pos = array<vec2<f32>, 3>(
        vec2( 0.0,  0.5), vec2(-0.5, -0.5), vec2( 0.5, -0.5),
    );
    var col = array<vec3<f32>, 3>(
        vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0),
    );
    var out: VertexOut;
    out.pos = vec4<f32>(pos[i], 0.0, 1.0);
    out.col = col[i];
    return out;
}
@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4<f32> {
    return vec4<f32>(in.col, 1.0);
}
"""

def main() raises:
    var gpu    = GPU()
    var device = gpu.request_device()
    var canvas = RenderCanvas(gpu, device, 800, 600, "wgpu-mojo: hello triangle")
    var shader = device.create_shader_module_wgsl(WGSL, "hello")
    var layout = device.create_pipeline_layout(List[OpaquePtr](), "layout")
    var pipeline = device.create_render_pipeline(
        shader, "vs_main", "fs_main",
        canvas.surface_format(), layout,
        primitive_topology=UInt32(4),  # TriangleList
    )
    while canvas.is_open():
        canvas.poll()
        var frame = canvas.next_frame()
        if not frame.is_renderable():
            continue
        var enc   = device.create_command_encoder("frame")
        var rpass = enc.begin_surface_clear_pass(
            frame.texture,
            WGPUColor(Float64(0), Float64(0), Float64(0), Float64(1)),
            "pass",
        )
        rpass.set_pipeline(pipeline)
        rpass.draw(UInt32(3), UInt32(1), UInt32(0), UInt32(0))
        rpass^.end()
        device.queue_submit(enc^.finish())
        canvas.present()
```

Run it with `pixi run hello`. See `examples/triangle_window.mojo` for an identical standalone version.

### GPU Compute (no window)

For headless work (ML, simulation, data processing), skip `RenderCanvas` entirely:

```mojo
from wgpu import GPU, WGPUBufferUsage

def main() raises:
    var gpu    = GPU()
    var device = gpu.request_device()

    var buf = device.create_buffer(
        UInt64(1024),
        WGPUBufferUsage.STORAGE | WGPUBufferUsage.COPY_DST,
        label="my_buffer",
    )
    # GPU objects release automatically when they go out of scope (RAII).
```

See `examples/compute_add.mojo` for a full vector-addition pipeline with buffer readback.

## Available Tasks

- `pixi run build-callbacks` — build the C callback bridge
- `pixi run build-callback-probe` — build the callback probe library
- `pixi run hello` — run `hello.mojo`
- `pixi run example-triangle` — run `examples/triangle_window.mojo`
- `pixi run example-compute` — run `examples/compute_add.mojo`
- `pixi run example-enumerate` — run `examples/enumerate_adapters.mojo`
- `pixi run example-clear` — run `examples/clear_screen.mojo`
- `pixi run example-input` — run `examples/input_demo.mojo`
- `pixi run example-texture-sample` — run `examples/texture_sample.mojo`
- `pixi run example-native-extensions` — run `examples/native_extensions.mojo`
- `pixi run test` — run non-GPU tests
- `pixi run test-glfw-input` — run GLFW input integration test

## Project Layout

- `hello.mojo` — hello triangle quickstart (RGB vertices, GLFW window)
- `examples/triangle_window.mojo` — identical standalone triangle demo
- `examples/texture_sample.mojo` — sampled texture rendering demo
- `examples/native_extensions.mojo` — query native wgpu-native feature support
- `examples/` — GPU compute, adapter enumeration, clear-screen, and input demos
- `tests/` — Mojo test files for wrapper behavior and API compatibility
- `wgpu/` — high-level Mojo wrapper layer for WebGPU objects
- `wgpu/_ffi/` — raw FFI bindings and type definitions
- `ffi/` — native C callback bridge and headers

### Core wrapper modules

- `wgpu/gpu.mojo` — `GPU()` entrypoint, adapter/device request, logging control
- `wgpu/instance.mojo` — adapter enumeration and device discovery
- `wgpu/device.mojo` — device creation, queue submission, buffer/texture/pipeline helpers
- `wgpu/buffer.mojo` — buffer creation, mapping, and data transfer helpers
- `wgpu/texture.mojo` — texture and texture view handling
- `wgpu/sampler.mojo` — sampler creation
- `wgpu/shader.mojo` — shader module creation
- `wgpu/bind_group.mojo` — bind group and layout helpers
- `wgpu/pipeline_layout.mojo` — pipeline layout creation
- `wgpu/pipeline.mojo` — compute and render pipeline helpers
- `wgpu/command.mojo` — command encoder management
- `wgpu/compute_pass.mojo` — compute pass encoder APIs
- `wgpu/render_pass.mojo` — render pass encoder APIs
- `wgpu/query_set.mojo` — query set support

## Lifetime and Ownership

The wrappers are built around RAII, but Mojo lifetime rules still matter when you extract raw handles or pointers.

- Keep owning wrappers alive after extracting raw handles or passing `unsafe_ptr()` references.
- Prefer wrapper-first APIs instead of raw `WGPU*Handle` values.
- Call `finish()`, `end()`, or `abandon()` on `CommandEncoder`, `RenderPassEncoder`, and `ComputePassEncoder` when required.
- When you need to pin an object, use `_ = value^` until the consuming GPU call completes.

Minimal pin example:

```mojo
var gpu = GPU()
var device = gpu.request_device()
var buf = device.create_buffer(UInt64(256), WGPUBufferUsage.STORAGE)
var raw_handle = buf.handle().raw

# ... use raw_handle in descriptors or FFI calls ...

_ = buf^
_ = device^
_ = gpu^
```

## Architecture

This project uses a thin, dynamic FFI layer to load `libwgpu_native.so` at runtime. The Mojo wrapper layer exposes high-level WebGPU concepts while the `ffi/` C bridge handles callback-based APIs such as device requests and buffer mapping.

## Notes

- `pixi run test` is intended for non-GPU tests and does not require a GPU device.
- GPU examples and GPU-specific tests require `pixi run build-callbacks` first.
- `example-input` is the correct example task name for the input demo.

## License

See [LICENSE](LICENSE).

