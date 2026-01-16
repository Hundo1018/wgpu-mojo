"""
tests/test_device.mojo — Integration tests for Device creation and queries.
Requires GPU hardware.
"""

from std.testing import assert_true, assert_false, assert_equal
from wgpu.gpu import GPU
from wgpu._ffi.types import WGPUFeatureName, WGPU_LIMIT_U32_UNDEFINED


def test_request_device() raises:
    """Device creation should succeed."""
    var gpu    = GPU()
    var device = gpu.request_device()
    assert_true(Bool(device.handle().raw))


def test_device_get_limits() raises:
    """Device limits should have non-UNDEFINED values after get_limits."""
    var gpu    = GPU()
    var device = gpu.request_device()
    var limits = device.get_limits()
    assert_true(limits.max_bind_groups > UInt32(0))
    assert_true(limits.max_bind_groups < WGPU_LIMIT_U32_UNDEFINED)
    print("max_bind_groups:", limits.max_bind_groups)
    print("max_buffer_size:", limits.max_buffer_size)


def test_device_has_feature() raises:
    """has_feature should not crash and returns a Bool."""
    var gpu    = GPU()
    var device = gpu.request_device()
    var has_dcc = device.has_feature(WGPUFeatureName.DepthClipControl)
    print("has DepthClipControl:", has_dcc)


def test_device_poll() raises:
    """device.poll() should return without error."""
    var gpu    = GPU()
    var device = gpu.request_device()
    _ = device.poll(False)


def test_queue_available() raises:
    """Queue should be non-null after device creation."""
    var gpu    = GPU()
    var device = gpu.request_device()
    assert_true(Bool(device.queue().raw))


def main() raises:
    test_request_device()
    test_device_get_limits()
    test_device_has_feature()
    test_device_poll()
    test_queue_available()
    print("test_device: ALL PASSED")
