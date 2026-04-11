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
    var qs     = device.create_query_set(UInt32(1), UInt32(8), "occlusion_qs")  # Occlusion = 1
    assert_true(Bool(qs.handle()))
    assert_equal(qs.get_count(), UInt32(8))
    assert_equal(qs.get_type(), UInt32(1))  # Occlusion


def main() raises:
    test_create_occlusion_query_set()
    # test_create_timestamp_query_set() — requires timestamp-query device feature
    # test_query_set_set_label() — wgpuQuerySetSetLabel not implemented in wgpu-native v29
    print("test_query_set: ALL PASSED")
