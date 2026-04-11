"""
examples/triangle_window.mojo — Hello Triangle in a real window.

Renders a coloured triangle (RGB vertices) on a black background.
This is the classical first rendering test: if the triangle appears,
the full pipeline (GLFW → Surface → RenderPipeline → draw → present) works.

Run:
    pixi run example-triangle
"""

from wgpu.gpu import request_adapter
from wgpu._ffi.lib import WGPULib
from wgpu._ffi.types import (
    OpaquePtr, WGPUTextureUsage,
)
from wgpu._ffi.structs import (
    WGPURenderPipelineDescriptor,
    WGPUVertexState, WGPUFragmentState,
    WGPUPrimitiveState, WGPUMultisampleState,
    WGPUColorTargetState,
    WGPUBlendState, WGPUBlendComponent,
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
    var inst   = request_adapter()
    var device = inst.request_device()
    var canvas = RenderCanvas(inst, device, 800, 600, "wgpu-mojo: hello triangle")

    # --- Compile shader ---------------------------------------------------
    var shader = device.create_shader_module_wgsl(TRIANGLE_WGSL, "triangle")

    # --- Build render pipeline --------------------------------------------
    var vs_entry = str_to_sv(String("vs_main"))
    var fs_entry = str_to_sv(String("fs_main"))

    var vertex_state = WGPUVertexState(
        OpaquePtr(), shader.handle(), vs_entry,
        UInt(0), UnsafePointer[WGPUConstantEntry, MutExternalOrigin](),
        UInt(0), UnsafePointer[WGPUVertexBufferLayout, MutExternalOrigin](),
    )

    var target_p = alloc[WGPUColorTargetState](1)
    target_p[0] = WGPUColorTargetState(
        OpaquePtr(),
        canvas.surface_format(),                          # match the swapchain format
        UnsafePointer[WGPUBlendState, MutExternalOrigin](),
        UInt64(0xF),                                      # ColorWriteMask.All
    )
    var fragment_p = alloc[WGPUFragmentState](1)
    fragment_p[0] = WGPUFragmentState(
        OpaquePtr(), shader.handle(), fs_entry,
        UInt(0), UnsafePointer[WGPUConstantEntry, MutExternalOrigin](),
        UInt(1), target_p,
    )

    var primitive   = WGPUPrimitiveState(OpaquePtr(), UInt32(4), UInt32(0), UInt32(1), UInt32(0), UInt32(0))
    var multisample = WGPUMultisampleState(OpaquePtr(), UInt32(1), UInt32(0xFFFFFFFF), UInt32(0))
    var pl = device.create_pipeline_layout(List[OpaquePtr](), "tri_layout")

    var desc = WGPURenderPipelineDescriptor(
        OpaquePtr(), WGPUStringView.null_view(), pl.handle(),
        vertex_state, primitive,
        UnsafePointer[WGPUDepthStencilState, MutExternalOrigin](),
        multisample, fragment_p,
    )
    var pipeline = device.create_render_pipeline(desc)
    _ = pl^
    _ = shader^
    target_p.free()
    fragment_p.free()

    print("Rendering triangle — close the window to quit.")

    # --- Render loop -------------------------------------------------------
    while canvas.is_open():
        canvas.poll()

        var frame = canvas.next_frame()
        if frame.status != 1 and frame.status != 2:
            continue

        var view_h = device._lib.texture_create_view(
            frame.texture,
            UnsafePointer[WGPUTextureViewDescriptor, MutExternalOrigin](),
        )
        var lib_for_view = WGPULib()
        var view = TextureView(lib_for_view^, view_h)

        var color_att_p = alloc[WGPURenderPassColorAttachment](1)
        color_att_p[0] = WGPURenderPassColorAttachment(
            OpaquePtr(),
            view.handle(),
            UInt32(0xFFFFFFFF),
            OpaquePtr(),
            UInt32(2),   # LoadOp.Clear
            UInt32(1),   # StoreOp.Store
            WGPUColor(Float64(0.0), Float64(0.0), Float64(0.0), Float64(1.0)),
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
        _ = view^
        rpass.set_pipeline(pipeline.handle())
        rpass.draw(UInt32(3), UInt32(1), UInt32(0), UInt32(0))
        rpass.end()
        color_att_p.free()
        rp_desc_p.free()

        var cmd = enc.finish()
        var cmds: List[OpaquePtr] = [cmd]
        device.queue_submit(cmds)
        device._lib.command_buffer_release(cmd)

        canvas.present()

    print("Window closed.")
    _ = pipeline^
    _ = canvas^
    _ = device^
    _ = inst^
