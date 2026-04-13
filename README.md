# wgpu-mojo

Mojo bindings for [wgpu-native](https://github.com/gfx-rs/wgpu-native), providing a lightweight WebGPU wrapper for Mojo applications with RAII-friendly GPU objects and GLFW-based examples.

## Requirements

- Mojo `>= 0.26.3`
- [Pixi](https://prefix.dev/) package manager
- `libwgpu_native.so` available at `ffi/lib/libwgpu_native.so`
- GLFW installed and available through your Conda environment
- Platform GPU drivers and runtime support for your system

## Platform Dependencies

This repository provides the Mojo wrapper and example tasks, but it does not install system-level GPU drivers or native runtime libraries for you.

You must install the platform-specific dependencies yourself before running GPU examples.

- Linux: Vulkan-compatible GPU drivers, GLFW, and `libwgpu_native.so`. On many distributions this means installing Mesa Vulkan/OpenGL drivers such as `mesa-vulkan-drivers`, `libvulkan1`, or the vendor-specific GPU stack for Intel/AMD/NVIDIA.
- macOS: Metal-compatible GPU drivers and a compatible `wgpu-native` build
- Windows: D3D12/Vulkan drivers and the appropriate `wgpu-native` DLL

If you are using a Conda environment, make sure GLFW is available there and `ffi/lib/libwgpu_native.so` is present or symlinked from the native runtime build.

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

Use the `GPU` wrapper and request a device before creating buffers, pipelines, or passes:

```mojo
from wgpu.gpu import GPU

func main() raises:
    var gpu = GPU()
    var device = gpu.request_device()

    var buffer = device.create_buffer(
        UInt64(1024),
        WGPUBufferUsage.STORAGE | WGPUBufferUsage.COPY_DST,
        label="my_buffer",
    )

    # GPU objects are RAII-managed and released when they go out of scope.
```

## Available Tasks

- `pixi run build-callbacks` — build the C callback bridge
- `pixi run build-callback-probe` — build the callback probe library
- `pixi run hello` — run `hello.mojo`
- `pixi run example-triangle` — run `examples/triangle_window.mojo`
- `pixi run example-compute` — run `examples/compute_add.mojo`
- `pixi run example-enumerate` — run `examples/enumerate_adapters.mojo`
- `pixi run example-clear` — run `examples/clear_screen.mojo`
- `pixi run example-input` — run `examples/input_demo.mojo`
- `pixi run test` — run non-GPU tests
- `pixi run test-glfw-input` — run GLFW input integration test

## Project Layout

- `hello.mojo` — triangle demo using the Mojo wrapper
- `examples/` — sample GPU programs and input demos
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

