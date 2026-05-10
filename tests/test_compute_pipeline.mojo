"""
Tests/test_compute_pipeline.mojo — Tests for compute pipeline creation and dispatch.
Requires GPU hardware.
"""

from std.testing import assert_true, assert_equal
from wgpu.device import Device
from wgpu.instance import Instance
from wgpu._ffi.alloc_guard import AllocGuard
from wgpu._ffi.types import (
    WGPUBufferUsage, WGPUShaderStage,
)
from wgpu._ffi.structs import (
    WGPUBindGroupLayoutEntry,
    WGPUBindGroupLayoutDescriptor,
    WGPUBufferBindingLayout, WGPUSamplerBindingLayout,
    WGPUTextureBindingLayout, WGPUStorageTextureBindingLayout,
    WGPUBindGroupEntry, WGPUBindGroupDescriptor,
    WGPUStringView,
)
from wgpu._ffi.types import WGPU_WHOLE_SIZE


def create_test_device() raises -> Device:
    var instance = Instance()
    var adapter = instance.request_adapter()
    return adapter.request_device()


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
        OpaquePointer[MutExternalOrigin](unsafe_from_address=0), binding,
        WGPUShaderStage.COMPUTE.value, UInt32(0),
        WGPUBufferBindingLayout(OpaquePointer[MutExternalOrigin](unsafe_from_address=0), buf_type, UInt32(0), UInt64(0)),
        WGPUSamplerBindingLayout(OpaquePointer[MutExternalOrigin](unsafe_from_address=0), UInt32(0)),
        WGPUTextureBindingLayout(OpaquePointer[MutExternalOrigin](unsafe_from_address=0), UInt32(0), UInt32(0), UInt32(0)),
        WGPUStorageTextureBindingLayout(OpaquePointer[MutExternalOrigin](unsafe_from_address=0), UInt32(0), UInt32(0), UInt32(0)),
    )


def test_create_compute_pipeline() raises:
    """Compute pipeline creation from WGSL shader should succeed."""
    var device = create_test_device()
    var shader = device.create_shader_module_wgsl(ADD_WGSL, "add")

    var bgl_entries: List[WGPUBindGroupLayoutEntry] = [
        _make_bgl_entry(UInt32(0), True),
        _make_bgl_entry(UInt32(1), True),
        _make_bgl_entry(UInt32(2), False),
    ]
    var bgl = device.create_bind_group_layout(bgl_entries)

    var pl = device.create_pipeline_layout(bgl)
    var pipeline = device.create_compute_pipeline(shader, "main", pl)


def test_vec_add_compute() raises:
    """Full GPU vector addition: upload, dispatch, readback."""
    var device = create_test_device()
    var shader = device.create_shader_module_wgsl(ADD_WGSL, "vec_add")

    var bgl_entries: List[WGPUBindGroupLayoutEntry] = [
        _make_bgl_entry(UInt32(0), True),
        _make_bgl_entry(UInt32(1), True),
        _make_bgl_entry(UInt32(2), False),
    ]
    var bgl = device.create_bind_group_layout(bgl_entries)

    var pl = device.create_pipeline_layout(bgl)

    var pipeline = device.create_compute_pipeline(shader, "main", pl)

    var buf_a = device.create_buffer(BUF_SIZE, WGPUBufferUsage.STORAGE | WGPUBufferUsage.COPY_DST, False, "buf_a")
    var buf_b = device.create_buffer(BUF_SIZE, WGPUBufferUsage.STORAGE | WGPUBufferUsage.COPY_DST, False, "buf_b")
    var buf_c = device.create_buffer(BUF_SIZE, WGPUBufferUsage.STORAGE | WGPUBufferUsage.COPY_SRC, False, "buf_c")
    var buf_r = device.create_buffer(BUF_SIZE, WGPUBufferUsage.MAP_READ | WGPUBufferUsage.COPY_DST, False, "buf_r")

    with AllocGuard[Float32](4) as a_data:
        a_data[0] = Float32(1.0); a_data[1] = Float32(2.0)
        a_data[2] = Float32(3.0); a_data[3] = Float32(4.0)
        device.queue_write_buffer(buf_a, UInt64(0), a_data, UInt(16))

    with AllocGuard[Float32](4) as b_data:
        b_data[0] = Float32(10.0); b_data[1] = Float32(20.0)
        b_data[2] = Float32(30.0); b_data[3] = Float32(40.0)
        device.queue_write_buffer(buf_b, UInt64(0), b_data, UInt(16))

    var bg_entries = List[WGPUBindGroupEntry]()
    bg_entries.append(WGPUBindGroupEntry(OpaquePointer[MutExternalOrigin](unsafe_from_address=0), UInt32(0), buf_a.handle().raw, UInt64(0), WGPU_WHOLE_SIZE, OpaquePointer[MutExternalOrigin](unsafe_from_address=0), OpaquePointer[MutExternalOrigin](unsafe_from_address=0)))
    bg_entries.append(WGPUBindGroupEntry(OpaquePointer[MutExternalOrigin](unsafe_from_address=0), UInt32(1), buf_b.handle().raw, UInt64(0), WGPU_WHOLE_SIZE, OpaquePointer[MutExternalOrigin](unsafe_from_address=0), OpaquePointer[MutExternalOrigin](unsafe_from_address=0)))
    bg_entries.append(WGPUBindGroupEntry(OpaquePointer[MutExternalOrigin](unsafe_from_address=0), UInt32(2), buf_c.handle().raw, UInt64(0), WGPU_WHOLE_SIZE, OpaquePointer[MutExternalOrigin](unsafe_from_address=0), OpaquePointer[MutExternalOrigin](unsafe_from_address=0)))
    var bg = device.create_bind_group(bgl, bg_entries)
    # Required: removing these pins reproducibly crashes in device_create_bind_group
    # due to Mojo ASAP lifetime + raw handles embedded in entry structs.
    _ = bgl^
    _ = buf_a^
    _ = buf_b^
    _ = buf_c^

    var enc = device.create_command_encoder("vec_add_enc")
    var cpass = enc.begin_compute_pass()
    cpass.set_pipeline(pipeline)
    cpass.set_bind_group(UInt32(0), bg)
    cpass.dispatch_workgroups(N_ELEMENTS, UInt32(1), UInt32(1))
    cpass^.end()

    enc.copy_buffer_to_buffer(buf_c, UInt64(0), buf_r, UInt64(0), BUF_SIZE)

    var cmd = enc^.finish()
    device.queue_submit(cmd)

    var raw = buf_r.map_read(UInt64(0), UInt64(16))
    var result = raw.bitcast[Float32]()
    assert_equal(result[0], Float32(11.0))
    assert_equal(result[1], Float32(22.0))
    assert_equal(result[2], Float32(33.0))
    assert_equal(result[3], Float32(44.0))
    print("GPU vector add result:", result[0], result[1], result[2], result[3])

    buf_r.unmap()
    # Pin: wgpu-native may free device on release; map_read needs it alive
    _ = device^


def main() raises:
    test_create_compute_pipeline()
    test_vec_add_compute()
    print("test_compute_pipeline: ALL PASSED")
