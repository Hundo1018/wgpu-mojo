"""
Tests/test_texture_sample.mojo — validate sampled texture bind group and render pipeline creation.
Requires GPU hardware.
"""

from wgpu._ffi.nulls import null_opaque, null_ptr, null_any_ptr
from std.testing import assert_true
from std.memory import alloc
from wgpu.device import Device
from wgpu.instance import Instance
from wgpu._ffi.types import (
    WGPUTextureUsage, WGPUTextureFormat, WGPUBufferUsage,
    WGPUShaderStage, WGPUSamplerBindingType, WGPUTextureSampleType,
    WGPUTextureViewDimension, WGPUTextureAspect, WGPUBufferBindingType,
    WGPU_WHOLE_SIZE,
)
from wgpu._ffi.structs import (
    WGPUBindGroupLayoutEntry, WGPUBindGroupLayoutDescriptor,
    WGPUBindGroupEntry, WGPUBindGroupDescriptor,
    WGPUBufferBindingLayout, WGPUSamplerBindingLayout,
    WGPUTextureBindingLayout, WGPUStorageTextureBindingLayout,
    WGPURenderPassColorAttachment, WGPURenderPassDescriptor,
    WGPURenderPassDepthStencilAttachment,
    WGPUColor, WGPUPassTimestampWrites,
    WGPUStringView,
    WGPUExtent3D, WGPUTexelCopyBufferInfo,
    WGPUTexelCopyBufferLayout, WGPUTexelCopyTextureInfo,
    WGPUOrigin3D,
)


def create_test_device() raises -> Device:
    var instance = Instance()
    var adapter = instance.request_adapter()
    return adapter.request_device()

comptime TEXTURE_SAMPLE_WGSL = """
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

comptime TEXTURE_READBACK_WGSL = """
@group(0) @binding(0) var tex: texture_2d<f32>;

@group(0) @binding(1) var<storage, read_write> out_buf: array<vec4<u32>, 4>;

