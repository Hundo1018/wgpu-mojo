"""
tests/test_texture.mojo — Tests for Texture and TextureView creation.
Requires GPU hardware.
"""

from testing import assert_true, assert_equal
from wgpu.gpu import request_adapter
from wgpu._ffi.types import (
    OpaquePtr, WGPUTextureUsage, WGPUTextureFormat,
)


def test_create_2d_texture() raises:
    """Create a simple 2D RGBA8Unorm texture."""
    var inst   = request_adapter()
    var device = inst.request_device()
    var handle = device.create_texture(
        UInt32(256), UInt32(256), UInt32(1),
        WGPUTextureFormat.RGBA8Unorm,
        WGPUTextureUsage.TextureBinding | WGPUTextureUsage.CopySrc,
        2, 1, 1, "tex2d"
    )
    assert_true(Bool(handle))
    assert_equal(device._lib.texture_get_width(handle), UInt32(256))
    assert_equal(device._lib.texture_get_height(handle), UInt32(256))
    assert_equal(device._lib.texture_get_format(handle), WGPUTextureFormat.RGBA8Unorm)
    device._lib.texture_destroy(handle)
    device._lib.texture_release(handle)


def test_create_texture_view() raises:
    """Create a default TextureView from a 2D texture."""
    var inst   = request_adapter()
    var device = inst.request_device()
    var tex = device.create_texture(
        UInt32(64), UInt32(64), UInt32(1),
        WGPUTextureFormat.RGBA8Unorm,
        WGPUTextureUsage.TextureBinding | WGPUTextureUsage.CopyDst,
        2, 1, 1
    )
    var view = device._lib.texture_create_view(
        tex, UnsafePointer[WGPUTextureViewDescriptor, MutExternalOrigin]()
    )
    assert_true(Bool(view))
    device._lib.texture_view_release(view)
    device._lib.texture_destroy(tex)
    device._lib.texture_release(tex)


def test_texture_dimensions() raises:
    """Texture dimensions match what was specified at creation."""
    var inst   = request_adapter()
    var device = inst.request_device()
    var w: UInt32 = 512
    var h: UInt32 = 256
    var tex = device.create_texture(
        w, h, UInt32(1),
        WGPUTextureFormat.BGRA8Unorm,
        WGPUTextureUsage.CopyDst | WGPUTextureUsage.CopySrc,
        2, 1, 1
    )
    assert_equal(device._lib.texture_get_width(tex), w)
    assert_equal(device._lib.texture_get_height(tex), h)
    device._lib.texture_destroy(tex)
    device._lib.texture_release(tex)
