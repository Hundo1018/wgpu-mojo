"""
examples/shadertoy_sdf.mojo — ShaderToy host, tier 2: animated 2D SDF metaballs.

Same low-friction host as examples/shadertoy.mojo (iResolution / iTime / iMouse /
iFrame uniforms, fullscreen `mainImage`), but the WGSL now shows the 2D
signed-distance-field toolkit you see all over https://www.shadertoy.com/ :
  * aspect-correct, centred coordinates
  * a distance function (sdCircle) + smooth-min (smin) to blend shapes
  * fill via smoothstep on the distance, plus a 1/d glow falloff

Difficulty ladder:
    1. plasma / gradient        examples/shadertoy.mojo
    2. 2D SDF shapes / metaballs ← you are here
    3. raymarching              (next)

Run:
    pixi run example-shadertoy-sdf
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
# WGSL — edit only `mainImage` to make a new effect (ShaderToy convention).
# ---------------------------------------------------------------------------
comptime SDF_WGSL = """
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

@vertex
fn vs_main(@builtin(vertex_index) idx: u32) -> @builtin(position) vec4<f32> {
    var p = array<vec2<f32>, 6>(
        vec2<f32>(-1.0, -1.0), vec2<f32>(1.0, -1.0), vec2<f32>(-1.0, 1.0),
        vec2<f32>(-1.0, 1.0), vec2<f32>(1.0, -1.0), vec2<f32>(1.0, 1.0),
    );
    return vec4<f32>(p[idx], 0.0, 1.0);
}

// ===========================================================================
// EDIT BELOW — 2D signed-distance-field scene.
// ===========================================================================
fn sdCircle(p: vec2<f32>, r: f32) -> f32 {
    return length(p) - r;
}

// Polynomial smooth-min: blends two distance fields into a gooey join.
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn mainImage(fragColor: ptr<function, vec4<f32>>, fragCoord: vec2<f32>) {
    // Centred, aspect-correct coords: y in [-1, 1].
    let p = (2.0 * fragCoord - U.iResolution.xy) / U.iResolution.y;
    let t = U.iTime;

    // Three orbiting blobs fused with smin -> metaballs.
    var d = 1e9;
    for (var i = 0; i < 3; i = i + 1) {
        let a = t * (0.6 + 0.2 * f32(i)) + f32(i) * 2.09440;
        let c = 0.55 * vec2<f32>(cos(a), sin(a * 1.3));
        d = smin(d, sdCircle(p - c, 0.25), 0.25);
    }

    let base = 0.5 + 0.5 * cos(t * 0.5 + p.xyx + vec3<f32>(0.0, 2.0, 4.0));
    let fill = smoothstep(0.012, -0.012, d);   // crisp interior
    let glow = 0.045 / (abs(d) + 0.045);       // distance-based halo

    var col = vec3<f32>(0.02, 0.03, 0.06);     // background
    col = mix(col, base, fill);
    col = col + base * glow * 0.5;
    *fragColor = vec4<f32>(col, 1.0);
}
// ===========================================================================

@fragment
fn fs_main(@builtin(position) frag: vec4<f32>) -> @location(0) vec4<f32> {
    let fragCoord = vec2<f32>(frag.x, U.iResolution.y - frag.y);
    var col = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    mainImage(&col, fragCoord);
    return col;
}
"""


def main() raises:
    print("=== wgpu-mojo: ShaderToy host (tier 2 — 2D SDF metaballs) ===")
    var instance = Instance()
    var adapter = instance.request_adapter()
    var device = adapter.request_device()
    var canvas = RenderCanvas(
        adapter, device, WIN_W, WIN_H, "wgpu-mojo · ShaderToy SDF"
    )

    var uniforms = device.create_buffer(
        UInt64(48),
        WGPUBufferUsage.UNIFORM | WGPUBufferUsage.COPY_DST,
        label="sdf_uniforms",
    )

    var bgl = device.create_bind_group_layout(
        [BGL.buffer_uniform(UInt32(0), WGPUShaderStage.FRAGMENT.value)],
        "sdf_bgl",
    )
    var pl = device.create_pipeline_layout(bgl, "sdf_pl")
    var shader = device.create_shader_module_wgsl(SDF_WGSL, "shadertoy_sdf")
    var pipeline = device.create_render_pipeline(
        shader, "vs_main", "fs_main", canvas.surface_format(), pl,
        label="sdf_pipeline",
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
        "sdf_bg",
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

        var u = List[Float32](capacity=12)
        u.append(Float32(WIN_W))
        u.append(Float32(WIN_H))
        u.append(Float32(1.0))
        u.append(elapsed)
        u.append(Float32(0.0))
        u.append(Float32(0.0))
        u.append(Float32(0.0))
        u.append(Float32(0.0))
        u.append(Float32(frame_idx))
        u.append(Float32(0.0))
        u.append(Float32(0.0))
        u.append(Float32(0.0))
        device.queue_write_data(uniforms, UInt64(0), u)

        var enc = device.create_command_encoder("sdf_frame")
        var rpass = enc.begin_surface_clear_pass(
            frame.texture,
            WGPUColor(Float64(0), Float64(0), Float64(0), Float64(1)),
            "sdf_pass",
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
