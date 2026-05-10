"""
Tests/test_query_set.mojo — Tests for QuerySet creation and properties.
Requires GPU hardware.
"""

from std.testing import assert_true, assert_equal
from wgpu.device import Device
from wgpu.instance import Instance


def create_test_device() raises -> Device:
    var instance = Instance()
    var adapter = instance.request_adapter()
    return adapter.request_device()


def test_create_occlusion_query_set() raises:
    """Create an occlusion query set with 8 queries."""
    var device = create_test_device()
    var qs     = device.create_query_set(UInt32(1), UInt32(8), "occlusion_qs")  # Occlusion = 1
    assert_true(qs)
    assert_equal(qs.get_count(), UInt32(8))
    assert_equal(qs.get_type(), UInt32(1))  # Occlusion


def main() raises:
    test_create_occlusion_query_set()
    # test_create_timestamp_query_set() — requires timestamp-query device feature
    # test_query_set_set_label() — wgpuQuerySetSetLabel not implemented in wgpu-native v29
    print("test_query_set: ALL PASSED")
