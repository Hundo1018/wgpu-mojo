"""
examples/shadertoy.mojo — a ShaderToy-style fullscreen fragment-shader host.

This is the lowest-friction way to play with GPU fragment shaders in wgpu-mojo:
the Mojo side just opens a window, owns a tiny uniform buffer, and draws one
fullscreen triangle pair every frame.  ALL the visuals live in the WGSL string
below — to make your own effect you only edit `mainImage`, exactly like on
https://www.shadertoy.com/ .

ShaderToy conventions provided as uniforms (see the `Uniforms` struct in WGSL):
    iResolution : vec3<f32>   viewport size in pixels (z = 1.0)
    iTime       : f32         seconds since start
    iMouse      : vec4<f32>   mouse (xy = current, zw = click) — 0 here (no input wired)
    iFrame      : f32         frame counter

Difficulty ladder (this file is tier 1 — a classic plasma):
    1. plasma / gradient   ← you are here
    2. 2D SDF shapes / noise
    3. raymarching
Copy this file, keep the host, swap `mainImage`, and climb the ladder.

Run:
    pixi run example-shadertoy
"""

from wgpu import (
    Instance,
    WGPUBufferUsage, WGPUShaderStage, WGPU_WHOLE_SIZE,
    WGPUBindGroupLayoutEntry, WGPUBindGroupEntry,
    WGPUColor, BGL,
)
from wgpu.rendercanvas import RenderCanvas
from wgpu._ffi.nulls import null_opaque
from std import io

comptime WIN_W = 960
comptime WIN_H = 540

# ---------------------------------------------------------------------------
# WGSL — the only part you edit to make a new effect.
#
# `mainImage` mirrors ShaderToy's `void mainImage(out vec4 fragColor,
# in vec2 fragCoord)`.  The host fragment entry flips Y so fragCoord uses
# ShaderToy's bottom-left origin, then calls mainImage for every pixel.
# ---------------------------------------------------------------------------
comptime SHADERTOY_WGSL = """
struct Uniforms {
    iResolution: vec3<f32>,
    iTime: f32,
    iMouse: vec4<f32>,
    iFrame: f32,
    _pad0: f32,
    _pad1: f32,
    _pad2: f32,
}
@group(0) @binding(0) var<uniform> U: Uniforms;

// ---- fullscreen triangle pair (no vertex buffer needed) -------------------
@vertex
fn vs_main(@builtin(vertex_index) idx: u32) -> @builtin(position) vec4<f32> {
    var p = array<vec2<f32>, 6>(
        vec2<f32>(-1.0, -1.0), vec2<f32>(1.0, -1.0), vec2<f32>(-1.0, 1.0),
        vec2<f32>(-1.0, 1.0), vec2<f32>(1.0, -1.0), vec2<f32>(1.0, 1.0),
    );
    return vec4<f32>(p[idx], 0.0, 1.0);
}

// ===========================================================================
// EDIT BELOW — this is your ShaderToy `mainImage`.
// ===========================================================================
fn mainImage(fragColor: ptr<function, vec4<f32>>, fragCoord: vec2<f32>) {
    let uv = fragCoord / U.iResolution.xy;
    let t = U.iTime;

    // Classic summed-sine plasma.
    var v = 0.0;
    v += sin((uv.x * 10.0) + t);
    v += sin((uv.y * 10.0 + t) * 0.5);
    v += sin((uv.x * 10.0 + uv.y * 10.0 + t) * 0.5);
    let cx = uv.x + 0.5 * sin(t * 0.2);
    let cy = uv.y + 0.5 * cos(t * 0.3);
    v += sin(sqrt(cx * cx + cy * cy) * 20.0 + t);
    v = v * 0.5;

    let col = vec3<f32>(
        sin(v * 3.14159),
        sin(v * 3.14159 + 2.09440),
        sin(v * 3.14159 + 4.18879),
    ) * 0.5 + vec3<f32>(0.5);
    *fragColor = vec4<f32>(col, 1.0);
}
// ===========================================================================

@fragment
fn fs_main(@builtin(position) frag: vec4<f32>) -> @location(0) vec4<f32> {
    // ShaderToy origin is bottom-left; @builtin(position) is top-left.
    let fragCoord = vec2<f32>(frag.x, U.iResolution.y - frag.y);
    var col = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    mainImage(&col, fragCoord);
    return col;
}
"""


def main() raises:
    print("=== wgpu-mojo: ShaderToy host (plasma) ===")
    var instance = Instance()
    var adapter = instance.request_adapter()
    var device = adapter.request_device()
    var canvas = RenderCanvas(
        adapter, device, WIN_W, WIN_H, "wgpu-mojo · ShaderToy host"
    )

    # Uniform buffer: 12 × f32 = 48 bytes (std140-safe ShaderToy layout).
    var uniforms = device.create_buffer(
        UInt64(48),
        WGPUBufferUsage.UNIFORM | WGPUBufferUsage.COPY_DST,
        label="shadertoy_uniforms",
    )

    var bgl = device.create_bind_group_layout(
        [BGL.buffer_uniform(UInt32(0), WGPUShaderStage.FRAGMENT.value)],
        "shadertoy_bgl",
    )
    var pl = device.create_pipeline_layout(bgl, "shadertoy_pl")
    var shader = device.create_shader_module_wgsl(SHADERTOY_WGSL, "shadertoy")
    var pipeline = device.create_render_pipeline(
        shader, "vs_main", "fs_main", canvas.surface_format(), pl,
        label="shadertoy_pipeline",
    )
    _ = shader^
    _ = pl^

    var bind_group = device.create_bind_group(
        bgl,
        [
            WGPUBindGroupEntry(
                null_opaque(), UInt32(0), uniforms.handle().raw,
                UInt64(0), WGPU_WHOLE_SIZE, null_opaque(), null_opaque(),
            )
        ],
        "shadertoy_bg",
    )
    _ = bgl^

    print("Rendering — close the window to quit.")
    var start_time = io.time.perf_counter()
    var frame_idx = 0

    while canvas.is_open():
        var elapsed = Float32((io.time.perf_counter() - start_time) / 1e9)
        canvas.poll()

        var frame = canvas.next_frame()
        if not frame.is_renderable():
            continue

        # iResolution, iTime, iMouse(0), iFrame, padding → 48 bytes.
        var u = List[Float32](capacity=12)
        u.append(Float32(WIN_W))   # iResolution.x
        u.append(Float32(WIN_H))   # iResolution.y
        u.append(Float32(1.0))     # iResolution.z
        u.append(elapsed)          # iTime
        u.append(Float32(0.0))     # iMouse.x
        u.append(Float32(0.0))     # iMouse.y
        u.append(Float32(0.0))     # iMouse.z
        u.append(Float32(0.0))     # iMouse.w
        u.append(Float32(frame_idx))  # iFrame
        u.append(Float32(0.0))
        u.append(Float32(0.0))
        u.append(Float32(0.0))
        device.queue_write_data(uniforms, UInt64(0), u)

        var enc = device.create_command_encoder("shadertoy_frame")
        var rpass = enc.begin_surface_clear_pass(
            frame.texture,
            WGPUColor(Float64(0), Float64(0), Float64(0), Float64(1)),
            "shadertoy_pass",
        )
        rpass.set_pipeline(pipeline)
        rpass.set_bind_group(UInt32(0), bind_group)
        rpass.draw(UInt32(6), UInt32(1), UInt32(0), UInt32(0))
        rpass^.end()

        device.queue_submit(enc^.finish())
        canvas.present()
        frame_idx += 1

    print("Done. Rendered", frame_idx, "frames.")
    _ = uniforms^
