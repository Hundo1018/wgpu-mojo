"""
Tests/test_bind_group.mojo — Tests for BindGroupLayout and BindGroup creation.
Requires GPU hardware.
"""

from std.testing import assert_true
from wgpu.device import Device
from wgpu.instance import Instance
from wgpu._ffi.types import (
    WGPUBufferUsage, WGPUShaderStage,
)
from wgpu._ffi.structs import (
    WGPUBindGroupLayoutEntry,
    WGPUBufferBindingLayout, WGPUSamplerBindingLayout,
    WGPUTextureBindingLayout, WGPUStorageTextureBindingLayout,
    WGPUBindGroupEntry,
)
from wgpu._ffi.types import WGPU_WHOLE_SIZE


def create_test_device() raises -> Device:
    var instance = Instance()
    var adapter = instance.request_adapter()
    return adapter.request_device()


def make_storage_bgl_entry(
    binding: UInt32,
    read_only: Bool = False,
) -> WGPUBindGroupLayoutEntry:
    """Create a BindGroupLayoutEntry for a storage buffer binding."""
    # Type 3 = Storage (read_write), Type 4 = ReadOnlyStorage
    var buf_type: UInt32 = UInt32(4) if read_only else UInt32(3)
    return WGPUBindGroupLayoutEntry(
        OpaquePointer[MutExternalOrigin](unsafe_from_address=0),
        binding,
        WGPUShaderStage.COMPUTE.value,
        UInt32(0),
        WGPUBufferBindingLayout(OpaquePointer[MutExternalOrigin](unsafe_from_address=0), buf_type, UInt32(0), UInt64(0)),
        WGPUSamplerBindingLayout(OpaquePointer[MutExternalOrigin](unsafe_from_address=0), UInt32(0)),
        WGPUTextureBindingLayout(OpaquePointer[MutExternalOrigin](unsafe_from_address=0), UInt32(0), UInt32(0), UInt32(0)),
        WGPUStorageTextureBindingLayout(OpaquePointer[MutExternalOrigin](unsafe_from_address=0), UInt32(0), UInt32(0), UInt32(0)),
    )


def test_create_bind_group_layout() raises:
    """Create a BindGroupLayout with one storage buffer binding."""
    var device = create_test_device()

    var entries: List[WGPUBindGroupLayoutEntry] = [make_storage_bgl_entry(UInt32(0))]
    var bgl = device.create_bind_group_layout(entries, "test_bgl")
    assert_true(bgl)


def test_create_bind_group_with_buffer() raises:
    """Create a BindGroup referencing a storage buffer."""
    var device = create_test_device()

    var buf = device.create_buffer(
        UInt64(256), WGPUBufferUsage.STORAGE | WGPUBufferUsage.COPY_DST, False
    )

    var bgl_entries: List[WGPUBindGroupLayoutEntry] = [make_storage_bgl_entry(UInt32(0))]
    var bgl = device.create_bind_group_layout(bgl_entries)

    var bg_entries: List[WGPUBindGroupEntry] = [
        WGPUBindGroupEntry(
            OpaquePointer[MutExternalOrigin](unsafe_from_address=0),
            UInt32(0),
            buf.handle().raw,
            UInt64(0),
            WGPU_WHOLE_SIZE,
            OpaquePointer[MutExternalOrigin](unsafe_from_address=0),
            OpaquePointer[MutExternalOrigin](unsafe_from_address=0),
        )
    ]
    var bg = device.create_bind_group(bgl, bg_entries)
    assert_true(bg)

    # Pin: raw handles from buf/bgl are embedded in FFI descriptors
    # passed to create_bind_group — ASAP could destroy them after .handle().raw
    _ = buf^
    _ = bgl^


def main() raises:
    test_create_bind_group_layout()
    test_create_bind_group_with_buffer()
    print("test_bind_group: ALL PASSED")
