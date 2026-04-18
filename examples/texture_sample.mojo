"""
Examples/texture_sample.mojo — Textured quad example with a sampled 2×2 texture.

Demonstrates:
  * creating an on-GPU texture and sampler
  * uploading texels through a staging buffer
  * binding a texture and sampler to a fragment shader
  * drawing a fullscreen quad with a texture lookup

Run:
    pixi run example-texture-sample
"""

from wgpu.gpu import GPU
from rendercanvas import RenderCanvas
from wgpu._ffi.types import (
    OpaquePtr,
    WGPUBufferUsage, WGPUTextureUsage, WGPUTextureFormat,
    WGPUShaderStage, WGPUSamplerBindingType, WGPUTextureSampleType,
    WGPUTextureViewDimension, WGPUTextureAspect,
    WGPU_COPY_STRIDE_UNDEFINED, WGPU_WHOLE_SIZE,
)
from wgpu._ffi.structs import (
    WGPUBindGroupLayoutEntry, WGPUBindGroupLayoutDescriptor,
    WGPUBindGroupEntry, WGPUBindGroupDescriptor,
    WGPUBufferBindingLayout, WGPUSamplerBindingLayout,
    WGPUTextureBindingLayout, WGPUStorageTextureBindingLayout,
    WGPUExtent3D, WGPUTexelCopyBufferInfo, WGPUTexelCopyBufferLayout,
    WGPUTexelCopyTextureInfo, WGPUOrigin3D, WGPUColor,
    WGPURenderPassColorAttachment, WGPURenderPassDescriptor,
    WGPURenderPassDepthStencilAttachment, WGPUPassTimestampWrites,
    WGPUStringView,
)

comptime TEXTURE_WGSL = """
struct VertexOutput {
    @builtin(position) pos: vec4<f32>,
    @location(0) uv: vec2<f32>,
}

@vertex
fn vs_main(@builtin(vertex_index) idx: u32) -> VertexOutput {
    var positions = array<vec2<f32>, 6>(
        vec2<f32>(-1.0, -1.0),
        vec2<f32>(1.0, -1.0),
        vec2<f32>(-1.0, 1.0),
        vec2<f32>(-1.0, 1.0),
        vec2<f32>(1.0, -1.0),
        vec2<f32>(1.0, 1.0),
    );
    var uvs = array<vec2<f32>, 6>(
        vec2<f32>(0.0, 1.0),
        vec2<f32>(1.0, 1.0),
        vec2<f32>(0.0, 0.0),
        vec2<f32>(0.0, 0.0),
        vec2<f32>(1.0, 1.0),
        vec2<f32>(1.0, 0.0),
    );
    var out: VertexOutput;
    out.pos = vec4<f32>(positions[idx], 0.0, 1.0);
    out.uv = uvs[idx];
    return out;
}

@group(0) @binding(0) var tex: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    return textureSample(tex, samp, in.uv);
}
"""


