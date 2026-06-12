// fire_render.wgsl — Fullscreen-quad renderer for the fire simulation buffer.
//
// binding(0) fire   — the "current" fire state buffer (read-only)
// binding(1) params — simulation dimensions

struct Params {
    width:  f32,
    height: f32,
    time:   f32,
    frame:  f32,
}

@group(0) @binding(0) var<storage, read> fire   : array<f32>;
@group(0) @binding(1) var<uniform>       params : Params;

struct VertexOut {
    @builtin(position) pos : vec4<f32>,
    @location(0)       uv  : vec2<f32>,
}

// Fullscreen quad in two triangles (NDC clip-space, no vertex buffer)
@vertex
fn vs_main(@builtin(vertex_index) idx: u32) -> VertexOut {
    var positions = array<vec2<f32>, 6>(
        vec2<f32>(-1.0, -1.0),
        vec2<f32>( 1.0, -1.0),
        vec2<f32>(-1.0,  1.0),
        vec2<f32>(-1.0,  1.0),
        vec2<f32>( 1.0, -1.0),
        vec2<f32>( 1.0,  1.0),
    );
    // UV: (0,0) = top-left of fire grid, (1,1) = bottom-right
    var uvs = array<vec2<f32>, 6>(
        vec2<f32>(0.0, 1.0),
        vec2<f32>(1.0, 1.0),
        vec2<f32>(0.0, 0.0),
        vec2<f32>(0.0, 0.0),
        vec2<f32>(1.0, 1.0),
        vec2<f32>(1.0, 0.0),
    );
    var out: VertexOut;
    out.pos = vec4<f32>(positions[idx], 0.0, 1.0);
    out.uv  = uvs[idx];
    return out;
}

// Bilinear interpolation over the scalar fire buffer.
// The display window is larger than the sim grid, so bilinear upscaling
// gives a smooth, painterly quality instead of blocky pixels.
fn load_fire(xi: u32, yi: u32) -> f32 {
    let W = u32(params.width);
    let H = u32(params.height);
    let cx = min(xi, W - 1u);
    let cy = min(yi, H - 1u);
    return fire[cy * W + cx];
}

fn sample_bilinear(uv: vec2<f32>) -> f32 {
    let W  = params.width;
    let H  = params.height;
    let px = uv.x * W - 0.5;
    let py = uv.y * H - 0.5;
    let x0 = u32(max(floor(px), 0.0));
    let y0 = u32(max(floor(py), 0.0));
    let x1 = x0 + 1u;
    let y1 = y0 + 1u;
    let fx = fract(px);
    let fy = fract(py);

    let v00 = load_fire(x0, y0);
    let v10 = load_fire(x1, y0);
    let v01 = load_fire(x0, y1);
    let v11 = load_fire(x1, y1);

    return mix(mix(v00, v10, fx), mix(v01, v11, fx), fy);
}

// Five-stop gradient from black through Mojo's orange-gold brand palette
// to near-white at peak temperature.
fn fire_palette(t: f32) -> vec3<f32> {
    let black  = vec3<f32>(0.000, 0.000, 0.000);   // 0.0
    let dkred  = vec3<f32>(0.502, 0.000, 0.000);   // 0.2
    let orange = vec3<f32>(1.000, 0.200, 0.000);   // 0.4
    let gold   = vec3<f32>(1.000, 0.600, 0.000);   // 0.6
    let yellow = vec3<f32>(1.000, 0.902, 0.125);   // 0.8
    let white  = vec3<f32>(1.000, 0.992, 0.902);   // 1.0

    if t < 0.2 {
        return mix(black,  dkred,  t * 5.0);
    } else if t < 0.4 {
        return mix(dkred,  orange, (t - 0.2) * 5.0);
    } else if t < 0.6 {
        return mix(orange, gold,   (t - 0.4) * 5.0);
    } else if t < 0.8 {
        return mix(gold,   yellow, (t - 0.6) * 5.0);
    } else {
        return mix(yellow, white,  (t - 0.8) * 5.0);
    }
}

@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4<f32> {
    let heat  = sample_bilinear(in.uv);
    let color = fire_palette(clamp(heat, 0.0, 1.0));
    return vec4<f32>(color, 1.0);
}
