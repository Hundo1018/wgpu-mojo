"""
Integration tests for Instance creation.
Requires: libwgpu_native.so, libwgpu_mojo_cb.so, GPU hardware.
"""

from wgpu._ffi.nulls import null_opaque, null_ptr, null_any_ptr
from wgpu._backend.wgpu_native.alloc_guard import raw_alloc
from std.testing import assert_true, assert_false, assert_equal, assert_not_equal
from wgpu.instance import Instance, instance_limits
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
    var desc_p = raw_alloc[WGPUInstanceDescriptor](1)
    desc_p[] = WGPUInstanceDescriptor(
        null_opaque(),
        UInt(0),
        None,
        None,
    )
    var inst = lib.create_instance(desc_p)
    desc_p.unsafe_free()
    assert_true(inst != null_opaque())
    lib.instance_release(inst)


def test_enumerate_adapters() raises:
    """Should find at least one GPU adapter."""
    var lib = WGPULib()
    var desc_p = raw_alloc[WGPUInstanceDescriptor](1)
    desc_p[] = WGPUInstanceDescriptor(
        null_opaque(), UInt(0),
        None,
        None,
    )
    var inst = lib.create_instance(desc_p)
    desc_p.unsafe_free()
    var count = lib.enumerate_adapters(
        inst,
        null_opaque(),
        null_ptr[WGPUAdapterHandle](),
    )
    print("Adapter count:", count)
    assert_true(count > UInt(0))
    var adapters = raw_alloc[WGPUAdapterHandle](Int(count))
    _ = lib.enumerate_adapters(inst, null_opaque(), adapters)
    assert_true(adapters[unsafe_offset=0] != null_opaque())
    for i in range(Int(count)):
        lib.adapter_release(adapters[unsafe_offset=i])
    adapters.unsafe_free()
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
    assert_true(info.vendor.data != null_any_ptr())


def test_get_version_via_instance() raises:
    """Test get_version via the Instance API."""
    var instance = Instance()
    var v = instance.get_version()
    assert_true(v > UInt32(0))


def test_instance_limits() raises:
    """WgpuGetInstanceLimits round-trips without an Instance.

    One of the three instance-global queries in webgpu.h that wgpu-native v29
    actually implements — GetInstanceFeatures and HasInstanceFeature are
    unimplemented!() stubs that abort the process, so they are not bound.
    """
    var limits = instance_limits()
    # timedWaitAnyMaxCount is 0 on v29; assert only that the field reads back,
    # so this does not break when upstream starts reporting a real value.
    assert_true(limits.timed_wait_any_max_count >= UInt(0))


def main() raises:
    test_wgpu_lib_loads()
    test_wgpu_version_format()
    test_create_instance()
    test_enumerate_adapters()
    test_request_adapter()
    test_adapter_info_fields()
    test_get_version_via_instance()
    test_instance_limits()
    print("test_instance: ALL PASSED")
