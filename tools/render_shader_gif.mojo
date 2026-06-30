"""
tools/render_shader_gif.mojo — headless, deterministic frame renderer.

Renders the plasma and metaballs fragment effects entirely on the GPU via a
compute shader (one pixel per invocation, written into a storage buffer) and
reads each frame back to the CPU as raw RGBA. Frames are produced for a sequence
of `time` values, so the output genuinely animates — no screen capture involved.

This exists because the wgpu surface in the windowed examples presents via a GPU
flip that screen grabbers (x11grab) cannot record: a captured stream of the
window is frozen even though the window animates on screen. Rendering off-screen
and reading the pixels back (storage buffer -> COPY_SRC -> MAP_READ staging) is
the only reliable way to produce the README GIFs.

Output: raw RGBA streams at /tmp/<name>.rgba (N frames of W*H*4 bytes), which
scripts/make-gifs.sh feeds to ffmpeg. Run via `pixi run render-gifs`.
"""

from wgpu import (
    Instance,
    WGPUBufferUsage, WGPUShaderStage, WGPU_WHOLE_SIZE,
    WGPUBindGroupEntry, BGL,
)
from wgpu._ffi.nulls import null_opaque
from wgpu.device import Device

comptime W = 480
comptime H = 270
comptime FPS = 16
comptime SECONDS = 3
comptime N_FRAMES = FPS * SECONDS
comptime BYTES = W * H * 4

# Compute wrapper: binding 0 = output (packed RGBA u32), binding 1 = params
# [W, H, time, frame]. `SHADE` is spliced in to choose the effect.
comptime WRAPPER_HEAD = """
@group(0) @binding(0) var<storage, read_write> out_buf: array<u32>;
@group(0) @binding(1) var<storage, read_write> params: array<f32>;
"""

comptime WRAPPER_MAIN = """
@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let w = u32(params[0]);
    let h = u32(params[1]);
    if (gid.x >= w || gid.y >= h) { return; }
    // bottom-left origin, matching the windowed examples
    let frag = vec2<f32>(f32(gid.x), f32(h - 1u - gid.y));
    let res = vec2<f32>(f32(w), f32(h));
    let c = clamp(shade(frag, params[2], res), vec3<f32>(0.0), vec3<f32>(1.0));
    let r = u32(c.x * 255.0 + 0.5);
    let g = u32(c.y * 255.0 + 0.5);
    let b = u32(c.z * 255.0 + 0.5);
    out_buf[gid.y * w + gid.x] = r | (g << 8u) | (b << 16u) | (255u << 24u);
}
"""

comptime PLASMA_SHADE = """
fn shade(frag: vec2<f32>, time: f32, res: vec2<f32>) -> vec3<f32> {
    let uv = frag / res;
    let t = time;
    var v = 0.0;
    v = v + sin((uv.x * 10.0) + t);
    v = v + sin((uv.y * 10.0 + t) * 0.5);
    v = v + sin((uv.x * 10.0 + uv.y * 10.0 + t) * 0.5);
    let cx = uv.x + 0.5 * sin(t * 0.2);
    let cy = uv.y + 0.5 * cos(t * 0.3);
    v = v + sin(sqrt(cx * cx + cy * cy) * 20.0 + t);
    v = v * 0.5;
    return vec3<f32>(
        sin(v * 3.14159), sin(v * 3.14159 + 2.09440), sin(v * 3.14159 + 4.18879)
    ) * 0.5 + vec3<f32>(0.5);
}
"""

comptime RAYMARCH_SHADE = """
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
fn shade(frag: vec2<f32>, time: f32, res: vec2<f32>) -> vec3<f32> {
    let uv = (2.0 * frag - res) / res.y;
    let t = time;
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
"""

comptime METABALLS_SHADE = """
fn sd_circle(p: vec2<f32>, r: f32) -> f32 { return length(p) - r; }
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}
fn shade(frag: vec2<f32>, time: f32, res: vec2<f32>) -> vec3<f32> {
    let p = (2.0 * frag - res) / res.y;
    let t = time;
    var d = 1e9;
    for (var i = 0; i < 3; i = i + 1) {
        let a = t * (0.6 + 0.2 * f32(i)) + f32(i) * 2.09440;
        let c = 0.55 * vec2<f32>(cos(a), sin(a * 1.3));
        d = smin(d, sd_circle(p - c, 0.25), 0.25);
    }
    let base = 0.5 + 0.5 * cos(t * 0.5 + p.xyx + vec3<f32>(0.0, 2.0, 4.0));
    let fill = smoothstep(0.012, -0.012, d);
    let glow = 0.045 / (abs(d) + 0.045);
    var col = vec3<f32>(0.02, 0.03, 0.06);
    col = mix(col, base, fill);
    return col + base * glow * 0.5;
}
"""


