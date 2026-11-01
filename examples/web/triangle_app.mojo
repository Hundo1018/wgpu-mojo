"""
The clear + triangle app shared by the native and web drivers (#14).

It only knows a device, a colour format and a texture to draw into; who owns
the loop and the surface is the driver's business:
    triangle_native.mojo  GLFW window, `while` loop
    triangle_web.mojo     HTML canvas, exported frame() called per animation frame

A solid-colour triangle, so a captured frame can be checked pixel by pixel:
CLEAR at the corners, TRIANGLE at the centre.
"""

from wgpu.device import Device
from wgpu.pipeline import RenderPipeline
from wgpu._ffi.types import WGPUTextureHandle
from wgpu._ffi.structs import WGPUColor

# Exact in 8 bits (n/255 only for n = 0 and 255), so pixel checks are exact.
comptime CLEAR = WGPUColor(0.0, 0.0, 1.0, 1.0)
comptime TRIANGLE_R: Float64 = 1.0
comptime TRIANGLE_G: Float64 = 1.0
comptime TRIANGLE_B: Float64 = 0.0

comptime TRIANGLE_WGSL = """
@vertex
fn vs_main(@builtin(vertex_index) idx: u32) -> @builtin(position) vec4<f32> {
    var positions = array<vec2<f32>, 3>(
        vec2<f32>( 0.0,  0.6),
        vec2<f32>(-0.6, -0.6),
        vec2<f32>( 0.6, -0.6),
    );
    return vec4<f32>(positions[idx], 0.0, 1.0);
}

@fragment
fn fs_main() -> @location(0) vec4<f32> {
    return vec4<f32>(1.0, 1.0, 0.0, 1.0);
}
"""


struct TriangleApp(Movable):
    var _pipeline: RenderPipeline

    def __init__(out self, device: Device, color_format: UInt32) raises:
        var shader = device.create_shader_module_wgsl(TRIANGLE_WGSL, "triangle")
        var layout = device.create_pipeline_layout(
            List[OpaquePointer[MutUntrackedOrigin]](), "triangle_layout"
        )
        self._pipeline = device.create_render_pipeline(
            shader, "vs_main", "fs_main", color_format, layout,
            primitive_topology=UInt32(4),  # TriangleList
        )

    def __init__(out self, *, deinit move: Self):
        self._pipeline = move._pipeline^

    def render(self, device: Device, target: WGPUTextureHandle) raises:
        var enc = device.create_command_encoder("frame")
        var rpass = enc.begin_surface_clear_pass(target, CLEAR, "frame_pass")
        rpass.set_pipeline(self._pipeline)
        rpass.draw(UInt32(3), UInt32(1), UInt32(0), UInt32(0))
        rpass^.end()
        device.queue_submit(enc^.finish())
