"""
hello.mojo — Hello Triangle quickstart.

Renders a coloured triangle (RGB vertices) in a window.
If a triangle appears, the full stack works:
  wgpu-native → WGPULib (FFI) → Device → RenderPipeline → window.

Run:
    pixi run hello
"""

from wgpu.gpu import request_adapter
from wgpu._ffi.lib import WGPULib
from wgpu._ffi.types import OpaquePtr
from wgpu._ffi.structs import (
    WGPURenderPipelineDescriptor,
    WGPUVertexState, WGPUFragmentState,
    WGPUPrimitiveState, WGPUMultisampleState,
    WGPUColorTargetState,
    WGPUBlendState,
    WGPURenderPassDescriptor, WGPURenderPassColorAttachment,
    WGPURenderPassDepthStencilAttachment,
    WGPUDepthStencilState, WGPUPassTimestampWrites,
    WGPUTextureViewDescriptor,
    WGPUConstantEntry, WGPUVertexBufferLayout,
    WGPUStringView, WGPUColor,
    str_to_sv,
)
from wgpu.texture import TextureView
from rendercanvas import RenderCanvas


# ---------------------------------------------------------------------------
# WGSL shader — one vertex + one fragment entry point
# ---------------------------------------------------------------------------
comptime WGSL = """
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
"""


def main() raises:
    # 1. Boot the GPU stack
    var inst   = request_adapter()
    var device = inst.request_device()

    # 2. Open a window (800 × 600, GLFW-backed)
    var canvas = RenderCanvas(inst, device, 800, 600, "wgpu-mojo: hello triangle")

    # 3. Compile the WGSL shader
    var shader = device.create_shader_module_wgsl(WGSL, "hello")

    # 4. Describe the vertex + fragment stages
    var vs_entry = str_to_sv(String("vs_main"))
    var fs_entry = str_to_sv(String("fs_main"))

    var vertex_state = WGPUVertexState(
        OpaquePtr(), shader.handle(), vs_entry,
        UInt(0), UnsafePointer[WGPUConstantEntry, MutExternalOrigin](),
        UInt(0), UnsafePointer[WGPUVertexBufferLayout, MutExternalOrigin](),
    )

    # Colour target must match the swapchain format
    var target_p = alloc[WGPUColorTargetState](1)
    target_p[0] = WGPUColorTargetState(
        OpaquePtr(),
        canvas.surface_format(),
        UnsafePointer[WGPUBlendState, MutExternalOrigin](),
        UInt64(0xF),   # ColorWriteMask.All
    )
    var fragment_p = alloc[WGPUFragmentState](1)
    fragment_p[0] = WGPUFragmentState(
        OpaquePtr(), shader.handle(), fs_entry,
        UInt(0), UnsafePointer[WGPUConstantEntry, MutExternalOrigin](),
        UInt(1), target_p,
    )

    # 5. Assemble the render pipeline
    var primitive   = WGPUPrimitiveState(OpaquePtr(), UInt32(4), UInt32(0), UInt32(1), UInt32(0), UInt32(0))
    var multisample = WGPUMultisampleState(OpaquePtr(), UInt32(1), UInt32(0xFFFFFFFF), UInt32(0))
    var layout      = device.create_pipeline_layout(List[OpaquePtr](), "hello_layout")

    var desc = WGPURenderPipelineDescriptor(
        OpaquePtr(), WGPUStringView.null_view(), layout.handle(),
        vertex_state, primitive,
        UnsafePointer[WGPUDepthStencilState, MutExternalOrigin](),
        multisample, fragment_p,
    )
    var pipeline = device.create_render_pipeline(desc)

    # Free temporaries; pin layout + shader until pipeline is created
    _ = layout^
    _ = shader^
    target_p.free()
    fragment_p.free()

    print("Window open — close it to exit.")

    # 6. Render loop
    while canvas.is_open():
        canvas.poll()

        var frame = canvas.next_frame()
        if frame.status != 1 and frame.status != 2:
            continue

        # Create a view into the current swapchain texture
        var view_h = device._lib.texture_create_view(
            frame.texture,
            UnsafePointer[WGPUTextureViewDescriptor, MutExternalOrigin](),
        )
        var lib_for_view = WGPULib()
        var view = TextureView(lib_for_view^, view_h)

        # Build the render pass (clear to black, then draw)
        var color_att_p = alloc[WGPURenderPassColorAttachment](1)
        color_att_p[0] = WGPURenderPassColorAttachment(
            OpaquePtr(),
            view.handle(),
            UInt32(0xFFFFFFFF),
            OpaquePtr(),
            UInt32(2),   # LoadOp.Clear
            UInt32(1),   # StoreOp.Store
            WGPUColor(Float64(0), Float64(0), Float64(0), Float64(1)),
        )
        var rp_desc_p = alloc[WGPURenderPassDescriptor](1)
        rp_desc_p[0] = WGPURenderPassDescriptor(
            OpaquePtr(), WGPUStringView.null_view(),
            UInt(1), color_att_p,
            UnsafePointer[WGPURenderPassDepthStencilAttachment, MutExternalOrigin](),
            OpaquePtr(),
            UnsafePointer[WGPUPassTimestampWrites, MutExternalOrigin](),
        )

        var enc   = device.create_command_encoder("frame")
        var rpass = enc.begin_render_pass(rp_desc_p)
        _ = view^                              # keep view alive until pass begins
        rpass.set_pipeline(pipeline.handle())
        rpass.draw(UInt32(3), UInt32(1), UInt32(0), UInt32(0))  # 3 vertices
        rpass.end()
        color_att_p.free()
        rp_desc_p.free()

        # Submit and present
        var cmd  = enc.finish()
        var cmds: List[OpaquePtr] = [cmd]
        device.queue_submit(cmds)
        device._lib.command_buffer_release(cmd)
        canvas.present()

    print("Done.")
    _ = pipeline^
    _ = canvas^
    _ = device^
    _ = inst^
