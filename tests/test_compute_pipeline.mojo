"""
tests/test_compute_pipeline.mojo — Tests for compute pipeline creation and dispatch.
Requires GPU hardware.
"""

from std.testing import assert_true, assert_equal
from wgpu.gpu import request_adapter
from wgpu._ffi.types import (
    OpaquePtr, WGPUBufferUsage, WGPUShaderStage,
)
from wgpu._ffi.structs import (
    WGPUBindGroupLayoutEntry, WGPUBindGroupLayoutDescriptor,
    WGPUBufferBindingLayout, WGPUSamplerBindingLayout,
    WGPUTextureBindingLayout, WGPUStorageTextureBindingLayout,
    WGPUBindGroupEntry, WGPUBindGroupDescriptor,
    WGPUComputeState, WGPUComputePipelineDescriptor,
    WGPUConstantEntry,
    WGPUPipelineLayoutDescriptor,
    WGPUStringView, str_to_sv,
    WGPUCommandBufferDescriptor,
    WGPUComputePassDescriptor,
)
from wgpu._ffi.types import WGPU_WHOLE_SIZE


comptime ADD_WGSL = """
@group(0) @binding(0) var<storage, read>       a : array<f32>;
@group(0) @binding(1) var<storage, read>       b : array<f32>;
@group(0) @binding(2) var<storage, read_write> c : array<f32>;

@compute @workgroup_size(1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let i = gid.x;
    c[i] = a[i] + b[i];
}
"""

comptime N_ELEMENTS: UInt32 = 4
comptime BUF_SIZE: UInt64 = UInt64(4) * UInt64(4)


def _make_bgl_entry(binding: UInt32, read_only: Bool) -> WGPUBindGroupLayoutEntry:
    var buf_type: UInt32 = 3 if read_only else 2
    return WGPUBindGroupLayoutEntry(
        OpaquePtr(), binding,
        WGPUShaderStage.COMPUTE.value, UInt32(0),
        WGPUBufferBindingLayout(OpaquePtr(), buf_type, UInt32(0), UInt64(0)),
        WGPUSamplerBindingLayout(OpaquePtr(), UInt32(0)),
        WGPUTextureBindingLayout(OpaquePtr(), UInt32(0), UInt32(0), UInt32(0)),
        WGPUStorageTextureBindingLayout(OpaquePtr(), UInt32(0), UInt32(0), UInt32(0)),
    )


def test_create_compute_pipeline() raises:
    """Compute pipeline creation from WGSL shader should succeed."""
    var inst   = request_adapter()
    var device = inst.request_device()
    var shader = device.create_shader_module_wgsl(ADD_WGSL, "add")
    assert_true(Bool(shader))

    var entries = List[WGPUBindGroupLayoutEntry]()
    for i in range(3):
        entries.append(_make_bgl_entry(UInt32(i), i < 2))

    var bgl_desc = WGPUBindGroupLayoutDescriptor(
        OpaquePtr(), WGPUStringView.null_view(), UInt(3), entries.unsafe_ptr()
    )
    var bgl = device.create_bind_group_layout(bgl_desc)

    var bgls = List[OpaquePtr]()
    bgls.append(bgl)
    var layout_desc = WGPUPipelineLayoutDescriptor(
        OpaquePtr(), WGPUStringView.null_view(), UInt(1), bgls.unsafe_ptr(), UInt32(0)
    )
    var layout_desc_p = alloc[WGPUPipelineLayoutDescriptor](1)
    layout_desc_p[] = layout_desc
    var pl = device._lib.device_create_pipeline_layout(
        device.handle(), layout_desc_p
    )
    layout_desc_p.free()
    assert_true(Bool(pl))

    var entry_sv = str_to_sv(String("main"))
    var compute_state = WGPUComputeState(
        OpaquePtr(), shader, entry_sv, UInt(0),
        UnsafePointer[WGPUConstantEntry, MutExternalOrigin]()
    )
    var pipeline_desc = WGPUComputePipelineDescriptor(
        OpaquePtr(), WGPUStringView.null_view(), pl, compute_state
    )
    var pipeline = device.create_compute_pipeline(pipeline_desc)
    assert_true(Bool(pipeline))

    device._lib.compute_pipeline_release(pipeline)
    device._lib.pipeline_layout_release(pl)
    device._lib.bind_group_layout_release(bgl)
    device._lib.shader_module_release(shader)


