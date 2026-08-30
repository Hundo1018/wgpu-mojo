"""
Integration tests for Device creation and queries.
Requires GPU hardware.
"""

from wgpu._ffi.nulls import null_opaque, null_ptr, null_any_ptr
from std.testing import assert_true, assert_false, assert_equal
from std.memory import OpaquePointer
from wgpu.device import Device
from wgpu.instance import Instance
from wgpu._ffi.types import WGPUFeatureName, WGPU_LIMIT_U32_UNDEFINED


def create_test_device() raises -> Device:
    var instance = Instance()
    var adapter = instance.request_adapter()
    return adapter.request_device()


def test_request_device() raises:
    """Device creation should succeed."""
    var device = create_test_device()
    assert_true(device)


def test_device_get_limits() raises:
    """Device limits should have non-UNDEFINED values after get_limits."""
    var device = create_test_device()
    var limits = device.get_limits()
    assert_true(limits.max_bind_groups > UInt32(0))
    assert_true(limits.max_bind_groups < WGPU_LIMIT_U32_UNDEFINED)
    print("max_bind_groups:", limits.max_bind_groups)
    print("max_buffer_size:", limits.max_buffer_size)


def test_device_has_feature() raises:
    """Has_feature should not crash and returns a Bool."""
    var device = create_test_device()
    var has_dcc = device.has_feature(WGPUFeatureName.DepthClipControl)
    print("has DepthClipControl:", has_dcc)


def test_device_poll() raises:
    """Device.poll() should return without error."""
    var device = create_test_device()
    _ = device.poll(False)


def test_queue_available() raises:
    """Queue should be non-null after device creation."""
    var device = create_test_device()
    assert_true(device.queue().raw != null_opaque())


def test_graphics_debugger_capture() raises:
    """Capture start/stop must be safe with no debugger attached.

    wgpuDeviceStartGraphicsDebuggerCapture returns false when nothing is
    listening; the pair must not error or abort either way.
    """
    var device = create_test_device()
    device.push_error_scope()
    var started = device.start_graphics_debugger_capture()
    if started:
        device.stop_graphics_debugger_capture()
    var err = device.pop_error_scope()
    assert_equal(err.byte_length(), 0, "debugger capture raised: " + err)
    _ = device^


def test_native_metal_handles_are_null_off_metal() raises:
    """The Metal getters return null on non-Metal backends rather than failing.

    On macOS these return real MTLDevice / MTLCommandQueue pointers; this
    asserts only that calling them anywhere is safe.
    """
    var device = create_test_device()
    var mtl_device = device.native_metal_device()
    var mtl_queue  = device.native_metal_command_queue()
    _ = mtl_device
    _ = mtl_queue
    _ = device^


def main() raises:
    test_request_device()
    test_device_get_limits()
    test_device_has_feature()
    test_device_poll()
    test_queue_available()
    test_graphics_debugger_capture()
    test_native_metal_handles_are_null_off_metal()
    print("test_device: ALL PASSED")