def render_scene(mut device: Device, name: String, shade_wgsl: String) raises:
    var wgsl = WRAPPER_HEAD + shade_wgsl + WRAPPER_MAIN
    var shader = device.create_shader_module_wgsl(wgsl, name + "_shader")
    var bgl = device.create_bind_group_layout(
        [
            BGL.buffer_storage(UInt32(0), WGPUShaderStage.COMPUTE.value),
            BGL.buffer_storage(UInt32(1), WGPUShaderStage.COMPUTE.value),
        ],
        name + "_bgl",
    )
    var layout = device.create_pipeline_layout(bgl, name + "_layout")
    var pipeline = device.create_compute_pipeline(shader, "main", layout, name + "_pipe")
    _ = shader^
    _ = layout^

    var out_buf = device.create_buffer(
        UInt64(BYTES), WGPUBufferUsage.STORAGE | WGPUBufferUsage.COPY_SRC, label=name + "_out"
    )
    var params = device.create_buffer(
        UInt64(16), WGPUBufferUsage.STORAGE | WGPUBufferUsage.COPY_DST, label=name + "_params"
    )
    var staging = device.create_buffer(
        UInt64(BYTES), WGPUBufferUsage.MAP_READ | WGPUBufferUsage.COPY_DST, label=name + "_stage"
    )

    var bg = device.create_bind_group(
        bgl,
        [
            WGPUBindGroupEntry(
                null_opaque(), UInt32(0), out_buf.handle().raw,
                UInt64(0), WGPU_WHOLE_SIZE, null_opaque(), null_opaque()),
            WGPUBindGroupEntry(
                null_opaque(), UInt32(1), params.handle().raw,
                UInt64(0), WGPU_WHOLE_SIZE, null_opaque(), null_opaque()),
        ],
        name + "_bg",
    )
    _ = bgl^

    var gx = UInt32((W + 7) // 8)
    var gy = UInt32((H + 7) // 8)
    var path = "/tmp/" + name + ".rgba"

    with open(path, "w") as f:
        for frame in range(N_FRAMES):
            var pd = List[Float32](capacity=4)
            pd.append(Float32(W))
            pd.append(Float32(H))
            pd.append(Float32(frame) / Float32(FPS))
            pd.append(Float32(frame))
            device.queue_write_data(params, UInt64(0), pd)

            var enc = device.create_command_encoder(name + "_enc")
            var cpass = enc.begin_compute_pass(name + "_pass")
            cpass.set_pipeline(pipeline)
            cpass.set_bind_group(UInt32(0), bg)
            cpass.dispatch_workgroups(gx, gy, UInt32(1))
            cpass^.end()
            enc.copy_buffer_to_buffer(out_buf, UInt64(0), staging, UInt64(0), UInt64(BYTES))
            device.queue_submit(enc^.finish(name + "_cmd"))
            _ = device.poll(True)

            var raw = staging.map_read()
            var src = raw.bitcast[UInt32]()
            var bytes = List[UInt8](capacity=BYTES)
            for i in range(W * H):
                var px = src[i]
                bytes.append(UInt8(px & 0xFF))
                bytes.append(UInt8((px >> 8) & 0xFF))
                bytes.append(UInt8((px >> 16) & 0xFF))
                bytes.append(UInt8((px >> 24) & 0xFF))
            staging.unmap()
            f.write_bytes(Span(bytes))

    _ = pipeline^
    _ = bg^
    _ = out_buf^
    _ = params^
    _ = staging^
    print("rendered", name, ":", N_FRAMES, "frames", W, "x", H, "->", path)


def main() raises:
    print("=== headless shader renderer:", W, "x", H, "@", FPS, "fps,", N_FRAMES, "frames ===")
    var instance = Instance()
    var device = instance.request_adapter().request_device()
    render_scene(device, "plasma", PLASMA_SHADE)
    render_scene(device, "metaballs", METABALLS_SHADE)
    render_scene(device, "raymarch", RAYMARCH_SHADE)
    _ = device^
    _ = instance^
    print("done — feed /tmp/*.rgba to scripts/make-gifs.sh")