def test_vec_add_compute() raises:
    """Full GPU vector addition: upload, dispatch, readback."""
    var inst   = request_adapter()
    var device = inst.request_device()
    var shader = device.create_shader_module_wgsl(ADD_WGSL, "vec_add")

    var entries = List[WGPUBindGroupLayoutEntry]()
    for i in range(3):
        entries.append(_make_bgl_entry(UInt32(i), i < 2))
    var bgl_desc = WGPUBindGroupLayoutDescriptor(
        OpaquePtr(), WGPUStringView.null_view(), UInt(3), entries.unsafe_ptr()
    )
    var bgl = device.create_bind_group_layout(bgl_desc)

    var bgls2 = List[OpaquePtr]()
    bgls2.append(bgl)
    var layout_desc = WGPUPipelineLayoutDescriptor(
        OpaquePtr(), WGPUStringView.null_view(), UInt(1), bgls.unsafe_ptr(), UInt32(0)
    )
    var layout_desc_p = alloc[WGPUPipelineLayoutDescriptor](1)
    layout_desc_p[] = layout_desc
    var layout_desc_p2 = alloc[WGPUPipelineLayoutDescriptor](1)
    layout_desc_p2[] = layout_desc2
    var pl = device._lib.device_create_pipeline_layout(device.handle(), layout_desc_p2)
    layout_desc_p2.free()

    var entry_sv = str_to_sv(String("main"))
    var cs = WGPUComputeState(OpaquePtr(), shader, entry_sv, UInt(0),
                              UnsafePointer[WGPUConstantEntry, MutExternalOrigin]())
    var pipeline_desc = WGPUComputePipelineDescriptor(OpaquePtr(), WGPUStringView.null_view(), pl, cs)
    var pipeline = device.create_compute_pipeline(pipeline_desc)

    var a_data = alloc[Float32](4)
    a_data[0] = Float32(1.0); a_data[1] = Float32(2.0)
    a_data[2] = Float32(3.0); a_data[3] = Float32(4.0)
    var b_data = alloc[Float32](4)
    b_data[0] = Float32(10.0); b_data[1] = Float32(20.0)
    b_data[2] = Float32(30.0); b_data[3] = Float32(40.0)

    var buf_a = device.create_buffer(BUF_SIZE, WGPUBufferUsage.STORAGE | WGPUBufferUsage.COPY_DST, False, "buf_a")
    var buf_b = device.create_buffer(BUF_SIZE, WGPUBufferUsage.STORAGE | WGPUBufferUsage.COPY_DST, False, "buf_b")
    var buf_c = device.create_buffer(BUF_SIZE, WGPUBufferUsage.STORAGE | WGPUBufferUsage.COPY_SRC, False, "buf_c")
    var buf_r = device.create_buffer(BUF_SIZE, WGPUBufferUsage.MAP_READ | WGPUBufferUsage.COPY_DST, False, "buf_r")

    device._lib.queue_write_buffer(
        device.queue(), buf_a, UInt64(0),
        a_data.bitcast[NoneType](), UInt(16)
    )
    device._lib.queue_write_buffer(
        device.queue(), buf_b, UInt64(0),
        b_data.bitcast[NoneType](), UInt(16)
    )

    var bg_entries = List[WGPUBindGroupEntry]()
    bg_entries.append(WGPUBindGroupEntry(OpaquePtr(), UInt32(0), buf_a, UInt64(0), WGPU_WHOLE_SIZE, OpaquePtr(), OpaquePtr()))
    bg_entries.append(WGPUBindGroupEntry(OpaquePtr(), UInt32(1), buf_b, UInt64(0), WGPU_WHOLE_SIZE, OpaquePtr(), OpaquePtr()))
    bg_entries.append(WGPUBindGroupEntry(OpaquePtr(), UInt32(2), buf_c, UInt64(0), WGPU_WHOLE_SIZE, OpaquePtr(), OpaquePtr()))
    var bg_desc = WGPUBindGroupDescriptor(
        OpaquePtr(), WGPUStringView.null_view(), bgl, UInt(3), bg_entries.unsafe_ptr()
    )
    var bg = device.create_bind_group(bg_desc)

    var enc = device.create_command_encoder("vec_add_enc")
    var pass_desc_p = alloc[WGPUComputePassDescriptor](1)
    pass_desc_p[] = WGPUComputePassDescriptor(OpaquePtr(), WGPUStringView.null_view(), OpaquePtr())
    var cpass = device._lib.command_encoder_begin_compute_pass(enc, pass_desc_p)
    pass_desc_p.free()
    device._lib.compute_pass_set_pipeline(cpass, pipeline)
    device._lib.compute_pass_set_bind_group(cpass, UInt32(0), bg, UInt(0), OpaquePtr())
    device._lib.compute_pass_dispatch_workgroups(cpass, N_ELEMENTS, UInt32(1), UInt32(1))
    device._lib.compute_pass_end(cpass)

    device._lib.command_encoder_copy_buffer_to_buffer(enc, buf_c, UInt64(0), buf_r, UInt64(0), BUF_SIZE)

    var cmd_buf_desc_p = alloc[WGPUCommandBufferDescriptor](1)
    cmd_buf_desc_p[] = WGPUCommandBufferDescriptor(OpaquePtr(), WGPUStringView.null_view())
    var cmd_buf = device._lib.command_encoder_finish(enc, cmd_buf_desc_p)
    cmd_buf_desc_p.free()
    var cmds_p = alloc[OpaquePtr](1)
    cmds_p[] = cmd_buf
    device._lib.queue_submit(device.queue(), UInt(1), cmds_p)

    var status = device._lib.buffer_map_async(
        device.instance(), device.handle(), buf_r,
        UInt64(1), UInt(0), UInt(16)
    )
    assert_equal(status, UInt32(1))

    var raw = device._lib.buffer_get_const_mapped_range(buf_r, UInt(0), UInt(16))
    var result = raw.bitcast[Float32]()
    assert_equal(result[0], Float32(11.0))
    assert_equal(result[1], Float32(22.0))
    assert_equal(result[2], Float32(33.0))
    assert_equal(result[3], Float32(44.0))
    print("GPU vector add result:", result[0], result[1], result[2], result[3])

    device._lib.buffer_unmap(buf_r)
    device._lib.bind_group_release(bg)
    device._lib.compute_pass_release(cpass)
    device._lib.command_buffer_release(cmd_buf)
    device._lib.compute_pipeline_release(pipeline)
    device._lib.pipeline_layout_release(pl)
    device._lib.bind_group_layout_release(bgl)
    device._lib.shader_module_release(shader)
    device._lib.buffer_release(buf_a)
    device._lib.buffer_release(buf_b)
    device._lib.buffer_release(buf_c)
    device._lib.buffer_release(buf_r)


def main() raises:
    test_create_compute_pipeline()
    test_vec_add_compute()
    print("test_compute_pipeline: ALL PASSED")
