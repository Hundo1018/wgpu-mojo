"""
tests/test_buffer.mojo — Integration tests for Buffer creation, write, map, read.
Requires GPU hardware.
"""

from testing import assert_true, assert_equal
from wgpu.gpu import request_adapter
from wgpu._ffi.types import WGPUBufferUsage


def test_create_storage_buffer() raises:
    """Create a GPU storage buffer; handle should be non-null."""
    var inst   = request_adapter()
    var device = inst.request_device()
    var handle = device.create_buffer(
        UInt64(256),
        WGPUBufferUsage.Storage | WGPUBufferUsage.CopyDst,
        False,
        "test_storage_buf",
    )
    assert_true(Bool(handle))
    device._lib.buffer_release(handle)


def test_create_staging_buffer_mapped() raises:
    """Create a mappable staging buffer with mapped_at_creation=True."""
    var inst   = request_adapter()
    var device = inst.request_device()
    var usage  = WGPUBufferUsage.MapWrite | WGPUBufferUsage.CopySrc
    var handle = device.create_buffer(UInt64(64), usage, True, "staging")
    assert_true(Bool(handle))
    # Write data via mapped range (already mapped at creation)
    var ptr = device._lib.buffer_get_mapped_range(handle, UInt(0), UInt(64))
    assert_true(Bool(ptr))
    device._lib.buffer_unmap(handle)
    device._lib.buffer_release(handle)


def test_queue_write_and_map_read_buffer() raises:
    """Write to a buffer via queue, copy to readback, map and verify data."""
    var inst   = request_adapter()
    var device = inst.request_device()

    # 4 x Float32 values = 16 bytes
    var n: UInt64 = 16
    comptime N = 4

    # GPU storage buffer (CopyDst | CopySrc)
    var gpu_buf = device.create_buffer(
        n, WGPUBufferUsage.CopyDst | WGPUBufferUsage.CopySrc, False, "gpu"
    )
    # CPU readback buffer (MapRead | CopyDst)
    var read_buf = device.create_buffer(
        n, WGPUBufferUsage.MapRead | WGPUBufferUsage.CopyDst, False, "readback"
    )

    # Upload data
    var data = List[Float32](1.0, 2.0, 3.0, 4.0)
    var data_ptr = data.unsafe_ptr()
    device._lib.queue_write_buffer(
        device.queue(), gpu_buf, UInt64(0),
        data_ptr.bitcast[NoneType](), UInt(16)
    )

    # Copy gpu → readback
    var enc = device.create_command_encoder("copy_enc")
    device._lib.command_encoder_copy_buffer_to_buffer(enc, gpu_buf, 0, read_buf, 0, n)
    var cmd_desc_null = UnsafePointer[NoneType, MutExternalOrigin]()
    var cmd_buf = device._lib.command_encoder_finish(enc, cmd_desc_null.bitcast())
    var cmds = List[OpaquePtr](cmd_buf)
    device._lib.queue_submit(device.queue(), UInt(1), cmds.unsafe_ptr())

    # Wait for GPU
    _ = device.poll(True)

    # Map readback
    var status = device._lib.buffer_map_async(
        device.instance(), device.handle(),
        read_buf, UInt64(1),  # MapRead
        UInt(0), UInt(16)
    )
    assert_equal(status, UInt32(1))  # MapAsyncStatus.Success

    var mapped = device._lib.buffer_get_const_mapped_range(read_buf, UInt(0), UInt(16))
    var result = mapped.bitcast[Float32]()
    assert_equal(result[0], Float32(1.0))
    assert_equal(result[1], Float32(2.0))
    assert_equal(result[2], Float32(3.0))
    assert_equal(result[3], Float32(4.0))

    device._lib.buffer_unmap(read_buf)
    device._lib.buffer_release(gpu_buf)
    device._lib.buffer_release(read_buf)
    device._lib.command_encoder_release(enc)
    device._lib.command_buffer_release(cmd_buf)
