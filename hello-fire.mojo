""" Hello-fire.mojo — Hello Fire quickstart.

Renders a coloured fire effect (RGB vertices) in a window.
If the fire effect appears, the full stack works:
  wgpu-native → WGPULib (FFI) → Device → RenderPipeline → window.

Run:
    pixi run hello
"""

from wgpu.instance import Instance
from wgpu._ffi.types import WGPUBufferUsage
from wgpu._ffi.structs import WGPUColor
from wgpu.rendercanvas import RenderCanvas
from std import io

# ---------------------------------------------------------------------------
# WGSL shader — one vertex + one fragment entry point
# ---------------------------------------------------------------------------

def main() raises:
    # 1. Create an instance, choose an adapter, then create a device.
    var instance = Instance()
    var adapter  = instance.request_adapter()
    var device   = adapter.request_device()

    # 2. Open a window (800 × 600, GLFW-backed)
    var canvas = RenderCanvas(adapter, device, 800, 600, "wgpu-mojo: hello triangle")

    # 3. Compile the WGSL shader
    var shader = device.create_shader_module_wgsl(open("wgsl/hello-fire.wgsl", "r").read(), "hello-fire")
    
    # 4. Build render pipeline (convenience overload handles all boilerplate)
    var layout = device.create_pipeline_layout(List[OpaquePointer[MutExternalOrigin]](), "hello_layout")
    var pipeline = device.create_render_pipeline(
        shader, "vs_main", "fs_main",
        canvas.surface_format(), layout,
        primitive_topology=UInt32(4),  # TriangleStrip
    )

    # 建立一個大小為 4 bytes (一個 f32) 的 Uniform Buffer
    var uniform_buffer = device.create_buffer(
        size = 4, 
        usage = WGPUBufferUsage(64 | 8), # UNIFORM | COPY_DST
        label = "Time Uniform Buffer"
    )
    print("Window open — close it to exit.")
    var start_time = io.time.perf_counter()
    # 6. Render loop
    while canvas.is_open():
        var current_time = Float32((io.time.perf_counter() - start_time) / 1e9)
        canvas.poll()

        var frame = canvas.next_frame()
        if not frame.is_renderable():
            continue

        var time_data = List[Float32](capacity=1)
        time_data.append(current_time)
        device.queue_write_data(uniform_buffer, 0, time_data)
        var enc   = device.create_command_encoder("frame")
        var rpass = enc.begin_surface_clear_pass(
            frame.texture,
            WGPUColor(Float64(0), Float64(0), Float64(0), Float64(1)),
            "frame_pass",
        )
        rpass.set_pipeline(pipeline)
        # rpass.set_bind_group(0, uniform_buffer, 0, 1)

        rpass.draw(UInt32(4), UInt32(1), UInt32(0), UInt32(0))  # 4 vertices
        rpass^.end()

        # Submit and present
        var cmd = enc^.finish()
        device.queue_submit(cmd)
        canvas.present()

    print("Done.")