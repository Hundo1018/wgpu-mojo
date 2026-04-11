"""
examples/clear_screen.mojo — Minimal on-screen rendering verification.

Renders a solid cornflower-blue background to a GLFW window.
If you see a blue window, the full pipeline works:
  GLFW window → wgpu Surface → swapchain → render pass (clear) → present

Run:
    pixi run example-clear
"""

from wgpu.gpu import request_adapter
from wgpu._ffi.lib import WGPULib
from wgpu._ffi.types import OpaquePtr
from wgpu._ffi.structs import (
    WGPURenderPassDescriptor, WGPURenderPassColorAttachment,
    WGPURenderPassDepthStencilAttachment, WGPUPassTimestampWrites,
    WGPUTextureViewDescriptor, WGPUStringView, WGPUColor,
)
from wgpu.texture import TextureView
from rendercanvas import RenderCanvas


def main() raises:
    # --- GPU setup -------------------------------------------------------
    var inst   = request_adapter()
    var device = inst.request_device()

    # --- Window + Surface ------------------------------------------------
    var canvas = RenderCanvas(inst, device, 800, 600, "wgpu-mojo: clear screen")

    print("Window open — cornflower blue should be visible. Close window to quit.")

    # --- Render loop -----------------------------------------------------
    while canvas.is_open():
        canvas.poll()

        var frame = canvas.next_frame()
        if frame.status != 1 and frame.status != 2:
            continue  # surface lost / timeout — skip frame

        # Create a default view on the swapchain texture
        var view_h = device._lib.texture_create_view(
            frame.texture,
            UnsafePointer[WGPUTextureViewDescriptor, MutExternalOrigin](),
        )
        var lib_for_view = WGPULib()
        var view = TextureView(lib_for_view^, view_h)

        # Build render pass: clear to cornflower blue, no draw calls
        var color_att_p = alloc[WGPURenderPassColorAttachment](1)
        color_att_p[0] = WGPURenderPassColorAttachment(
            OpaquePtr(),
            view.handle(),
            UInt32(0xFFFFFFFF),   # WGPU_DEPTH_SLICE_UNDEFINED
            OpaquePtr(),          # no resolve target
            UInt32(2),            # LoadOp.Clear
            UInt32(1),            # StoreOp.Store
            WGPUColor(
                Float64(0.392),   # cornflower blue R
                Float64(0.584),   # G
                Float64(0.929),   # B
                Float64(1.0),     # A
            ),
        )
        var rp_desc_p = alloc[WGPURenderPassDescriptor](1)
        rp_desc_p[0] = WGPURenderPassDescriptor(
            OpaquePtr(),
            WGPUStringView.null_view(),
            UInt(1),
            color_att_p,
            UnsafePointer[WGPURenderPassDepthStencilAttachment, MutExternalOrigin](),
            OpaquePtr(),
            UnsafePointer[WGPUPassTimestampWrites, MutExternalOrigin](),
        )

        var enc   = device.create_command_encoder("frame")
        var rpass = enc.begin_render_pass(rp_desc_p)
        _ = view^     # TextureView handle extracted; safe to drop
        rpass.end()
        color_att_p.free()
        rp_desc_p.free()

        var cmd = enc.finish()
        var cmds = List[OpaquePtr]()
        cmds.append(cmd)
        device.queue_submit(cmds)
        device._lib.command_buffer_release(cmd)

        canvas.present()

    print("Window closed.")
    _ = canvas^
    _ = device^
    _ = inst^
