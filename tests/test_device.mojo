"""
tests/test_device.mojo — Integration tests for Device creation and queries.
Requires GPU hardware.
"""

from testing import assert_true, assert_false, assert_equal
from wgpu.gpu import request_adapter
from wgpu._ffi.types import WGPUFeatureName, WGPU_LIMIT_U32_UNDEFINED


def test_request_device() raises:
    """Device creation should succeed."""
    var inst   = request_adapter()
    var device = inst.request_device()
    assert_true(Bool(device.handle()))


def test_device_get_limits() raises:
    """Device limits should have non-UNDEFINED values after get_limits."""
    var inst   = request_adapter()
    var device = inst.request_device()
    var limits = device.get_limits()
    # At least max_bind_groups should be reasonable
    assert_true(limits.max_bind_groups > UInt32(0))
    assert_true(limits.max_bind_groups < WGPU_LIMIT_U32_UNDEFINED)
    print("max_bind_groups:", limits.max_bind_groups)
    print("max_buffer_size:", limits.max_buffer_size)


def test_device_has_feature() raises:
    """has_feature should not crash and returns a Bool."""
    var inst   = request_adapter()
    var device = inst.request_device()
    # Depth clip control is widely supported
    var has_dcc = device.has_feature(WGPUFeatureName.DepthClipControl)
    print("has DepthClipControl:", has_dcc)


def test_device_poll() raises:
    """device.poll() should return without error."""
    var inst   = request_adapter()
    var device = inst.request_device()
    _ = device.poll(False)


def test_queue_available() raises:
    """Queue should be non-null after device creation."""
    var inst   = request_adapter()
    var device = inst.request_device()
    assert_true(Bool(device.queue()))
