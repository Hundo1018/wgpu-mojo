"""
Tests/test_error_scope.mojo — Tests for Device push/pop_error_scope.
Requires GPU hardware.
"""

from std.testing import assert_true, assert_equal
from wgpu.device import Device
from wgpu.instance import Instance
from wgpu._ffi.types import WGPUErrorFilter, WGPUBufferUsage


def create_test_device() raises -> Device:
    var instance = Instance()
    var adapter = instance.request_adapter()
    return adapter.request_device()


def test_pop_error_scope_no_error() raises:
    """Push a validation scope, do nothing illegal, pop — should return empty string."""
    var device = create_test_device()
    device.push_error_scope()
    var msg = device.pop_error_scope()
    assert_equal(msg, "")


def test_pop_error_scope_catches_validation_error() raises:
    """Push a validation scope, create an invalid buffer (0-size STORAGE), pop — should capture an error."""
    var device = create_test_device()
    device.push_error_scope()
    # A zero-size STORAGE buffer is invalid per the WebGPU spec.
    try:
        _ = device.create_buffer(0, WGPUBufferUsage.STORAGE, False, "bad_buf")
    except:
        pass
    var msg = device.pop_error_scope()
    assert_true(msg.byte_length() > 0)


def main() raises:
    test_pop_error_scope_no_error()
    test_pop_error_scope_catches_validation_error()
    print("test_error_scope: ALL PASSED")
