// fire_compute.wgsl — Doom-style cellular automaton fire simulation.
//
// Ping-pong buffer layout:
//   binding(0) fire_in  — previous frame state (read)
//   binding(1) fire_out — current frame state  (write)
//   binding(2) params   — simulation constants + time
//
// Dispatch: (FIRE_W/8, FIRE_H/8, 1) workgroups

struct Params {
    width:  f32,   // cast to u32 in shader
    height: f32,
    time:   f32,
    frame:  f32,
}

@group(0) @binding(0) var<storage, read>       fire_in  : array<f32>;
@group(0) @binding(1) var<storage, read_write> fire_out : array<f32>;
@group(0) @binding(2) var<uniform>             params   : Params;

// Low-quality but fast scalar hash for per-cell noise/decay variation
fn hash(n: f32) -> f32 {
    return fract(sin(n) * 43758.5453123);
}

fn sample(xi: i32, yi: i32) -> f32 {
    let W = i32(params.width);
    let H = i32(params.height);
    let cx = clamp(xi, 0, W - 1);
    let cy = clamp(yi, 0, H - 1);
    return fire_in[u32(cy * W + cx)];
}

@compute @workgroup_size(8, 8)
fn cs_main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let x  = i32(gid.x);
    let y  = i32(gid.y);
    let W  = i32(params.width);
    let H  = i32(params.height);

    if x >= W || y >= H { return; }

    let idx = u32(y * W + x);
    let fx  = f32(x) / f32(W);   // normalized 0..1

    // Bottom row: constant maximum heat — acts as the ignition source
    if y == H - 1 {
        fire_out[idx] = 1.0;
        return;
    }

    // Row just above bottom: high heat with time-varying turbulence so the
    // flame base "breathes" organically
    if y == H - 2 {
        let flicker = hash(fx * 23.7 + params.time * 3.1) * 0.35;
        fire_out[idx] = clamp(0.65 + flicker, 0.0, 1.0);
        return;
    }

    // All other rows: Doom-style diffusion upward.
    // Average four neighbours from the row below + row two below,
    // then subtract a small per-pixel decay for the cooling effect.
    let a = sample(x - 1, y + 1);
    let b = sample(x,     y + 1);
    let c = sample(x + 1, y + 1);
    let d = sample(x,     y + 2);

    let avg = (a + b + c + d) * 0.25;

    // Spatially-varying decay keeps the flame shape organic and prevents
    // perfectly symmetric patterns.  The frame counter drives slow drift.
    let seed  = f32(x * 7 + y * 13) + params.frame * 0.07;
    let decay = 0.003 + hash(seed) * 0.006;

    fire_out[idx] = max(0.0, avg - decay);
}