def main() raises:
    var gpu = GPU()
    var device = gpu.request_device()
    var canvas = RenderCanvas(gpu, device, 640, 480, "wgpu-mojo: texture sample")

    # Create a small 2×2 texture and upload texel data directly.
    var texture = device.create_texture(
        UInt32(2), UInt32(2), UInt32(1),
        WGPUTextureFormat.RGBA8Unorm,
        WGPUTextureUsage.TEXTURE_BINDING | WGPUTextureUsage.COPY_DST,
        UInt32(2), UInt32(1), UInt32(1),
        "texture_sample_tex"
    )

    var tex_data: List[UInt8] = [
        UInt8(255), UInt8(0), UInt8(0), UInt8(255),       # red
        UInt8(0), UInt8(255), UInt8(0), UInt8(255),       # green
        UInt8(0), UInt8(0), UInt8(255), UInt8(255),       # blue
        UInt8(255), UInt8(255), UInt8(255), UInt8(255),   # white
    ]

    var staging = device.create_buffer(
        UInt64(512),
        WGPUBufferUsage.COPY_SRC | WGPUBufferUsage.COPY_DST,
        False,
        "texture_sample_staging",
    )
    device.queue_write_data(staging, UInt64(0), tex_data)

    var copy_src = alloc[WGPUTexelCopyBufferInfo](1)
    copy_src[0] = WGPUTexelCopyBufferInfo(
        WGPUTexelCopyBufferLayout(UInt64(0), UInt32(256), UInt32(2)),  # rows_per_image must match texture height for a 2×2 copy
        staging.handle().raw,
    )

    var copy_dst = alloc[WGPUTexelCopyTextureInfo](1)
    copy_dst[0] = WGPUTexelCopyTextureInfo(
        texture.handle().raw,
        UInt32(0),
        WGPUOrigin3D(UInt32(0), UInt32(0), UInt32(0)),
        WGPUTextureAspect.All,
    )

    var copy_size = alloc[WGPUExtent3D](1)
    copy_size[0] = WGPUExtent3D(UInt32(2), UInt32(2), UInt32(1))

    var upload_enc = device.create_command_encoder("upload_tex")
    upload_enc.copy_buffer_to_texture(copy_src, copy_dst, copy_size)
    device.queue_submit(upload_enc^.finish())
    _ = device.poll(True)

    _ = staging^  # keep staging alive through submit
    copy_src.free()
    copy_dst.free()
    copy_size.free()

    var tex_view = texture.create_view_default()
    var sampler = device.create_sampler()

    var entries_p = alloc[WGPUBindGroupLayoutEntry](2)
    entries_p[0] = WGPUBindGroupLayoutEntry(
        OpaquePtr(), UInt32(0), WGPUShaderStage.FRAGMENT.value, UInt32(0),
        WGPUBufferBindingLayout(OpaquePtr(), UInt32(0), UInt32(0), UInt64(0)),
        WGPUSamplerBindingLayout(OpaquePtr(), UInt32(0)),
        WGPUTextureBindingLayout(OpaquePtr(), WGPUTextureSampleType.Float, WGPUTextureViewDimension.D2, UInt32(0)),
        WGPUStorageTextureBindingLayout(OpaquePtr(), UInt32(0), UInt32(0), UInt32(0)),
    )
    entries_p[1] = WGPUBindGroupLayoutEntry(
        OpaquePtr(), UInt32(1), WGPUShaderStage.FRAGMENT.value, UInt32(0),
        WGPUBufferBindingLayout(OpaquePtr(), UInt32(0), UInt32(0), UInt64(0)),
        WGPUSamplerBindingLayout(OpaquePtr(), WGPUSamplerBindingType.Filtering),
        WGPUTextureBindingLayout(OpaquePtr(), UInt32(0), UInt32(0), UInt32(0)),
        WGPUStorageTextureBindingLayout(OpaquePtr(), UInt32(0), UInt32(0), UInt32(0)),
    )

    var bgl_desc = WGPUBindGroupLayoutDescriptor(
        OpaquePtr(), WGPUStringView.null_view(), UInt(2), entries_p
    )
    var bind_group_layout = device.create_bind_group_layout(bgl_desc)
    entries_p.free()

    var pl = device.create_pipeline_layout([bind_group_layout.handle().raw], "texture_sample_layout")
    var shader = device.create_shader_module_wgsl(TEXTURE_WGSL, "texture_sample_shader")
    var pipeline = device.create_render_pipeline(
        shader, "vs_main", "fs_main",
        canvas.surface_format(), pl,
        primitive_topology=UInt32(3),
        label="texture_sample_pipeline",
    )

    var bg_entries_p = alloc[WGPUBindGroupEntry](2)
    bg_entries_p[0] = WGPUBindGroupEntry(
        OpaquePtr(), UInt32(0), OpaquePtr(), UInt64(0), UInt64(0), OpaquePtr(), tex_view.handle().raw
    )
    bg_entries_p[1] = WGPUBindGroupEntry(
        OpaquePtr(), UInt32(1), OpaquePtr(), UInt64(0), UInt64(0), sampler.handle().raw, OpaquePtr()
    )
    var bg_desc = WGPUBindGroupDescriptor(
        OpaquePtr(), WGPUStringView.null_view(), bind_group_layout.handle().raw, UInt(2), bg_entries_p
    )
    var bind_group = device.create_bind_group(bg_desc)
    bg_entries_p.free()
    _ = bind_group_layout^
    _ = tex_view^
    _ = sampler^

    print("Rendering textured quad — close the window to quit.")

    while canvas.is_open():
        canvas.poll()
        var frame = canvas.next_frame()
        if not frame.is_renderable():
            continue

        var enc = device.create_command_encoder("frame")
        var view = device.create_texture_view(frame.texture)

        var color_att_p = alloc[WGPURenderPassColorAttachment](1)
        color_att_p[0] = WGPURenderPassColorAttachment(
            OpaquePtr(),
            view.handle().raw,
            UInt32(0xFFFFFFFF),
            OpaquePtr(),
            UInt32(1),
            UInt32(1),
            WGPUColor(Float64(0.0), Float64(0.0), Float64(0.0), Float64(1.0)),
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

        var rpass = enc.begin_render_pass(rp_desc_p)
        _ = view^
        rpass.set_pipeline(pipeline)
        rpass.set_bind_group(UInt32(0), bind_group)
        rpass.draw(UInt32(6), UInt32(1), UInt32(0), UInt32(0))
        rpass^.end()

        color_att_p.free()
        rp_desc_p.free()

        device.queue_submit(enc^.finish())
        canvas.present()

    print("Window closed.")
