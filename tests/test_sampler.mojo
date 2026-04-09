"""
tests/test_sampler.mojo — Tests for Sampler creation.
Requires GPU hardware.
"""

from testing import assert_true
from wgpu.gpu import request_adapter
from wgpu._ffi.types import OpaquePtr
from wgpu._ffi.structs import WGPUSamplerDescriptor, WGPUStringView


def test_create_default_sampler() raises:
    """Create a sampler with default (nearest) settings."""
    var inst   = request_adapter()
    var device = inst.request_device()
    var handle = device.create_sampler(label="default_sampler")
    assert_true(Bool(handle))
    device._lib.sampler_release(handle)


def test_create_linear_sampler() raises:
    """Create a sampler with linear filtering."""
    var inst   = request_adapter()
    var device = inst.request_device()
    var handle = device.create_sampler(
        address_mode_u=UInt32(2),  # Repeat
        address_mode_v=UInt32(2),
        address_mode_w=UInt32(1),  # ClampToEdge
        mag_filter=UInt32(1),      # Linear
        min_filter=UInt32(1),      # Linear
        mipmap_filter=UInt32(1),   # Linear
        label="linear_sampler",
    )
    assert_true(Bool(handle))
    device._lib.sampler_release(handle)


def test_create_anisotropic_sampler() raises:
    """Create a sampler with max anisotropy."""
    var inst   = request_adapter()
    var device = inst.request_device()
    var handle = device.create_sampler(
        mag_filter=UInt32(1),
        min_filter=UInt32(1),
        max_anisotropy=UInt16(16),
        label="aniso_sampler",
    )
    assert_true(Bool(handle))
    device._lib.sampler_release(handle)
