# wgpu-mojo

Pure Mojo bindings for [wgpu-native](https://github.com/gfx-rs/wgpu-native) (WebGPU).

## Requirements

- Mojo ≥ 0.26.3
- [Pixi](https://prefix.dev/) package manager
- wgpu-native shared library at `ffi/lib/libwgpu_native.so`

## Quick Start

```mojo
from wgpu import request_adapter, WGPUBufferUsage

def main() raises:
    var instance = request_adapter()
    var device = instance.request_device()
    var buffer = device.create_buffer(
        UInt64(1024), WGPUBufferUsage.STORAGE | WGPUBufferUsage.COPY_DST,
        label="my_buffer",
    )
    # buffer is automatically released when it goes out of scope
```

## Project Structure

```
wgpu/                     # High-level RAII wrappers
├── gpu.mojo              # request_adapter(), set_log_level()
├── instance.mojo         # Instance (adapter info, request_device)
├── device.mojo           # Device (create_*, queue ops)
├── buffer.mojo           # Buffer (map, read_data, write_data)
├── texture.mojo          # Texture, TextureView
├── sampler.mojo          # Sampler
├── shader.mojo           # ShaderModule
├── bind_group.mojo       # BindGroup, BindGroupLayout
├── pipeline_layout.mojo  # PipelineLayout
├── pipeline.mojo         # ComputePipeline, RenderPipeline
├── command.mojo          # CommandEncoder
├── compute_pass.mojo     # ComputePassEncoder
├── render_pass.mojo      # RenderPassEncoder
├── query_set.mojo        # QuerySet
└── _ffi/                 # Raw FFI layer
    ├── lib.mojo          # WGPULib (dlsym dispatcher, ~170 functions)
    ├── types.mojo        # Type aliases, enums, bitflags
    └── structs.mojo      # C struct layouts (descriptors, etc.)

examples/
├── compute_add.mojo      # GPU vector addition (compute shader)
└── enumerate_adapters.mojo  # List all GPU adapters

tests/                    # 16 test files, 27+ non-GPU tests compile & pass
```

## Build & Test

```bash
# Build the C callback bridge
pixi run build-callbacks

# Run non-GPU tests (no GPU required)
pixi run test

# Run examples (requires GPU)
pixi run example-compute
pixi run example-enumerate
```

## Architecture

All GPU objects use **RAII wrappers** (`struct X(Movable)`) that automatically call
`destroy`/`release` in their `__del__` destructor. `Device.create_*()` methods return
wrapped types directly — no manual cleanup needed.

The FFI layer (`wgpu/_ffi/`) uses `OwnedDLHandle` + `dlsym` to dynamically load
`libwgpu_native.so` at runtime. A thin C bridge (`ffi/wgpu_callbacks.c`) handles
callback-based APIs like device request and buffer mapping.

### wgpu-native Extensions

Native extensions beyond the WebGPU spec are supported:
- Push constants (`ComputePassEncoder.set_push_constants`, `RenderPassEncoder.set_push_constants`)
- Multi-draw (`RenderPassEncoder.multi_draw_indirect`, `multi_draw_indexed_indirect`)
- Pipeline statistics queries
- Timestamp writes on compute/render passes
- Log level control (`set_log_level()`)

## License

See [LICENSE](LICENSE).
