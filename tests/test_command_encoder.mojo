"""
tests/test_command_encoder.mojo — Tests for CommandEncoder operations.
Requires GPU hardware.
"""

from testing import assert_true, assert_equal
from wgpu.gpu import request_adapter
from wgpu._ffi.types import OpaquePtr, WGPUBufferUsage
from wgpu._ffi.structs import (
    WGPUCommandBufferDescriptor, WGPUStringView,
)


def test_create_command_encoder() raises:
    """CommandEncoder creation should return non-null."""
    var inst   = request_adapter()
    var device = inst.request_device()
    var enc    = device.create_command_encoder("test_enc")
    assert_true(Bool(enc))
    device._lib.command_encoder_release(enc)


def test_finish_empty_encoder() raises:
    """Finishing an empty command encoder produces a valid CommandBuffer."""
    var inst   = request_adapter()
    var device = inst.request_device()
    var enc    = device.create_command_encoder()
    var desc_p = alloc[WGPUCommandBufferDescriptor](1)
    desc_p[] = WGPUCommandBufferDescriptor(OpaquePtr(), WGPUStringView.null_view())
    var cmd    = device._lib.command_encoder_finish(enc, desc_p)
    desc_p.free()
    assert_true(Bool(cmd))
    device._lib.command_buffer_release(cmd)
    device._lib.command_encoder_release(enc)


def test_submit_empty_command_buffer() raises:
    """Submitting an empty command buffer to the queue should succeed."""
    var inst   = request_adapter()
    var device = inst.request_device()
    var enc    = device.create_command_encoder()
    var desc_p = alloc[WGPUCommandBufferDescriptor](1)
    desc_p[] = WGPUCommandBufferDescriptor(OpaquePtr(), WGPUStringView.null_view())
    var cmd    = device._lib.command_encoder_finish(enc, desc_p)
    desc_p.free()
    var cmds   = List[OpaquePtr](cmd)
    device._lib.queue_submit(device.queue(), UInt(1), cmds.unsafe_ptr())
    _ = device.poll(True)
    device._lib.command_buffer_release(cmd)
    device._lib.command_encoder_release(enc)


def test_copy_buffer_to_buffer() raises:
    """Copy data from one buffer to another via CommandEncoder."""
    var inst   = request_adapter()
    var device = inst.request_device()
    var size: UInt64 = 64
    var src = device.create_buffer(size, WGPUBufferUsage.CopySrc | WGPUBufferUsage.MapWrite, False, "src")
    var dst = device.create_buffer(size, WGPUBufferUsage.CopyDst | WGPUBufferUsage.MapRead, False, "dst")
    var enc = device.create_command_encoder()
    device._lib.command_encoder_copy_buffer_to_buffer(enc, src, 0, dst, 0, size)
    var desc_p = alloc[WGPUCommandBufferDescriptor](1)
    desc_p[] = WGPUCommandBufferDescriptor(OpaquePtr(), WGPUStringView.null_view())
    var cmd  = device._lib.command_encoder_finish(enc, desc_p)
    desc_p.free()
    var cmds = List[OpaquePtr](cmd)
    device._lib.queue_submit(device.queue(), UInt(1), cmds.unsafe_ptr())
    _ = device.poll(True)
    device._lib.command_buffer_release(cmd)
    device._lib.command_encoder_release(enc)
    device._lib.buffer_release(src)
    device._lib.buffer_release(dst)
