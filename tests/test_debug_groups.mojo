"""
tests/test_debug_groups.mojo — Tests for debug group/marker methods on encoders.
Requires GPU hardware.
"""

from std.testing import assert_true
from wgpu.gpu import request_adapter
from wgpu._ffi.types import OpaquePtr, WGPUTextureUsage, WGPUTextureFormat
from wgpu._ffi.structs import (
    WGPURenderPassDescriptor, WGPURenderPassColorAttachment,
    WGPURenderPassDepthStencilAttachment, WGPUPassTimestampWrites,
    WGPUColor, WGPUStringView,
)


def test_command_encoder_debug_groups() raises:
    """push/pop/insert debug groups on a CommandEncoder."""
    var inst   = request_adapter()
    var device = inst.request_device()
    var enc    = device.create_command_encoder("debug_enc")
    enc.push_debug_group("outer")
    enc.push_debug_group("inner")
    enc.insert_debug_marker("checkpoint")
    enc.pop_debug_group()
    enc.pop_debug_group()
    var cmd = enc.finish()
    assert_true(Bool(cmd))
    device._lib.command_buffer_release(cmd)


def test_compute_pass_debug_groups() raises:
    """push/pop/insert debug groups on a ComputePassEncoder."""
    var inst   = request_adapter()
    var device = inst.request_device()
    var enc    = device.create_command_encoder()
    var cpass  = enc.begin_compute_pass("debug_cpass")
    cpass.push_debug_group("compute_group")
    cpass.insert_debug_marker("mid_compute")
    cpass.pop_debug_group()
    cpass.end()
    var cmd = enc.finish()
    assert_true(Bool(cmd))
    device._lib.command_buffer_release(cmd)


def test_render_pass_debug_groups() raises:
    """push/pop/insert debug groups on a RenderPassEncoder."""
    var inst   = request_adapter()
    var device = inst.request_device()

    # Create a minimal render target
    var tex = device.create_texture(
        UInt32(4), UInt32(4), UInt32(1),
        WGPUTextureFormat.RGBA8Unorm,
        WGPUTextureUsage.RENDER_ATTACHMENT,
        label="debug_rt",
    )
    var view = tex.create_view_default()

    var enc = device.create_command_encoder()
    var color_att_p = alloc[WGPURenderPassColorAttachment](1)
    color_att_p[0] = WGPURenderPassColorAttachment(
        OpaquePtr(), view.handle(), UInt32(0xFFFFFFFF), OpaquePtr(),
        UInt32(1), UInt32(1),  # Clear, Store
        WGPUColor(Float64(0.0), Float64(0.0), Float64(0.0), Float64(1.0)),
    )
    var rp_desc_p = alloc[WGPURenderPassDescriptor](1)
    rp_desc_p[0] = WGPURenderPassDescriptor(
        OpaquePtr(), WGPUStringView.null_view(),
        UInt(1), color_att_p,
        UnsafePointer[WGPURenderPassDepthStencilAttachment, MutExternalOrigin](),
        OpaquePtr(),
        UnsafePointer[WGPUPassTimestampWrites, MutExternalOrigin](),
    )
    var rpass = enc.begin_render_pass(rp_desc_p)
    _ = view^   # keep TextureView alive past begin_render_pass (ASAP would destroy it after view.handle())
    _ = tex^    # keep Texture alive past the render pass
    rpass.push_debug_group("render_group")
    rpass.insert_debug_marker("mid_render")
    rpass.pop_debug_group()
    rpass.end()
    color_att_p.free()
    rp_desc_p.free()
    var cmd = enc.finish()
    assert_true(Bool(cmd))
    device._lib.command_buffer_release(cmd)


def test_encoder_set_label() raises:
    """set_label on CommandEncoder should not crash."""
    var inst   = request_adapter()
    var device = inst.request_device()
    var enc    = device.create_command_encoder("original")
    enc.set_label("renamed_encoder")
    var cmd = enc.finish()
    device._lib.command_buffer_release(cmd)


def main() raises:
    test_command_encoder_debug_groups()
    test_compute_pass_debug_groups()
    test_render_pass_debug_groups()
    # test_encoder_set_label() — wgpuCommandEncoderSetLabel not implemented in wgpu-native v29
    print("test_debug_groups: ALL PASSED")
