# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

wgpu-mojo provides pure Mojo bindings for [wgpu-native](https://github.com/gfx-rs/wgpu-native), a WebGPU implementation. It is a Pixi-managed workspace targeting `linux-64` and `osx-arm64`, with a companion subproject at `rendercanvas-mojo/`.

## Prerequisites

Before running any GPU tests or examples, `libwgpu_native.so` must be present at `ffi/lib/libwgpu_native.so`. Download it from the wgpu-native releases page using the git tag in `ffi/wgpu-native-meta/wgpu-native-git-tag`. The C callback bridges also must be compiled first (see commands below).

## Commands

All commands are run via `pixi run <task>` from the repo root (or `rendercanvas-mojo/` for subproject tasks).

### Build

```bash
pixi run build-callbacks       # compile C callback bridges (required before GPU work)
pixi run build-callback-probe  # compile ABI probe library (required for callback ABI tests)
```

### Run tests

```bash
pixi run test                  # all non-GPU tests (no hardware required)
pixi run test-types            # individual non-GPU test
pixi run test-structs
pixi run test-handle-newtypes
pixi run test-callback-abi
pixi run test-native-ext

# GPU-requiring tests (need build-callbacks + GPU hardware + display server)
pixi run test-instance
pixi run test-device
pixi run test-buffer
pixi run test-texture
pixi run test-compute
```

Run a single test file directly:
```bash
mojo run -I . tests/test_types.mojo
```

### Run examples

```bash
pixi run hello                   # hello triangle (GLFW window)
pixi run example-clear           # cornflower-blue window (minimal GPU path)
pixi run example-compute         # headless vector-addition (no display needed)
pixi run example-enumerate       # list GPU adapters
pixi run example-texture-sample
pixi run example-input
```

### rendercanvas-mojo subproject

```bash
cd rendercanvas-mojo
pixi install
pixi run build-callbacks
pixi run test                    # non-GPU tests
pixi run test-glfw-input         # requires display server
```

### Package build

```bash
pixi build   # builds wgpu-mojo conda package
```

## Architecture

### Layer model

```
wgpu/                    ← High-level Mojo RAII wrappers (user-facing)
wgpu/_ffi/               ← Backward-compat shims (re-export from _backend)
wgpu/_backend/wgpu_native/ ← Canonical FFI layer: types, structs, handles, loader
ffi/                     ← C callback bridge source + headers + compiled libs
rendercanvas-mojo/       ← Standalone subproject: GLFW window + surface integration
```

### Key files

- **`wgpu/_backend/wgpu_native/loader.mojo` (`WGPULib`)** — loads `libwgpu_native.so` and `libwgpu_mojo_cb.so` at runtime via `std.ffi.OwnedDLHandle`; exposes every `webgpu.h` function as a method.
- **`wgpu/instance_owner.mojo` (`InstanceOwner`)** — shared owner (via `ArcPointer`) of `WGPULib` + raw `WGPUInstance`. `Instance`, `Adapter`, and `Device` all hold an `ArcPointer[InstanceOwner]` so the library stays loaded as long as any GPU object is alive.
- **`wgpu/instance.mojo`** — entry point; creates `WGPULib`, instantiates `InstanceOwner`, exposes `request_adapter()`.
- **`wgpu/device.mojo`** — the central factory: `create_buffer`, `create_texture`, `create_shader_module_wgsl`, `create_render_pipeline`, `create_compute_pipeline`, `queue_submit`, etc.
- **`wgpu/rendercanvas/canvas.mojo` (`RenderCanvas`)** — owns a GLFW window and wgpu `Surface`; the standard render-loop host.
- **`ffi/wgpu_callbacks.c`** — C callback bridge. wgpu-native's async APIs require C function pointers; this file provides them and writes results into caller-allocated structs whose layout must match the `_*Result` structs in `loader.mojo`.

### Handle newtype pattern

Raw `OpaquePointer[MutExternalOrigin]` handles from wgpu-native are wrapped in strongly-typed newtypes (e.g. `AdapterHandle`, `DeviceHandle`) defined in `wgpu/_backend/wgpu_native/handles.mojo` and re-exported through `wgpu/_ffi/handles.mojo`. This prevents accidentally passing the wrong raw pointer to an FFI call.

### RAII and ownership

- Every GPU object (`Buffer`, `Texture`, `RenderPipeline`, etc.) releases its wgpu-native handle in `__del__`.
- Encoder types (`CommandEncoder`, `RenderPassEncoder`, `ComputePassEncoder`) must be explicitly finished: call `.finish()`, `.end()`, or `.abandon()` before they drop.
- When a raw handle is embedded in a descriptor struct and passed to an FFI call, Mojo's ASAP drop may free the owning wrapper before the call returns. Pin with `_ = obj^` after the call.
- `Device` may need to be pinned past `map_read`/`poll` calls (wgpu-native v29 behaviour).
- `Instance` does **not** need pinning — shared ownership through `InstanceOwner` keeps the library alive.

### C callback bridge layout contract

The `_*Result` structs at the top of `loader.mojo` (e.g. `_AdapterResult`, `_DeviceResult`) must match the `typedef struct` definitions at the top of `ffi/wgpu_callbacks.c`. Breaking this layout silently corrupts the result.

### rendercanvas-mojo subproject

`rendercanvas-mojo/` is an independent Pixi workspace that builds the `rendercanvas` Mojo package. Its `rendercanvas/canvas.mojo` imports from `wgpu.*`; during development the `-I ../wgpu-mojo` flag is passed to resolve those imports. It compiles its own C bridge (`ffi/glfw_input_callbacks.c` → `libglfw_input_cb.so`) for GLFW keyboard/mouse callbacks into Mojo.

### WGSL shaders

WGSL shader source is embedded inline in Mojo files using `comptime` string literals and passed to `device.create_shader_module_wgsl(wgsl_source, label)`. Standalone `.wgsl` files live in `wgsl/`.

### `tests/abi_probes/`

These are not regular test files — they are incremental experiments for exploring Mojo's FFI/ABI behaviour (callback passing, struct layout, opaque pointer rebinding). They document what works and what does not at each Mojo nightly.
