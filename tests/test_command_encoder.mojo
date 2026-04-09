"""
tests/test_command_encoder.mojo — Tests for CommandEncoder operations.
Requires GPU hardware.
"""

from std.testing import assert_true, assert_equal
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


def test_submit_empty_command_buffer() raises:
    """Submitting an empty command buffer to the queue should succeed."""
    var inst   = request_adapter()
    var device = inst.request_device()
    var enc    = device.create_command_encoder()
    var desc_p = alloc[WGPUCommandBufferDescriptor](1)
    desc_p[] = WGPUCommandBufferDescriptor(OpaquePtr(), WGPUStringView.null_view())
    var cmd    = device._lib.command_encoder_finish(enc, desc_p)
    desc_p.free()
    var cmds_p   = alloc[OpaquePtr](1)
    cmds_p[]   = cmd
    device._lib.queue_submit(device.queue(), UInt(1), cmds_p)
    _ = device.poll(True)
    cmds_p.free()
    device._lib.command_buffer_release(cmd)


def test_copy_buffer_to_buffer() raises:
    """Copy data from one buffer to another via CommandEncoder."""
    var inst   = request_adapter()
    var device = inst.request_device()
    var size: UInt64 = 64
    var src = device.create_buffer(size, WGPUBufferUsage.COPY_SRC | WGPUBufferUsage.MAP_WRITE, False, "src")
    var dst = device.create_buffer(size, WGPUBufferUsage.COPY_DST | WGPUBufferUsage.MAP_READ, False, "dst")
    var enc = device.create_command_encoder()
    device._lib.command_encoder_copy_buffer_to_buffer(enc, src, UInt64(0), dst, UInt64(0), size)
    var desc_p = alloc[WGPUCommandBufferDescriptor](1)
    desc_p[] = WGPUCommandBufferDescriptor(OpaquePtr(), WGPUStringView.null_view())
    var cmd  = device._lib.command_encoder_finish(enc, desc_p)
    desc_p.free()
    var cmds_p = alloc[OpaquePtr](1)
    cmds_p[] = cmd
    device._lib.queue_submit(device.queue(), UInt(1), cmds_p)
    _ = device.poll(True)
    cmds_p.free()
    device._lib.command_buffer_release(cmd)
    device._lib.buffer_release(src)
    device._lib.buffer_release(dst)


def main() raises:
    test_create_command_encoder()
    test_finish_empty_encoder()
    test_submit_empty_command_buffer()
    test_copy_buffer_to_buffer()
    print("test_command_encoder: ALL PASSED")
