"""
hello.mojo — Hello Triangle quickstart.

Renders a coloured triangle (RGB vertices) in a window.
If a triangle appears, the full stack works:
  wgpu-native → WGPULib (FFI) → Device → RenderPipeline → window.

Run:
    pixi run hello
"""

from wgpu.gpu import GPU
from wgpu._ffi.types import OpaquePtr
from wgpu._ffi.structs import WGPUColor
from rendercanvas import RenderCanvas
from std import io

# ---------------------------------------------------------------------------
# WGSL shader — one vertex + one fragment entry point
# ---------------------------------------------------------------------------


def main() raises:
    # 1. Boot the GPU stack
    var gpu    = GPU()
    var device = gpu.request_device()

    # 2. Open a window (800 × 600, GLFW-backed)
    var canvas = RenderCanvas(gpu, device, 800, 600, "wgpu-mojo: hello triangle")

    # 3. Compile the WGSL shader
    var shader = device.create_shader_module_wgsl(open("wgsl/hello-fire.wgsl", "r").read(), "hello-fire")

    # 4. Build render pipeline (convenience overload handles all boilerplate)
    var layout = device.create_pipeline_layout(List[OpaquePtr](), "hello_layout")
    var pipeline = device.create_render_pipeline(
        shader, "vs_main", "fs_main",
        canvas.surface_format(), layout,
        primitive_topology=UInt32(4),  # TriangleStrip
    )

    print("Window open — close it to exit.")

    # 6. Render loop
    while canvas.is_open():
        canvas.poll()

        var frame = canvas.next_frame()
        if not frame.is_renderable():
            continue

        var enc   = device.create_command_encoder("frame")
        var rpass = enc.begin_surface_clear_pass(
            frame.texture,
            WGPUColor(Float64(0), Float64(0), Float64(0), Float64(1)),
            "frame_pass",
        )
        rpass.set_pipeline(pipeline)
        rpass.draw(UInt32(3), UInt32(1), UInt32(0), UInt32(0))  # 3 vertices
        rpass^.end()

        # Submit and present
        var cmd = enc^.finish()
        device.queue_submit(cmd)
        canvas.present()

    print("Done.")
