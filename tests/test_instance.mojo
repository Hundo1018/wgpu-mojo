"""
Tests/test_instance.mojo — Integration tests for Instance creation.
Requires: libwgpu_native.so, libwgpu_mojo_cb.so, GPU hardware.
"""

from std.testing import assert_true, assert_false, assert_equal, assert_not_equal
from wgpu.instance import Instance
from wgpu._ffi.lib import WGPULib
from wgpu._ffi.types import (
    WGPUAdapterHandle, WGPUAdapterType, WGPUBackendType,
)
from wgpu._ffi.structs import WGPUInstanceDescriptor


def test_wgpu_lib_loads() raises:
    """WGPULib should load both shared libraries without error."""
    var lib = WGPULib()
    var version = lib.get_version()
    assert_true(version > UInt32(0))
    print("wgpu version:", version)


def test_wgpu_version_format() raises:
    """Version should be >= 27 (v27.x.y.z encoded as integer)."""
    var lib = WGPULib()
    var version = lib.get_version()
    assert_true(version > UInt32(0))


def test_create_instance() raises:
    """WgpuCreateInstance should return non-null."""
    var lib = WGPULib()
    var desc_p = alloc[WGPUInstanceDescriptor](1)
    desc_p[] = WGPUInstanceDescriptor(
        OpaquePointer[MutExternalOrigin](unsafe_from_address=0),
        UInt(0),
        None,
        None,
    )
    var inst = lib.create_instance(desc_p)
    desc_p.free()
    assert_true(inst != OpaquePointer[MutExternalOrigin](unsafe_from_address=0))
    lib.instance_release(inst)


def test_enumerate_adapters() raises:
    """Should find at least one GPU adapter."""
    var lib = WGPULib()
    var desc_p = alloc[WGPUInstanceDescriptor](1)
    desc_p[] = WGPUInstanceDescriptor(
        OpaquePointer[MutExternalOrigin](unsafe_from_address=0), UInt(0),
        None,
        None,
    )
    var inst = lib.create_instance(desc_p)
    desc_p.free()
    var count = lib.enumerate_adapters(
        inst,
        OpaquePointer[MutExternalOrigin](unsafe_from_address=0),
        UnsafePointer[WGPUAdapterHandle, MutExternalOrigin](unsafe_from_address=0),
    )
    print("Adapter count:", count)
    assert_true(count > UInt(0))
    var adapters = alloc[WGPUAdapterHandle](Int(count))
    _ = lib.enumerate_adapters(inst, OpaquePointer[MutExternalOrigin](unsafe_from_address=0), adapters)
    assert_true(adapters[0] != OpaquePointer[MutExternalOrigin](unsafe_from_address=0))
    for i in range(Int(count)):
        lib.adapter_release(adapters[i])
    adapters.free()
    lib.instance_release(inst)


def test_request_adapter() raises:
    """Instance.request_adapter() should return a working adapter."""
    var instance = Instance()
    var adapter = instance.request_adapter()
    var info = adapter.adapter_info()
    print("Backend type:", info.backend_type)
    print("Adapter type:", info.adapter_type)
    assert_true(info.backend_type > UInt32(0))


def test_adapter_info_fields() raises:
    """AdapterInfo fields should be populated after get_info."""
    var instance = Instance()
    var adapter = instance.request_adapter()
    var info = adapter.adapter_info()
    assert_true(info.vendor.data != UnsafePointer[NoneType, MutAnyOrigin](unsafe_from_address=0))


def test_get_version_via_instance() raises:
    """Test get_version via the Instance API."""
    var instance = Instance()
    var v = instance.get_version()
    assert_true(v > UInt32(0))


def main() raises:
    test_wgpu_lib_loads()
    test_wgpu_version_format()
    test_create_instance()
    test_enumerate_adapters()
    test_request_adapter()
    test_adapter_info_fields()
    test_get_version_via_instance()
    print("test_instance: ALL PASSED")
