"""
examples/raymarch.mojo — an animated raymarched 3D scene (fragment shader).

Same fullscreen fragment-shader host as examples/plasma.mojo (resolution / time /
mouse / frame uniforms, a single `shade` function), but `shade` now raymarches a
small 3D signed-distance scene: three orbiting spheres fused with a smooth-min,
floating over a colourful ground plane, lit with a single diffuse light while the
camera orbits. This is the hardest of the fragment-shader examples (plasma → 2D
SDF → raymarching).

Run:
    pixi run example-raymarch
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

comptime RAYMARCH_WGSL = """
struct Uniforms {
    resolution: vec3<f32>,
    time: f32,
    mouse: vec4<f32>,
    frame: f32,
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
// EDIT BELOW — raymarched signed-distance scene.
// ===========================================================================
fn sd_sphere(p: vec3<f32>, r: f32) -> f32 { return length(p) - r; }
fn smin3(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}
fn scene(p: vec3<f32>, t: f32) -> f32 {
    var d = 1e9;
    for (var i = 0; i < 3; i = i + 1) {
        let a = t * 0.7 + f32(i) * 2.09440;
        let c = vec3<f32>(cos(a) * 1.1, sin(a * 1.3) * 0.6, sin(a) * 1.1);
        d = smin3(d, sd_sphere(p - c, 0.6), 0.5);
    }
    return min(d, p.y + 1.2);
}
fn normal_at(p: vec3<f32>, t: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        scene(p + e.xyy, t) - scene(p - e.xyy, t),
        scene(p + e.yxy, t) - scene(p - e.yxy, t),
        scene(p + e.yyx, t) - scene(p - e.yyx, t)));
}

fn shade(frag_coord: vec2<f32>) -> vec3<f32> {
    let uv = (2.0 * frag_coord - U.resolution.xy) / U.resolution.y;
    let t = U.time;
    let ca = t * 0.3;
    let ro = vec3<f32>(sin(ca) * 4.0, 1.5, cos(ca) * 4.0);
    let fwd = normalize(-ro);
    let rt = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), fwd));
    let up = cross(fwd, rt);
    let rd = normalize(uv.x * rt + uv.y * up + 1.6 * fwd);

    var dist = 0.0;
    var hit = false;
    for (var i = 0; i < 90; i = i + 1) {
        let p = ro + rd * dist;
        let dd = scene(p, t);
        if (dd < 0.001) { hit = true; break; }
        dist = dist + dd;
        if (dist > 30.0) { break; }
    }

    var col = vec3<f32>(0.05, 0.06, 0.10) + 0.10 * rd.y;
    if (hit) {
        let p = ro + rd * dist;
        let n = normal_at(p, t);
        let ld = normalize(vec3<f32>(2.0, 4.0, 1.0) - p);
        let diff = max(dot(n, ld), 0.0);
        let base = 0.5 + 0.5 * cos(t + p.xyx * 0.5 + vec3<f32>(0.0, 2.0, 4.0));
        col = base * (0.2 + diff);
        col = mix(col, vec3<f32>(0.05, 0.06, 0.10), 1.0 - exp(-0.02 * dist * dist));
    }
    return pow(clamp(col, vec3<f32>(0.0), vec3<f32>(1.0)), vec3<f32>(0.4545));
}
// ===========================================================================

@fragment
fn fs_main(@builtin(position) frag: vec4<f32>) -> @location(0) vec4<f32> {
    let frag_coord = vec2<f32>(frag.x, U.resolution.y - frag.y);
    return vec4<f32>(shade(frag_coord), 1.0);
}
"""


def main() raises:
    print("=== wgpu-mojo: raymarch (3D SDF fragment shader) ===")
    var instance = Instance()
    var adapter = instance.request_adapter()
    var device = adapter.request_device()
    var canvas = RenderCanvas(adapter, device, WIN_W, WIN_H, "wgpu-mojo · raymarch")

    var uniforms = device.create_buffer(
        UInt64(48),
        WGPUBufferUsage.UNIFORM | WGPUBufferUsage.COPY_DST,
        label="raymarch_uniforms",
    )

    var bgl = device.create_bind_group_layout(
        [BGL.buffer_uniform(UInt32(0), WGPUShaderStage.FRAGMENT.value)],
        "raymarch_bgl",
    )
    var pl = device.create_pipeline_layout(bgl, "raymarch_pl")
    var shader = device.create_shader_module_wgsl(RAYMARCH_WGSL, "raymarch")
    var pipeline = device.create_render_pipeline(
        shader, "vs_main", "fs_main", canvas.surface_format(), pl,
        label="raymarch_pipeline",
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
        "raymarch_bg",
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

        var enc = device.create_command_encoder("raymarch_frame")
        var rpass = enc.begin_surface_clear_pass(
            frame.texture,
            WGPUColor(Float64(0), Float64(0), Float64(0), Float64(1)),
            "raymarch_pass",
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
