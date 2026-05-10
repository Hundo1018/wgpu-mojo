"""
Examples/clear_screen.mojo — Minimal on-screen rendering verification.

Renders a solid cornflower-blue background to a GLFW window.
If you see a blue window, the full pipeline works:
  GLFW window → wgpu Surface → swapchain → render pass (clear) → present

Run:
    pixi run example-clear
"""

from wgpu.instance import Instance
from wgpu._ffi.structs import WGPUColor
from wgpu.rendercanvas import RenderCanvas


def main() raises:
    # --- GPU setup -------------------------------------------------------
    var instance = Instance()
    var adapter  = instance.request_adapter()
    var device   = adapter.request_device()

    # --- Window + Surface ------------------------------------------------
    var canvas = RenderCanvas(adapter, device, 800, 600, "wgpu-mojo: clear screen")

    print("Window open — cornflower blue should be visible. Close window to quit.")

    # --- Render loop -----------------------------------------------------
    while canvas.is_open():
        canvas.poll()

        var frame = canvas.next_frame()
        if not frame.is_renderable():
            continue  # surface lost / timeout — skip frame

        var enc   = device.create_command_encoder("frame")
        var rpass = enc.begin_surface_clear_pass(
            frame.texture,
            WGPUColor(
                Float64(0.392),
                Float64(0.584),
                Float64(0.929),
                Float64(1.0),
            ),
            "clear_pass",
        )
        rpass^.end()

        var cmd = enc^.finish()
        device.queue_submit(cmd)

        canvas.present()

    print("Window closed.")