@compute @workgroup_size(1)
fn cs_main(@builtin(global_invocation_id) gid: vec3<u32>) {
    if (gid.x >= 2u || gid.y >= 2u) {
        return;
    }
    let color = textureLoad(tex, vec2<i32>(gid.xy), 0);
    let idx = gid.y * 2u + gid.x;
    out_buf[idx] = vec4<u32>(
        u32(color.x * 255.0),
        u32(color.y * 255.0),
        u32(color.z * 255.0),
        u32(color.w * 255.0),
    );
}
"""


def test_sampled_texture_pipeline_creation() raises:
    var device = create_test_device()

    var tex = device.create_texture(
        UInt32(2), UInt32(2), UInt32(1),
        WGPUTextureFormat.RGBA8Unorm,
        WGPUTextureUsage.TEXTURE_BINDING.value | WGPUTextureUsage.COPY_DST.value,
        UInt32(2), UInt32(1), UInt32(1),
        "test_sample_texture",
    )
    var view = tex.create_view_default()
    var sampler = device.create_sampler()

    var bgl_entries: List[WGPUBindGroupLayoutEntry] = [
        WGPUBindGroupLayoutEntry(
            null_opaque(), UInt32(0), WGPUShaderStage.FRAGMENT.value, UInt32(0),
            WGPUBufferBindingLayout(null_opaque(), UInt32(0), UInt32(0), UInt64(0)),
            WGPUSamplerBindingLayout(null_opaque(), UInt32(0)),
            WGPUTextureBindingLayout(null_opaque(), WGPUTextureSampleType.Float, WGPUTextureViewDimension.D2, UInt32(0)),
            WGPUStorageTextureBindingLayout(null_opaque(), UInt32(0), UInt32(0), UInt32(0)),
        ),
        WGPUBindGroupLayoutEntry(
            null_opaque(), UInt32(1), WGPUShaderStage.FRAGMENT.value, UInt32(0),
            WGPUBufferBindingLayout(null_opaque(), UInt32(0), UInt32(0), UInt64(0)),
            WGPUSamplerBindingLayout(null_opaque(), WGPUSamplerBindingType.Filtering),
            WGPUTextureBindingLayout(null_opaque(), UInt32(0), UInt32(0), UInt32(0)),
            WGPUStorageTextureBindingLayout(null_opaque(), UInt32(0), UInt32(0), UInt32(0)),
        ),
    ]
    var bgl = device.create_bind_group_layout(bgl_entries)

    var bg_entries: List[WGPUBindGroupEntry] = [
        WGPUBindGroupEntry(
            null_opaque(), UInt32(0), null_opaque(), UInt64(0), UInt64(0), null_opaque(), view.handle().raw
        ),
        WGPUBindGroupEntry(
            null_opaque(), UInt32(1), null_opaque(), UInt64(0), UInt64(0), sampler.handle().raw, null_opaque()
        ),
    ]
    var bg = device.create_bind_group(bgl, bg_entries)

    var pl = device.create_pipeline_layout(bgl, "test_sample_pipeline_layout")
    var shader = device.create_shader_module_wgsl(TEXTURE_SAMPLE_WGSL, "test_sample_shader")
    var pipeline = device.create_render_pipeline(shader, "vs_main", "fs_main", WGPUTextureFormat.RGBA8Unorm, pl)

    assert_true(view)
    assert_true(sampler)
    assert_true(bgl)
    assert_true(bg)
    assert_true(pipeline)


def test_offscreen_render_texture_readback() raises:
    var device = create_test_device()

    var target_texture = device.create_texture(
        UInt32(2), UInt32(2), UInt32(1),
        WGPUTextureFormat.RGBA8Unorm,
        WGPUTextureUsage.RENDER_ATTACHMENT.value | WGPUTextureUsage.COPY_SRC.value,
        UInt32(2), UInt32(1), UInt32(1),
        "test_offscreen_readback_target",
    )
    var target_view = target_texture.create_view_default()

    var readback = device.create_buffer(
        UInt64(512),
        WGPUBufferUsage.COPY_DST.value | WGPUBufferUsage.MAP_READ.value,
        False,
        "test_offscreen_readback_buffer",
    )

    var enc = device.create_command_encoder("offscreen_render")
    var rpass = enc.begin_render_pass_clear(
        target_view^,
        WGPUColor(Float64(0.0), Float64(1.0), Float64(0.0), Float64(1.0)),
        "offscreen_clear",
    )
    rpass^.end()

    device.queue_submit(enc^.finish())
    _ = device.poll(True)

    var copy_enc = device.create_command_encoder("texture_readback")
    copy_enc.copy_texture_to_buffer(
        target_texture,
        readback,
        UInt64(0),
        UInt32(256),
        UInt32(2),
        UInt32(2),
        UInt32(2),
        aspect=WGPUTextureAspect.All,
    )
    device.queue_submit(copy_enc^.finish())

    var device_pin = device^
    var raw = readback.map_read()
    var pixels = raw.bitcast[UInt8]()

    assert_true(pixels[0] == UInt8(0))
    assert_true(pixels[1] == UInt8(255))
    assert_true(pixels[2] == UInt8(0))
    assert_true(pixels[3] == UInt8(255))

    assert_true(pixels[4] == UInt8(0))
    assert_true(pixels[5] == UInt8(255))
    assert_true(pixels[6] == UInt8(0))
    assert_true(pixels[7] == UInt8(255))

    assert_true(pixels[256] == UInt8(0))
    assert_true(pixels[257] == UInt8(255))
    assert_true(pixels[258] == UInt8(0))
    assert_true(pixels[259] == UInt8(255))

    assert_true(pixels[260] == UInt8(0))
    assert_true(pixels[261] == UInt8(255))
    assert_true(pixels[262] == UInt8(0))
    assert_true(pixels[263] == UInt8(255))

    readback.unmap()
    _ = device_pin^
    _ = target_texture^
    _ = readback^


def test_example_texture_sample_upload_readback() raises:
    var device = create_test_device()

    var texture = device.create_texture(
        UInt32(2), UInt32(2), UInt32(1),
        WGPUTextureFormat.RGBA8Unorm,
        WGPUTextureUsage.TEXTURE_BINDING.value | WGPUTextureUsage.COPY_DST.value,
        UInt32(2), UInt32(1), UInt32(1),
        "example_texture_sample_tex",
    )

    var tex_data: List[UInt8] = [
        UInt8(255), UInt8(0), UInt8(0), UInt8(255),
        UInt8(0), UInt8(255), UInt8(0), UInt8(255),
        UInt8(0), UInt8(0), UInt8(255), UInt8(255),
        UInt8(255), UInt8(255), UInt8(255), UInt8(255),
    ]

    var staging = device.create_buffer(
        UInt64(512),
        WGPUBufferUsage.COPY_SRC.value | WGPUBufferUsage.COPY_DST.value,
        False,
        "example_texture_sample_staging",
    )
    device.queue_write_data(staging, UInt64(0), tex_data)

    var upload_enc = device.create_command_encoder("example_upload")
    upload_enc.copy_buffer_to_texture(
        staging,
        UInt64(0),
        UInt32(256),
        UInt32(2),
        texture,
        UInt32(2),
        UInt32(2),
        aspect=WGPUTextureAspect.All,
    )
    device.queue_submit(upload_enc^.finish())
    _ = device.poll(True)
    _ = staging^

    var readback = device.create_buffer(
        UInt64(512),
        WGPUBufferUsage.COPY_DST.value | WGPUBufferUsage.MAP_READ.value,
        False,
        "example_texture_sample_readback",
    )

    var copy_back_enc = device.create_command_encoder("example_readback")
    copy_back_enc.copy_texture_to_buffer(
        texture,
        readback,
        UInt64(0),
        UInt32(256),
        UInt32(2),
        UInt32(2),
        UInt32(2),
        aspect=WGPUTextureAspect.All,
    )
    device.queue_submit(copy_back_enc^.finish())
    _ = device.poll(True)

    var device_pin = device^
    var raw = readback.map_read()
    var pixels = raw.bitcast[UInt8]()

    assert_true(pixels[0] == UInt8(255))
    assert_true(pixels[1] == UInt8(0))
    assert_true(pixels[2] == UInt8(0))
    assert_true(pixels[3] == UInt8(255))

    assert_true(pixels[4] == UInt8(0))
    assert_true(pixels[5] == UInt8(255))
    assert_true(pixels[6] == UInt8(0))
    assert_true(pixels[7] == UInt8(255))

    assert_true(pixels[256] == UInt8(0))
    assert_true(pixels[257] == UInt8(0))
    assert_true(pixels[258] == UInt8(255))
    assert_true(pixels[259] == UInt8(255))

    assert_true(pixels[260] == UInt8(255))
    assert_true(pixels[261] == UInt8(255))
    assert_true(pixels[262] == UInt8(255))
    assert_true(pixels[263] == UInt8(255))

    readback.unmap()
    _ = device_pin^
    _ = texture^
    _ = readback^

def test_texture_upload_copy_buffer_to_texture() raises:
    var device = create_test_device()

    var texture = device.create_texture(
        UInt32(2), UInt32(2), UInt32(1),
        WGPUTextureFormat.RGBA8Unorm,
        WGPUTextureUsage.TEXTURE_BINDING.value | WGPUTextureUsage.COPY_DST.value,
        UInt32(2), UInt32(1), UInt32(1),
        "test_texture_upload",
    )

    var tex_data: List[UInt8] = [
        UInt8(255), UInt8(0), UInt8(0), UInt8(255),
        UInt8(0), UInt8(255), UInt8(0), UInt8(255),
        UInt8(0), UInt8(0), UInt8(255), UInt8(255),
        UInt8(255), UInt8(255), UInt8(255), UInt8(255),
    ]

    var staging = device.create_buffer(
        UInt64(512),
        WGPUBufferUsage.COPY_SRC.value | WGPUBufferUsage.COPY_DST.value,
        False,
        "test_texture_upload_staging",
    )
    device.queue_write_data(staging, UInt64(0), tex_data)

    var enc = device.create_command_encoder("test_upload")
    enc.copy_buffer_to_texture(
        staging,
        UInt64(0),
        UInt32(256),
        UInt32(2),
        texture,
        UInt32(2),
        UInt32(2),
        aspect=WGPUTextureAspect.All,
    )
    device.queue_submit(enc^.finish())
    _ = device.poll(True)

    _ = staging^  # keep staging alive through submit

    assert_true(texture)


def test_texture_upload_readback() raises:
    var device = create_test_device()

    var texture = device.create_texture(
        UInt32(2), UInt32(2), UInt32(1),
        WGPUTextureFormat.RGBA8Unorm,
        WGPUTextureUsage.TEXTURE_BINDING.value | WGPUTextureUsage.COPY_DST.value | WGPUTextureUsage.COPY_SRC.value,
        UInt32(2), UInt32(1), UInt32(1),
        "test_texture_readback",
    )

    var tex_data: List[UInt8] = [
        UInt8(255), UInt8(0), UInt8(0), UInt8(255),
        UInt8(0), UInt8(255), UInt8(0), UInt8(255),
        UInt8(0), UInt8(0), UInt8(255), UInt8(255),
        UInt8(255), UInt8(255), UInt8(255), UInt8(255),
    ]

    var staging = device.create_buffer(
        UInt64(512),
        WGPUBufferUsage.COPY_SRC.value | WGPUBufferUsage.COPY_DST.value,
        False,
        "test_texture_readback_staging",
    )
    device.queue_write_data(staging, UInt64(0), tex_data)

    var upload_enc = device.create_command_encoder("upload_tex")
    upload_enc.copy_buffer_to_texture(
        staging,
        UInt64(0),
        UInt32(256),
        UInt32(2),
        texture,
        UInt32(2),
        UInt32(2),
        aspect=WGPUTextureAspect.All,
    )
    device.queue_submit(upload_enc^.finish())
    _ = device.poll(True)

    var storage_buffer = device.create_buffer(
        UInt64(64),
        WGPUBufferUsage.STORAGE.value | WGPUBufferUsage.COPY_SRC.value,
        False,
        "test_texture_readback_storage",
    )

    var readback = device.create_buffer(
        UInt64(64),
        WGPUBufferUsage.COPY_DST.value | WGPUBufferUsage.MAP_READ.value,
        False,
        "test_texture_readback_buffer",
    )

    var shader = device.create_shader_module_wgsl(TEXTURE_READBACK_WGSL, "test_texture_readback_shader")

    var bgl_entries: List[WGPUBindGroupLayoutEntry] = [
        WGPUBindGroupLayoutEntry(
            null_opaque(), UInt32(0), WGPUShaderStage.COMPUTE.value, UInt32(0),
            WGPUBufferBindingLayout(null_opaque(), UInt32(0), UInt32(0), UInt64(0)),
            WGPUSamplerBindingLayout(null_opaque(), UInt32(0)),
            WGPUTextureBindingLayout(null_opaque(), WGPUTextureSampleType.UnfilterableFloat, WGPUTextureViewDimension.D2, UInt32(0)),
            WGPUStorageTextureBindingLayout(null_opaque(), UInt32(0), UInt32(0), UInt32(0)),
        ),
        WGPUBindGroupLayoutEntry(
            null_opaque(), UInt32(1), WGPUShaderStage.COMPUTE.value, UInt32(0),
            WGPUBufferBindingLayout(null_opaque(), WGPUBufferBindingType.Storage, UInt32(0), UInt64(0)),
            WGPUSamplerBindingLayout(null_opaque(), UInt32(0)),
            WGPUTextureBindingLayout(null_opaque(), UInt32(0), UInt32(0), UInt32(0)),
            WGPUStorageTextureBindingLayout(null_opaque(), UInt32(0), UInt32(0), UInt32(0)),
        ),
    ]
    var bgl = device.create_bind_group_layout(bgl_entries)

    var pl = device.create_pipeline_layout(bgl, "test_texture_readback_layout")
    var pipeline = device.create_compute_pipeline(shader, "cs_main", pl, "test_texture_readback_pipeline")

    var tex_view = texture.create_view_default()
    var bg_entries: List[WGPUBindGroupEntry] = [
        WGPUBindGroupEntry(
            null_opaque(), UInt32(0), null_opaque(), UInt64(0), UInt64(0), null_opaque(), tex_view.handle().raw
        ),
        WGPUBindGroupEntry(
            null_opaque(), UInt32(1), storage_buffer.handle().raw, UInt64(0), WGPU_WHOLE_SIZE, null_opaque(), null_opaque()
        ),
    ]
    var bg = device.create_bind_group(bgl, bg_entries)

    var enc = device.create_command_encoder("compute_readback")
    var cpass = enc.begin_compute_pass("readback_pass")
    cpass.set_pipeline(pipeline)
    cpass.set_bind_group(UInt32(0), bg)
    cpass.dispatch_workgroups(UInt32(2), UInt32(2), UInt32(1))
    cpass^.end()

    device.queue_submit(enc^.finish())
    _ = device.poll(True)

    var copy_enc = device.create_command_encoder("storage_readback")
    copy_enc.copy_buffer_to_buffer(
        storage_buffer, UInt64(0),
        readback, UInt64(0),
        UInt64(64),
    )
    device.queue_submit(copy_enc^.finish())
    _ = device.poll(True)

    assert_true(storage_buffer)
    assert_true(readback)

    _ = staging^
    _ = storage_buffer^
    _ = readback^
    _ = texture^


def main() raises:
    test_offscreen_render_texture_readback()
    print("test_texture_sample: OFFSCREEN READBACK PASSED")
