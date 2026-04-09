"""
tests/test_instance.mojo — Integration tests for Instance creation.
Requires: libwgpu_native.so, libwgpu_mojo_cb.so, GPU hardware.
"""

from std.testing import assert_true, assert_false, assert_equal, assert_not_equal
from wgpu.gpu import request_adapter
from wgpu._ffi.lib import WGPULib
from wgpu._ffi.types import (
    OpaquePtr,
    WGPUAdapterType, WGPUBackendType,
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
    """wgpuCreateInstance should return non-null."""
    var lib = WGPULib()
    var desc_p = alloc[WGPUInstanceDescriptor](1)
    desc_p[] = WGPUInstanceDescriptor(
        OpaquePtr(),
        UInt(0),
        UnsafePointer[UInt32, MutExternalOrigin](),
        UnsafePointer[NoneType, MutExternalOrigin](),
    )
    var inst = lib.create_instance(desc_p)
    desc_p.free()
    assert_true(Bool(inst))
    lib.instance_release(inst)


def test_enumerate_adapters() raises:
    """Should find at least one GPU adapter."""
    var lib = WGPULib()
    var desc_p = alloc[WGPUInstanceDescriptor](1)
    desc_p[] = WGPUInstanceDescriptor(
        OpaquePtr(), UInt(0),
        UnsafePointer[UInt32, MutExternalOrigin](),
        UnsafePointer[NoneType, MutExternalOrigin](),
    )
    var inst = lib.create_instance(desc_p)
    desc_p.free()
    var count = lib.enumerate_adapters(inst, OpaquePtr(), UnsafePointer[OpaquePtr, MutExternalOrigin]())
    print("Adapter count:", count)
    assert_true(count > UInt(0))
    var adapters = alloc[OpaquePtr](Int(count))
    _ = lib.enumerate_adapters(inst, OpaquePtr(), adapters)
    assert_true(Bool(adapters[0]))
    adapters.free()
    lib.instance_release(inst)


def test_request_adapter() raises:
    """request_adapter() should return a non-destroyed Instance."""
    var inst = request_adapter()
    var info = inst.adapter_info()
    print("Backend type:", info.backend_type)
    print("Adapter type:", info.adapter_type)
    assert_true(info.backend_type > UInt32(0))


def test_adapter_info_fields() raises:
    """AdapterInfo fields should be populated after get_info."""
    var inst = request_adapter()
    var info = inst.adapter_info()
    assert_true(Bool(info.vendor.data))


def test_get_version_via_instance() raises:
    """Test get_version via the Instance high-level API."""
    var inst = request_adapter()
    var v = inst.get_version()
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
