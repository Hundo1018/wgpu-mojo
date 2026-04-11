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
    WGPUStringView, str_to_sv,
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
    # Type 3 = Storage (read_write), Type 4 = ReadOnlyStorage
    var buf_type: UInt32 = UInt32(4) if read_only else UInt32(3)
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

    var entries_p = alloc[WGPUBindGroupLayoutEntry](3)
    for i in range(3):
        entries_p[i] = _make_bgl_entry(UInt32(i), i < 2)

    var bgl_desc = WGPUBindGroupLayoutDescriptor(
        OpaquePtr(), WGPUStringView.null_view(), UInt(3), entries_p
    )
    var bgl = device.create_bind_group_layout(bgl_desc)
    entries_p.free()

    var bgls = List[OpaquePtr]()
    bgls.append(bgl.handle())
    var pl = device.create_pipeline_layout(bgls)
    _ = bgl^  # bgl no longer needed once pipeline layout is created

    var entry_str = String("main")
    var entry_sv = str_to_sv(entry_str)
    var compute_state = WGPUComputeState(
        OpaquePtr(), shader.handle(), entry_sv, UInt(0),
        UnsafePointer[WGPUConstantEntry, MutExternalOrigin]()
    )
    var pipeline_desc = WGPUComputePipelineDescriptor(
        OpaquePtr(), WGPUStringView.null_view(), pl.handle(), compute_state
    )
    var pipeline = device.create_compute_pipeline(pipeline_desc)
    _ = pl^      # pl must outlive create_compute_pipeline
    _ = shader^  # shader must outlive create_compute_pipeline
    _ = entry_str
    _ = pipeline^
    _ = device^
    _ = inst^


def test_vec_add_compute() raises:
    """Full GPU vector addition: upload, dispatch, readback."""
    var inst   = request_adapter()
    var device = inst.request_device()
    var shader = device.create_shader_module_wgsl(ADD_WGSL, "vec_add")

    var entries_p = alloc[WGPUBindGroupLayoutEntry](3)
    for i in range(3):
        entries_p[i] = _make_bgl_entry(UInt32(i), i < 2)
    var bgl_desc = WGPUBindGroupLayoutDescriptor(
        OpaquePtr(), WGPUStringView.null_view(), UInt(3), entries_p
    )
    var bgl = device.create_bind_group_layout(bgl_desc)
    entries_p.free()

    var bgls = List[OpaquePtr]()
    bgls.append(bgl.handle())
    var pl = device.create_pipeline_layout(bgls)

    var entry_str2 = String("main")
    var entry_sv = str_to_sv(entry_str2)
    var cs = WGPUComputeState(OpaquePtr(), shader.handle(), entry_sv, UInt(0),
                              UnsafePointer[WGPUConstantEntry, MutExternalOrigin]())
    var pipeline_desc = WGPUComputePipelineDescriptor(
        OpaquePtr(), WGPUStringView.null_view(), pl.handle(), cs
    )
    var pipeline = device.create_compute_pipeline(pipeline_desc)
    _ = pl^      # pl must outlive create_compute_pipeline
    _ = shader^  # shader must outlive create_compute_pipeline
    _ = entry_str2

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

    device.queue_write_buffer(buf_a.handle(), UInt64(0), a_data, UInt(16))
    device.queue_write_buffer(buf_b.handle(), UInt64(0), b_data, UInt(16))

    var bg_entries_p = alloc[WGPUBindGroupEntry](3)
    bg_entries_p[0] = WGPUBindGroupEntry(OpaquePtr(), UInt32(0), buf_a.handle(), UInt64(0), WGPU_WHOLE_SIZE, OpaquePtr(), OpaquePtr())
    bg_entries_p[1] = WGPUBindGroupEntry(OpaquePtr(), UInt32(1), buf_b.handle(), UInt64(0), WGPU_WHOLE_SIZE, OpaquePtr(), OpaquePtr())
    bg_entries_p[2] = WGPUBindGroupEntry(OpaquePtr(), UInt32(2), buf_c.handle(), UInt64(0), WGPU_WHOLE_SIZE, OpaquePtr(), OpaquePtr())
    var bg_desc = WGPUBindGroupDescriptor(
        OpaquePtr(), WGPUStringView.null_view(), bgl.handle(), UInt(3), bg_entries_p
    )
    var bg = device.create_bind_group(bg_desc)
    _ = bgl^  # bgl must outlive create_bind_group
    bg_entries_p.free()

    var enc = device.create_command_encoder("vec_add_enc")
    var cpass = enc.begin_compute_pass()
    cpass.set_pipeline(pipeline.handle())
    cpass.set_bind_group(UInt32(0), bg.handle())
    cpass.dispatch_workgroups(N_ELEMENTS, UInt32(1), UInt32(1))
    cpass.end()

    enc.copy_buffer_to_buffer(buf_c.handle(), UInt64(0), buf_r.handle(), UInt64(0), BUF_SIZE)

    var cmd = enc.finish()
    var cmds = List[OpaquePtr]()
    cmds.append(cmd)
    device.queue_submit(cmds)

    # Pin GPU resources past queue_submit
    _ = pipeline^
    _ = bg^
    _ = enc^
    _ = buf_a^
    _ = buf_b^
    _ = buf_c^

    var raw = buf_r.map_read(UInt64(0), UInt64(16))
    var result = raw.bitcast[Float32]()
    assert_equal(result[0], Float32(11.0))
    assert_equal(result[1], Float32(22.0))
    assert_equal(result[2], Float32(33.0))
    assert_equal(result[3], Float32(44.0))
    print("GPU vector add result:", result[0], result[1], result[2], result[3])

    buf_r.unmap()
    
    # Pin remaining GPU object lifetimes past all usage
    _ = device^
    _ = inst^


def main() raises:
    test_create_compute_pipeline()
    test_vec_add_compute()
    print("test_compute_pipeline: ALL PASSED")
