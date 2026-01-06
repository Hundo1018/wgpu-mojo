"""
examples/triangle_window.mojo — Hello Triangle in a real window.

Renders a coloured triangle (RGB vertices) on a black background.
This is the classical first rendering test: if the triangle appears,
the full pipeline (GLFW → Surface → RenderPipeline → draw → present) works.

Run:
    pixi run example-triangle
"""

from wgpu.gpu import GPU
from wgpu._ffi.types import (
    OpaquePtr,
)
from wgpu._ffi.structs import (
    WGPUColor,
)
from rendercanvas import RenderCanvas


comptime TRIANGLE_WGSL = """
struct VertexOutput {
    @builtin(position) pos: vec4<f32>,
    @location(0) color: vec3<f32>,
}

@vertex
fn vs_main(@builtin(vertex_index) idx: u32) -> VertexOutput {
    var positions = array<vec2<f32>, 3>(
        vec2<f32>( 0.0,  0.5),
        vec2<f32>(-0.5, -0.5),
        vec2<f32>( 0.5, -0.5),
    );
    var colors = array<vec3<f32>, 3>(
        vec3<f32>(1.0, 0.0, 0.0),
        vec3<f32>(0.0, 1.0, 0.0),
        vec3<f32>(0.0, 0.0, 1.0),
    );
    var out: VertexOutput;
    out.pos   = vec4<f32>(positions[idx], 0.0, 1.0);
    out.color = colors[idx];
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    return vec4<f32>(in.color, 1.0);
}
"""


def main() raises:
    # --- GPU + window setup -----------------------------------------------
    var gpu    = GPU()
    var device = gpu.request_device()
    var canvas = RenderCanvas(gpu, device, 800, 600, "wgpu-mojo: hello triangle")

    # --- Compile shader ---------------------------------------------------
    var shader = device.create_shader_module_wgsl(TRIANGLE_WGSL, "triangle")

    # --- Build render pipeline --------------------------------------------
    var pl = device.create_pipeline_layout(List[OpaquePtr](), "tri_layout")
    var pipeline = device.create_render_pipeline(
        shader, "vs_main", "fs_main",
        canvas.surface_format(), pl,
        primitive_topology=UInt32(4),  # TriangleStrip
    )

    print("Rendering triangle — close the window to quit.")

    # --- Render loop -------------------------------------------------------
    while canvas.is_open():
        canvas.poll()

        var frame = canvas.next_frame()
        if not frame.is_renderable():
            continue

        var enc   = device.create_command_encoder("frame")
        var rpass = enc.begin_surface_clear_pass(
            frame.texture,
            WGPUColor(Float64(0.0), Float64(0.0), Float64(0.0), Float64(1.0)),
            "frame_pass",
        )
        rpass.set_pipeline(pipeline)
        rpass.draw(UInt32(3), UInt32(1), UInt32(0), UInt32(0))
        rpass^.end()

        var cmd = enc^.finish()
        device.queue_submit(cmd)

        canvas.present()

    print("Window closed.")
