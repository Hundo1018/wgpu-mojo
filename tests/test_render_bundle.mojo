"""
Tests/test_render_bundle.mojo — Tests for RenderBundleEncoder / RenderBundle.
Requires GPU hardware.
"""

from std.testing import assert_true
from wgpu.device import Device
from wgpu.instance import Instance
from wgpu._ffi.types import WGPUTextureFormat


def create_test_device() raises -> Device:
    var instance = Instance()
    var adapter = instance.request_adapter()
    return adapter.request_device()


def test_create_render_bundle_encoder() raises:
    """Create a RenderBundleEncoder for a simple RGBA8Unorm color target."""
    var device = create_test_device()
    var formats = List[UInt32]()
    formats.append(WGPUTextureFormat.RGBA8Unorm)
    var enc = device.create_render_bundle_encoder(formats, "test_enc")
    var valid = Int(enc.handle().raw) != 0
    enc^.abandon()
    assert_true(valid)


def test_render_bundle_encoder_finish_abandon() raises:
    """finish() must return a non-null RenderBundle; abandon() must not crash."""
    var device = create_test_device()
    var formats = List[UInt32]()
    formats.append(WGPUTextureFormat.BGRA8Unorm)
    var enc = device.create_render_bundle_encoder(formats, "finish_test")
    var bundle = enc^.finish("my_bundle")
    assert_true(bundle)

    var device2 = create_test_device()
    var formats2 = List[UInt32]()
    formats2.append(WGPUTextureFormat.BGRA8Unorm)
    var enc2 = device2.create_render_bundle_encoder(formats2, "abandon_test")
    enc2^.abandon()


def main() raises:
    test_create_render_bundle_encoder()
    test_render_bundle_encoder_finish_abandon()
    print("test_render_bundle: ALL PASSED")
