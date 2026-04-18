/*
# ---------------------------------------------------------------------------
# WGSL shader — one vertex + one fragment entry point
# ---------------------------------------------------------------------------
*/
struct VertexOut {
    @builtin(position) pos: vec4<f32>,
    @location(0)       col: vec3<f32>,
}

@vertex
fn vs_main(@builtin(vertex_index) i: u32) -> VertexOut {
    var pos = array<vec2<f32>, 3>(
        vec2( 0.0,  0.5),
        vec2(-0.5, -0.5),
        vec2( 0.5, -0.5),
    );
    var col = array<vec3<f32>, 3>(
        vec3(1.0, 0.0, 0.0),  // red
        vec3(0.0, 1.0, 0.0),  // green
        vec3(0.0, 0.0, 1.0),  // blue
    );
    var out: VertexOut;
    out.pos = vec4<f32>(pos[i], 0.0, 1.0);
    out.col = col[i];
    return out;
}

@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4<f32> {
    return vec4<f32>(in.col, 1.0);
}