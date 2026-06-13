# wgpu-mojo

Mojo bindings for [wgpu-native](https://github.com/gfx-rs/wgpu-native), providing a lightweight WebGPU wrapper with RAII-friendly GPU objects.

## GPU Fire Simulation Demo

![GPU Fire Simulation](assets/fire_demo.gif)

Real-time Doom-style fire running entirely on the GPU — compute shader → render shader → GLFW window.

```bash
# clone + run the demo
pixi run build-callbacks && pixi run example-fire-sim
```

---

## Using wgpu-mojo in your project

### Step 1 — Add the package

Your `pixi.toml` needs the Modular and conda-forge channels and `pixi-build` preview:

```toml
[workspace]
channels = ["https://conda.modular.com/max-nightly", "conda-forge"]
preview  = ["pixi-build"]
```

Then add the dependency:

```bash
pixi add --git https://github.com/Hundo1018/wgpu-mojo wgpu-mojo
```

This compiles `wgpu.mojopkg` and installs it into your environment.
All `from wgpu import …` statements now resolve at compile time.

### Step 2 — Install the native GPU library (once per machine)

The Mojo package needs `libwgpu_native` and its callback bridge at runtime.
Run this once inside your project's activated pixi environment:

```bash
curl -fsSL https://raw.githubusercontent.com/Hundo1018/wgpu-mojo/main/scripts/setup-native.sh | bash
```

What it does:
- Downloads `libwgpu_native` v29.0.0.0 from [wgpu-native releases](https://github.com/gfx-rs/wgpu-native/releases)
- Compiles the Mojo callback bridge (`libwgpu_mojo_cb`) from source
- Installs both to `$CONDA_PREFIX/lib/`
- If GLFW is present, also compiles the windowed rendering bridge (`libglfw_input_cb`)

Requires: `curl`, `unzip`, `gcc` (standard in any conda environment).

### Step 3 — Write GPU code

```mojo
from wgpu import Instance, WGPUBufferUsage

def main() raises:
    var instance = Instance()
    var adapter  = instance.request_adapter()
    var device   = adapter.request_device()

    # Allocate a GPU storage buffer
    var buf = device.create_buffer(
        UInt64(1024),
        WGPUBufferUsage.STORAGE | WGPUBufferUsage.COPY_SRC,
        label = "my_buffer",
    )
    # buf releases automatically (RAII) when it goes out of scope
```

---

## Examples

### Headless GPU Compute (no window)

Vector addition on the GPU, result read back to CPU:

```mojo
from wgpu import Instance, WGPUBufferUsage, WGPUMapMode

comptime WGSL = """
@group(0) @binding(0) var<storage, read>       a   : array<f32>;
@group(0) @binding(1) var<storage, read>       b   : array<f32>;
@group(0) @binding(2) var<storage, read_write> out : array<f32>;
@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let i = id.x;
    if i < arrayLength(&a) { out[i] = a[i] + b[i]; }
}
"""

def main() raises:
    var instance = Instance()
    var device   = instance.request_adapter().request_device()
    var gpu      = GPU.wgpu(instance^)

    var n: UInt64 = 1024
    var a = gpu.buffer[Float32](n, WGPUBufferUsage.STORAGE | WGPUBufferUsage.COPY_DST)
    var b = gpu.buffer[Float32](n, WGPUBufferUsage.STORAGE | WGPUBufferUsage.COPY_DST)
    var c = gpu.buffer[Float32](n, WGPUBufferUsage.STORAGE | WGPUBufferUsage.COPY_SRC)

    gpu.write(a, List[Float32](1.0, 2.0, 3.0))   # fill first 3 elements
    gpu.write(b, List[Float32](10.0, 20.0, 30.0))

    var prog = gpu.compile_compute(WGSL, entry_point="main", n_storage_buffers=3)
    gpu.dispatch(prog^, List[Buffer](a, b, c), wx=UInt32(n // 64))

    var result = gpu.read[Float32](c, count=3)
    print(result[0], result[1], result[2])  # 11.0  22.0  33.0
```

Full source: [`examples/compute_add_v2.mojo`](examples/compute_add_v2.mojo)

### Render Triangle (GLFW window)

```mojo
from wgpu.instance import Instance
from wgpu._ffi.structs import WGPUColor
from wgpu.rendercanvas import RenderCanvas

comptime WGSL = """
struct V { @builtin(position) pos: vec4<f32>, @location(0) col: vec3<f32> }
@vertex fn vs(@builtin(vertex_index) i: u32) -> V {
    var pos = array<vec2<f32>,3>(vec2(0.0,0.5), vec2(-0.5,-0.5), vec2(0.5,-0.5));
    var col = array<vec3<f32>,3>(vec3(1,0,0), vec3(0,1,0), vec3(0,0,1));
    return V(vec4(pos[i],0,1), col[i]);
}
@fragment fn fs(v: V) -> @location(0) vec4<f32> { return vec4(v.col,1); }
"""

def main() raises:
    var instance = Instance()
    var adapter  = instance.request_adapter()
    var device   = adapter.request_device()
    var canvas   = RenderCanvas(adapter, device, 800, 600, "hello triangle")
    var shader   = device.create_shader_module_wgsl(WGSL, "tri")
    var layout   = device.create_pipeline_layout(List[OpaquePointer[MutExternalOrigin]](), "layout")
    var pipeline = device.create_render_pipeline(
        shader, "vs", "fs", canvas.surface_format(), layout,
        primitive_topology = UInt32(4),
    )
    while canvas.is_open():
        canvas.poll()
        var frame = canvas.next_frame()
        if not frame.is_renderable(): continue
        var enc   = device.create_command_encoder("frame")
        var rpass = enc.begin_surface_clear_pass(frame.texture, WGPUColor(0,0,0,1), "pass")
        rpass.set_pipeline(pipeline)
        rpass.draw(UInt32(3), UInt32(1), UInt32(0), UInt32(0))
        rpass^.end()
        device.queue_submit(enc^.finish())
        canvas.present()
```

Full source: [`examples/triangle_window.mojo`](examples/triangle_window.mojo)

### Texture Sampling

```mojo
from wgpu import Instance, WGPUTextureUsage, WGPUTextureFormat, WGPUFilterMode
```

Full source: [`examples/texture_sample.mojo`](examples/texture_sample.mojo)

### Enumerate GPU Adapters

```bash
pixi run example-enumerate
```

Output lists all available GPU backends (Vulkan, Metal, DX12) and adapter names.

---

## Available pixi tasks (development clone)

| Task | Description |
|------|-------------|
| `build-callbacks` | Compile C callback bridge (required before GPU tasks) |
| `hello` | Hello triangle quickstart |
| `example-compute` | Headless vector addition |
| `example-enumerate` | List available GPU adapters |
| `example-clear` | Cornflower-blue window (smoke test) |
| `example-triangle` | RGB triangle in a window |
| `example-texture-sample` | Texture sampling demo |
| `example-fire-sim` | GPU fire simulation (compute + render) |
| `test` | Non-GPU unit tests |

---

## Core API

| Module | What it provides |
|--------|-----------------|
| `wgpu.instance` | `Instance` — library entry point, adapter selection |
| `wgpu.adapter` | `Adapter` — device creation |
| `wgpu.device` | `Device` — create all GPU objects, submit work |
| `wgpu.buffer` | `Buffer` — GPU memory allocation, mapping |
| `wgpu.texture` | `Texture`, `TextureView` |
| `wgpu.shader` | `ShaderModule` — WGSL compilation |
| `wgpu.pipeline` | `ComputePipeline`, `RenderPipeline` |
| `wgpu.command` | `CommandEncoder`, `CommandBuffer` |
| `wgpu.compute_pass` | `ComputePassEncoder` |
| `wgpu.render_pass` | `RenderPassEncoder` |
| `wgpu.bind_group` | `BindGroup`, `BindGroupLayout` |
| `wgpu.gpu` | `GPU` — high-level facade (compile + dispatch in ~5 lines) |
| `wgpu.rendercanvas` | `RenderCanvas` — GLFW window + surface |
| `wgpu.diagnostics` | `preflight()` — check library load, list adapters |

All types are re-exported from `wgpu` so `from wgpu import Instance` always works.

---

## Lifetime and Ownership

Wrappers are RAII: GPU objects release automatically when they go out of scope.
Two patterns to keep in mind:

**Encoder types must be explicitly finished:**
```mojo
var enc   = device.create_command_encoder("enc")
var cpass = enc.begin_compute_pass("pass")
# ...
cpass^.end()                  # consume the encoder
var cmd = enc^.finish("cmd")  # consume and produce CommandBuffer
device.queue_submit(cmd^)
```

**Pin resources that must outlive the GPU call:**
```mojo
var pipeline = device.create_compute_pipeline(...)
var bg = device.create_bind_group(...)
device.queue_submit(cmd^)
_ = pipeline^   # prevent ASAP drop before GPU finishes
_ = bg^
device.poll(True)
```

The `GPU` facade (`wgpu.gpu`) handles these pins automatically.

---

## Development Setup (cloning the repo)

```bash
git clone https://github.com/Hundo1018/wgpu-mojo
cd wgpu-mojo
pixi run build-callbacks   # download wgpu-native + compile C bridges
pixi run test              # non-GPU unit tests
pixi run hello             # GPU smoke test — RGB triangle window
```

`pixi run build-callbacks` performs the same steps as `setup-native.sh` but
reads the native library version from [`ffi/wgpu-native-meta/wgpu-native-git-tag`](ffi/wgpu-native-meta/wgpu-native-git-tag)
and uses sources already present in the repo.

### GPU driver prerequisites

| Platform | What to install |
|----------|----------------|
| Linux | Vulkan: `mesa-vulkan-drivers` + `libvulkan1`, or NVIDIA proprietary drivers |
| macOS | Metal is built-in — no extra drivers needed |
| Windows | D3D12 or Vulkan — usually already present with GPU vendor drivers |

### Platform support

`linux-64` and `osx-arm64` are fully supported via pixi.
`osx-x86_64` and `win-x64` can be built manually; see `conda.recipe/recipe.yaml` for the build steps.

---

## Diagnostics

```mojo
from wgpu.diagnostics import preflight
print(preflight())
```

Prints library search paths, load status, wgpu-native version, and available GPU adapters.

---

## License

[Apache-2.0](LICENSE)
