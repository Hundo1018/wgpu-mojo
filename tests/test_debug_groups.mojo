"""
Tests/test_debug_groups.mojo — Tests for debug group/marker methods on encoders.
Requires GPU hardware.
"""

from std.testing import assert_true
from wgpu.device import Device
from wgpu.instance import Instance
from wgpu._ffi.types import WGPUTextureUsage, WGPUTextureFormat
from wgpu._ffi.structs import (
    WGPURenderPassDescriptor, WGPURenderPassColorAttachment,
    WGPURenderPassDepthStencilAttachment, WGPUPassTimestampWrites,
    WGPUColor, WGPUStringView,
)


def create_test_device() raises -> Device:
    var instance = Instance()
    var adapter = instance.request_adapter()
    return adapter.request_device()


def test_command_encoder_debug_groups() raises:
    """Push/pop/insert debug groups on a CommandEncoder."""
    var device = create_test_device()
    var enc    = device.create_command_encoder("debug_enc")
    enc.push_debug_group("outer")
    enc.push_debug_group("inner")
    enc.insert_debug_marker("checkpoint")
    enc.pop_debug_group()
    enc.pop_debug_group()
    var cmd = enc^.finish()
    assert_true(cmd.raw() != OpaquePointer[MutExternalOrigin](unsafe_from_address=0))


def test_compute_pass_debug_groups() raises:
    """Push/pop/insert debug groups on a ComputePassEncoder."""
    var device = create_test_device()
    var enc    = device.create_command_encoder()
    var cpass  = enc.begin_compute_pass("debug_cpass")
    cpass.push_debug_group("compute_group")
    cpass.insert_debug_marker("mid_compute")
    cpass.pop_debug_group()
    cpass^.end()
    var cmd = enc^.finish()
    assert_true(cmd.raw() != OpaquePointer[MutExternalOrigin](unsafe_from_address=0))


def test_render_pass_debug_groups() raises:
    """Push/pop/insert debug groups on a RenderPassEncoder."""
    var device = create_test_device()

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
        OpaquePointer[MutExternalOrigin](unsafe_from_address=0), view.handle().raw, UInt32(0xFFFFFFFF), OpaquePointer[MutExternalOrigin](unsafe_from_address=0),
        UInt32(1), UInt32(1),  # Clear, Store
        WGPUColor(Float64(0.0), Float64(0.0), Float64(0.0), Float64(1.0)),
    )
    var rp_desc_p = alloc[WGPURenderPassDescriptor](1)
    rp_desc_p[0] = WGPURenderPassDescriptor(
        OpaquePointer[MutExternalOrigin](unsafe_from_address=0), WGPUStringView.null_view(),
        UInt(1), color_att_p,
        UnsafePointer[WGPURenderPassDepthStencilAttachment, MutExternalOrigin](unsafe_from_address=0),
        OpaquePointer[MutExternalOrigin](unsafe_from_address=0),
        UnsafePointer[WGPUPassTimestampWrites, MutExternalOrigin](unsafe_from_address=0),
    )
    var rpass = enc.begin_render_pass(rp_desc_p)
    # Required: view.handle().raw is embedded in color attachment descriptor.
    # Removing this pin reproducibly crashes in command_encoder_begin_render_pass.
    _ = view^
    rpass.push_debug_group("render_group")
    rpass.insert_debug_marker("mid_render")
    rpass.pop_debug_group()
    rpass^.end()
    color_att_p.free()
    rp_desc_p.free()
    var cmd = enc^.finish()
    assert_true(cmd.raw() != OpaquePointer[MutExternalOrigin](unsafe_from_address=0))


def test_encoder_set_label() raises:
    """Set_label on CommandEncoder should not crash."""
    var device = create_test_device()
    var enc    = device.create_command_encoder("original")
    enc.set_label("renamed_encoder")
    _ = enc^.finish()


def main() raises:
    test_command_encoder_debug_groups()
    test_compute_pass_debug_groups()
    test_render_pass_debug_groups()
    # test_encoder_set_label() — wgpuCommandEncoderSetLabel not implemented in wgpu-native v29
    print("test_debug_groups: ALL PASSED")
