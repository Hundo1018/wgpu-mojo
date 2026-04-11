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
    # Type 3 = Storage (read_write), Type 4 = ReadOnlyStorage
    var buf_type: UInt32 = UInt32(4) if read_only else UInt32(3)
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

    var entries_p = alloc[WGPUBindGroupLayoutEntry](1)
    entries_p[0] = make_storage_bgl_entry(UInt32(0))
    var label   = str_to_sv(String("test_bgl"))
    var desc    = WGPUBindGroupLayoutDescriptor(
        OpaquePtr(),
        label,
        UInt(1),
        entries_p,
    )
    var bgl = device.create_bind_group_layout(desc)
    entries_p.free()
    assert_true(Bool(bgl.handle()))
    
    # Pin GPU objects past usage
    _ = bgl^
    _ = device^
    _ = inst^


def test_create_bind_group_with_buffer() raises:
    """Create a BindGroup referencing a storage buffer."""
    var inst   = request_adapter()
    var device = inst.request_device()

    var buf = device.create_buffer(
        UInt64(256), WGPUBufferUsage.STORAGE | WGPUBufferUsage.COPY_DST, False
    )

    var entries_p = alloc[WGPUBindGroupLayoutEntry](1)
    entries_p[0] = make_storage_bgl_entry(UInt32(0))
    var bgl_desc = WGPUBindGroupLayoutDescriptor(
        OpaquePtr(), WGPUStringView.null_view(), UInt(1), entries_p
    )
    var bgl = device.create_bind_group_layout(bgl_desc)
    entries_p.free()

    var bg_entries_p = alloc[WGPUBindGroupEntry](1)
    bg_entries_p[0] = WGPUBindGroupEntry(
        OpaquePtr(),
        UInt32(0),
        buf.handle(),
        UInt64(0),
        WGPU_WHOLE_SIZE,
        OpaquePtr(),
        OpaquePtr(),
    )
    var bg_desc = WGPUBindGroupDescriptor(
        OpaquePtr(), WGPUStringView.null_view(), bgl.handle(), UInt(1), bg_entries_p
    )
    var bg = device.create_bind_group(bg_desc)
    bg_entries_p.free()
    assert_true(Bool(bg.handle()))
    
    # Pin GPU objects past usage
    _ = buf^
    _ = bgl^
    _ = bg^
    _ = device^
    _ = inst^


def main() raises:
    test_create_bind_group_layout()
    test_create_bind_group_with_buffer()
    print("test_bind_group: ALL PASSED")
