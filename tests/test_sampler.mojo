"""
Tests/test_sampler.mojo — Tests for Sampler creation.
Requires GPU hardware.
"""

from std.testing import assert_true
from wgpu.device import Device
from wgpu.instance import Instance


def create_test_device() raises -> Device:
    var instance = Instance()
    var adapter = instance.request_adapter()
    return adapter.request_device()


def test_create_default_sampler() raises:
    """Create a sampler with default settings."""
    var device = create_test_device()
    var sampler = device.create_sampler(label="default_sampler")
    assert_true(sampler)


def test_create_linear_sampler() raises:
    """Create a sampler with linear filtering."""
    var device = create_test_device()
    var sampler = device.create_sampler(
        address_mode_u=UInt32(2),
        address_mode_v=UInt32(2),
        address_mode_w=UInt32(1),
        mag_filter=UInt32(1),
        min_filter=UInt32(1),
        mipmap_filter=UInt32(1),
        label="linear_sampler",
    )
    assert_true(sampler)


def test_create_anisotropic_sampler() raises:
    """Create a sampler with max anisotropy."""
    var device = create_test_device()
    var sampler = device.create_sampler(
        mag_filter=UInt32(2),      # Linear (required when anisotropy > 1)
        min_filter=UInt32(2),      # Linear (required when anisotropy > 1)
        mipmap_filter=UInt32(2),   # Linear (required when anisotropy > 1)
        max_anisotropy=UInt16(16),
        label="aniso_sampler",
    )
    assert_true(sampler)


def main() raises:
    test_create_default_sampler()
    test_create_linear_sampler()
    test_create_anisotropic_sampler()
    print("test_sampler: ALL PASSED")
