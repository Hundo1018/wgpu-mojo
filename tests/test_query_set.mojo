"""
tests/test_query_set.mojo — Tests for QuerySet creation and properties.
Requires GPU hardware.
"""

from std.testing import assert_true, assert_equal
from wgpu.gpu import request_adapter
from wgpu._ffi.types import OpaquePtr


def test_create_occlusion_query_set() raises:
    """Create an occlusion query set with 8 queries."""
    var inst   = request_adapter()
    var device = inst.request_device()
    var qs     = device.create_query_set(UInt32(0), UInt32(8), "occlusion_qs")  # Occlusion = 0
    assert_true(Bool(qs.handle()))
    assert_equal(qs.get_count(), UInt32(8))
    assert_equal(qs.get_type(), UInt32(0))  # Occlusion


def test_create_timestamp_query_set() raises:
    """Create a timestamp query set (requires TimestampQuery feature)."""
    var inst   = request_adapter()
    var device = inst.request_device()
    # Timestamp type = 1 per WebGPU spec
    # This may fail if the adapter doesn't support timestamps;
    # we still test the API surface works.
    var qs = device.create_query_set(UInt32(1), UInt32(4), "ts_qs")
    assert_true(Bool(qs.handle()))
    assert_equal(qs.get_count(), UInt32(4))


def test_query_set_set_label() raises:
    """set_label should not crash."""
    var inst   = request_adapter()
    var device = inst.request_device()
    var qs     = device.create_query_set(UInt32(0), UInt32(2), "orig")
    qs.set_label("renamed")


def main() raises:
    test_create_occlusion_query_set()
    test_create_timestamp_query_set()
    test_query_set_set_label()
    print("test_query_set: ALL PASSED")
