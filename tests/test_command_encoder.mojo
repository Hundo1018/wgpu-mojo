"""
Tests/test_command_encoder.mojo — Tests for CommandEncoder operations.
Requires GPU hardware.
"""

from std.testing import assert_true, assert_equal
from wgpu.device import Device
from wgpu.instance import Instance
from wgpu._ffi.types import WGPUBufferUsage


def create_test_device() raises -> Device:
    var instance = Instance()
    var adapter = instance.request_adapter()
    return adapter.request_device()


def test_create_command_encoder() raises:
    """CommandEncoder creation should return non-null."""
    var device = create_test_device()
    var enc    = device.create_command_encoder("test_enc")
    var is_valid = enc.handle().raw != OpaquePointer[MutExternalOrigin](unsafe_from_address=0)
    enc^.abandon()  # linear type: must explicitly consume
    assert_true(is_valid)


def test_finish_empty_encoder() raises:
    """Finishing an empty command encoder produces a valid CommandBuffer."""
    var device = create_test_device()
    var enc    = device.create_command_encoder()
    var cmd    = enc^.finish()
    assert_true(cmd.raw != OpaquePointer[MutExternalOrigin](unsafe_from_address=0))


def test_submit_empty_command_buffer() raises:
    """Submitting an empty command buffer to the queue should succeed."""
    var device = create_test_device()
    var enc    = device.create_command_encoder()
    var cmd    = enc^.finish()
    device.queue_submit(cmd)
    _ = device.poll(True)


def test_copy_buffer_to_buffer() raises:
    """Copy data from one buffer to another via CommandEncoder."""
    var device = create_test_device()
    var size: UInt64 = 64
    var src = device.create_buffer(size, WGPUBufferUsage.COPY_SRC | WGPUBufferUsage.MAP_WRITE, False, "src")
    var dst = device.create_buffer(size, WGPUBufferUsage.COPY_DST | WGPUBufferUsage.MAP_READ, False, "dst")
    var enc = device.create_command_encoder()
    enc.copy_buffer_to_buffer(src, UInt64(0), dst, UInt64(0), size)
    var cmd = enc^.finish()
    device.queue_submit(cmd)
    _ = device.poll(True)


def main() raises:
    test_create_command_encoder()
    test_finish_empty_encoder()
    test_submit_empty_command_buffer()
    test_copy_buffer_to_buffer()
    print("test_command_encoder: ALL PASSED")
