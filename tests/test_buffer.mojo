"""
tests/test_buffer.mojo — Integration tests for Buffer creation, write, map, read.
Requires GPU hardware.
"""

from std.testing import assert_true, assert_equal
from wgpu.gpu import request_adapter
from wgpu._ffi.types import OpaquePtr, WGPUBufferUsage


def test_create_storage_buffer() raises:
    """Create a GPU storage buffer; handle should be non-null."""
    var inst   = request_adapter()
    var device = inst.request_device()
    var buf = device.create_buffer(
        UInt64(256),
        WGPUBufferUsage.STORAGE | WGPUBufferUsage.COPY_DST,
        False,
        "test_storage_buf",
    )
    assert_true(Bool(buf.handle()))


def test_create_staging_buffer_mapped() raises:
    """Create a mappable staging buffer with mapped_at_creation=True."""
    var inst   = request_adapter()
    var device = inst.request_device()
    var usage  = WGPUBufferUsage.MAP_WRITE | WGPUBufferUsage.COPY_SRC
    var buf = device.create_buffer(UInt64(64), usage, True, "staging")
    assert_true(Bool(buf.handle()))
    var ptr = device._lib.buffer_get_mapped_range(buf.handle(), UInt(0), UInt(64))
    assert_true(Bool(ptr))
    buf.unmap()


def test_queue_write_and_map_read_buffer() raises:
    """Write to a buffer via queue, copy to readback, map and verify data."""
    var inst   = request_adapter()
    var device = inst.request_device()

    var n: UInt64 = 16

    # GPU storage buffer (CopyDst | CopySrc)
    var gpu_buf = device.create_buffer(
        n, WGPUBufferUsage.COPY_DST | WGPUBufferUsage.COPY_SRC, False, "gpu"
    )
    # CPU readback buffer (MapRead | CopyDst)
    var read_buf = device.create_buffer(
        n, WGPUBufferUsage.MAP_READ | WGPUBufferUsage.COPY_DST, False, "readback"
    )

    # Upload data
    var data = alloc[Float32](4)
    data[0] = Float32(1.0)
    data[1] = Float32(2.0)
    data[2] = Float32(3.0)
    data[3] = Float32(4.0)
    device._lib.queue_write_buffer(
        device.queue(), gpu_buf.handle(), UInt64(0),
        data.bitcast[NoneType](), UInt(16)
    )

    # Copy gpu -> readback
    var enc = device.create_command_encoder("copy_enc")
    enc.copy_buffer_to_buffer(gpu_buf.handle(), UInt64(0), read_buf.handle(), UInt64(0), n)
    var cmd_buf = enc.finish()
    var cmds = List[OpaquePtr]()
    cmds.append(cmd_buf)
    device.queue_submit(cmds)

    # Wait for GPU
    _ = device.poll(True)

    # Map readback and verify
    var raw = read_buf.map_read()
    var result = raw.bitcast[Float32]()
    assert_equal(result[0], Float32(1.0))
    assert_equal(result[1], Float32(2.0))
    assert_equal(result[2], Float32(3.0))
    assert_equal(result[3], Float32(4.0))

    read_buf.unmap()
    data.free()


def main() raises:
    test_create_storage_buffer()
    test_create_staging_buffer_mapped()
    test_queue_write_and_map_read_buffer()
    print("test_buffer: ALL PASSED")
