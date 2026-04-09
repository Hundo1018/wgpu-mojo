"""
tests/test_bind_group.mojo — Tests for BindGroupLayout and BindGroup creation.
Requires GPU hardware.
"""

from std.testing import assert_true
from wgpu.gpu import request_adapter
from wgpu._ffi.types import (
    OpaquePtr, WGPUBufferUsage, WGPUShaderStage,
)
from wgpu._ffi.structs import (
    WGPUBindGroupLayoutEntry, WGPUBindGroupLayoutDescriptor,
    WGPUBufferBindingLayout, WGPUSamplerBindingLayout,
    WGPUTextureBindingLayout, WGPUStorageTextureBindingLayout,
    WGPUBindGroupEntry, WGPUBindGroupDescriptor,
    str_to_sv, WGPUStringView,
)
from wgpu._ffi.types import WGPU_WHOLE_SIZE


def make_storage_bgl_entry(
    binding: UInt32,
    read_only: Bool = False,
) -> WGPUBindGroupLayoutEntry:
    """Create a BindGroupLayoutEntry for a storage buffer binding."""
    var buf_type: UInt32 = 3 if read_only else 2
    return WGPUBindGroupLayoutEntry(
        OpaquePtr(),
        binding,
        WGPUShaderStage.COMPUTE.value,
        UInt32(0),
        WGPUBufferBindingLayout(OpaquePtr(), buf_type, UInt32(0), UInt64(0)),
        WGPUSamplerBindingLayout(OpaquePtr(), UInt32(0)),
        WGPUTextureBindingLayout(OpaquePtr(), UInt32(0), UInt32(0), UInt32(0)),
        WGPUStorageTextureBindingLayout(OpaquePtr(), UInt32(0), UInt32(0), UInt32(0)),
    )


def test_create_bind_group_layout() raises:
    """Create a BindGroupLayout with one storage buffer binding."""
    var inst   = request_adapter()
    var device = inst.request_device()

    var entries = List[WGPUBindGroupLayoutEntry](make_storage_bgl_entry(UInt32(0)))
    var label   = str_to_sv(String("test_bgl"))
    var desc    = WGPUBindGroupLayoutDescriptor(
        OpaquePtr(),
        label,
        UInt(1),
        entries.unsafe_ptr(),
    )
    var bgl = device.create_bind_group_layout(desc)
    assert_true(Bool(bgl))
    device._lib.bind_group_layout_release(bgl)


def test_create_bind_group_with_buffer() raises:
    """Create a BindGroup referencing a storage buffer."""
    var inst   = request_adapter()
    var device = inst.request_device()

    var buf = device.create_buffer(
        UInt64(256), WGPUBufferUsage.STORAGE | WGPUBufferUsage.COPY_DST, False
    )

    var entries_layout = List[WGPUBindGroupLayoutEntry](make_storage_bgl_entry(UInt32(0)))
    var bgl_desc = WGPUBindGroupLayoutDescriptor(
        OpaquePtr(), WGPUStringView.null_view(), UInt(1), entries_layout.unsafe_ptr()
    )
    var bgl = device.create_bind_group_layout(bgl_desc)

    var entry = WGPUBindGroupEntry(
        OpaquePtr(),
        UInt32(0),
        buf,
        UInt64(0),
        WGPU_WHOLE_SIZE,
        OpaquePtr(),
        OpaquePtr(),
    )
    var bg_entries = List[WGPUBindGroupEntry](entry)
    var bg_desc = WGPUBindGroupDescriptor(
        OpaquePtr(), WGPUStringView.null_view(), bgl, UInt(1), bg_entries.unsafe_ptr()
    )
    var bg = device.create_bind_group(bg_desc)
    assert_true(Bool(bg))

    device._lib.bind_group_release(bg)
    device._lib.bind_group_layout_release(bgl)
    device._lib.buffer_release(buf)


def main() raises:
    test_create_bind_group_layout()
    test_create_bind_group_with_buffer()
    print("test_bind_group: ALL PASSED")
