"""
tests/test_command_encoder.mojo — Tests for CommandEncoder operations.
Requires GPU hardware.
"""

from std.testing import assert_true, assert_equal
from wgpu.gpu import request_adapter
from wgpu._ffi.types import OpaquePtr, WGPUBufferUsage


def test_create_command_encoder() raises:
    """CommandEncoder creation should return non-null."""
    var inst   = request_adapter()
    var device = inst.request_device()
    var enc    = device.create_command_encoder("test_enc")
    assert_true(Bool(enc.handle()))


def test_finish_empty_encoder() raises:
    """Finishing an empty command encoder produces a valid CommandBuffer."""
    var inst   = request_adapter()
    var device = inst.request_device()
    var enc    = device.create_command_encoder()
    var cmd    = enc.finish()
    assert_true(Bool(cmd))
    device._lib.command_buffer_release(cmd)


def test_submit_empty_command_buffer() raises:
    """Submitting an empty command buffer to the queue should succeed."""
    var inst   = request_adapter()
    var device = inst.request_device()
    var enc    = device.create_command_encoder()
    var cmd    = enc.finish()
    var cmds   = List[OpaquePtr]()
    cmds.append(cmd)
    device.queue_submit(cmds)
    _ = device.poll(True)
    device._lib.command_buffer_release(cmd)


def test_copy_buffer_to_buffer() raises:
    """Copy data from one buffer to another via CommandEncoder."""
    var inst   = request_adapter()
    var device = inst.request_device()
    var size: UInt64 = 64
    var src = device.create_buffer(size, WGPUBufferUsage.COPY_SRC | WGPUBufferUsage.MAP_WRITE, False, "src")
    var dst = device.create_buffer(size, WGPUBufferUsage.COPY_DST | WGPUBufferUsage.MAP_READ, False, "dst")
    var enc = device.create_command_encoder()
    enc.copy_buffer_to_buffer(src.handle(), UInt64(0), dst.handle(), UInt64(0), size)
    var cmd = enc.finish()
    var cmds = List[OpaquePtr]()
    cmds.append(cmd)
    device.queue_submit(cmds)
    _ = device.poll(True)
    _ = src^
    _ = dst^
    _ = enc^
    device._lib.command_buffer_release(cmd)


def main() raises:
    test_create_command_encoder()
    test_finish_empty_encoder()
    test_submit_empty_command_buffer()
    test_copy_buffer_to_buffer()
    print("test_command_encoder: ALL PASSED")
