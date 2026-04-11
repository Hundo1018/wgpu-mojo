"""
tests/test_texture.mojo — Tests for Texture and TextureView creation.
Requires GPU hardware.
"""

from std.testing import assert_true, assert_equal
from wgpu.gpu import request_adapter
from wgpu._ffi.types import (
    OpaquePtr, WGPUTextureUsage, WGPUTextureFormat,
)
from wgpu._ffi.structs import WGPUTextureViewDescriptor


def test_create_2d_texture() raises:
    """Create a simple 2D RGBA8Unorm texture."""
    var inst   = request_adapter()
    var device = inst.request_device()
    var tex = device.create_texture(
        UInt32(256), UInt32(256), UInt32(1),
        WGPUTextureFormat.RGBA8Unorm,
        WGPUTextureUsage.TEXTURE_BINDING | WGPUTextureUsage.COPY_SRC,
        2, 1, 1, "tex2d"
    )
    assert_true(Bool(tex.handle()))
    assert_equal(tex.width(), UInt32(256))
    assert_equal(tex.height(), UInt32(256))
    assert_equal(tex.format(), WGPUTextureFormat.RGBA8Unorm)
    
    # Pin GPU objects past usage
    _ = tex^
    _ = device^
    _ = inst^


def test_create_texture_view() raises:
    """Create a default TextureView from a 2D texture."""
    var inst   = request_adapter()
    var device = inst.request_device()
    var tex = device.create_texture(
        UInt32(64), UInt32(64), UInt32(1),
        WGPUTextureFormat.RGBA8Unorm,
        WGPUTextureUsage.TEXTURE_BINDING | WGPUTextureUsage.COPY_DST,
        2, 1, 1
    )
    var view = tex.create_view_default()
    assert_true(Bool(view.handle()))
    
    # Pin GPU objects past usage
    _ = tex^
    _ = view^
    _ = device^
    _ = inst^


def test_texture_dimensions() raises:
    """Texture dimensions match what was specified at creation."""
    var inst   = request_adapter()
    var device = inst.request_device()
    var w: UInt32 = 512
    var h: UInt32 = 256
    var tex = device.create_texture(
        w, h, UInt32(1),
        WGPUTextureFormat.BGRA8Unorm,
        WGPUTextureUsage.COPY_DST | WGPUTextureUsage.COPY_SRC,
        2, 1, 1
    )
    assert_equal(tex.width(), w)
    assert_equal(tex.height(), h)
    
    # Pin GPU objects past usage
    _ = tex^
    _ = device^
    _ = inst^


def main() raises:
    test_create_2d_texture()
    test_create_texture_view()
    test_texture_dimensions()
    print("test_texture: ALL PASSED")
