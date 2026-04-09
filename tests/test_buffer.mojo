"""
tests/test_buffer.mojo — Integration tests for Buffer creation, write, map, read.
Requires GPU hardware.
"""

from std.testing import assert_true, assert_equal
from wgpu.gpu import request_adapter
from wgpu._ffi.types import OpaquePtr, WGPUBufferUsage
from wgpu._ffi.structs import WGPUCommandBufferDescriptor, WGPUStringView


def test_create_storage_buffer() raises:
    """Create a GPU storage buffer; handle should be non-null."""
    var inst   = request_adapter()
    var device = inst.request_device()
    var handle = device.create_buffer(
        UInt64(256),
        WGPUBufferUsage.STORAGE | WGPUBufferUsage.COPY_DST,
        False,
        "test_storage_buf",
    )
    assert_true(Bool(handle))
    device._lib.buffer_release(handle)


def test_create_staging_buffer_mapped() raises:
    """Create a mappable staging buffer with mapped_at_creation=True."""
    var inst   = request_adapter()
    var device = inst.request_device()
    var usage  = WGPUBufferUsage.MAP_WRITE | WGPUBufferUsage.COPY_SRC
    var handle = device.create_buffer(UInt64(64), usage, True, "staging")
    assert_true(Bool(handle))
    var ptr = device._lib.buffer_get_mapped_range(handle, UInt(0), UInt(64))
    assert_true(Bool(ptr))
    device._lib.buffer_unmap(handle)
    device._lib.buffer_release(handle)


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
        device.queue(), gpu_buf, UInt64(0),
        data.bitcast[NoneType](), UInt(16)
    )

    # Copy gpu -> readback
    var enc = device.create_command_encoder("copy_enc")
    device._lib.command_encoder_copy_buffer_to_buffer(enc, gpu_buf, UInt64(0), read_buf, UInt64(0), n)
    var cmd_desc_p = alloc[WGPUCommandBufferDescriptor](1)
    cmd_desc_p[] = WGPUCommandBufferDescriptor(OpaquePtr(), WGPUStringView.null_view())
    var cmd_buf = device._lib.command_encoder_finish(enc, cmd_desc_p)
    cmd_desc_p.free()
    var cmds = alloc[OpaquePtr](1)
    cmds[] = cmd_buf
    device._lib.queue_submit(device.queue(), UInt(1), cmds)

    # Wait for GPU
    _ = device.poll(True)

    # Map readback
    var status = device._lib.buffer_map_async(
        device.instance(), device.handle(),
        read_buf, UInt64(1),
        UInt(0), UInt(16)
    )
    assert_equal(status, UInt32(1))

    var mapped = device._lib.buffer_get_const_mapped_range(read_buf, UInt(0), UInt(16))
    var result = mapped.bitcast[Float32]()
    assert_equal(result[0], Float32(1.0))
    assert_equal(result[1], Float32(2.0))
    assert_equal(result[2], Float32(3.0))
    assert_equal(result[3], Float32(4.0))

    device._lib.buffer_unmap(read_buf)
    data.free()
    cmds.free()
    device._lib.buffer_release(gpu_buf)
    device._lib.buffer_release(read_buf)


def main() raises:
    test_create_storage_buffer()
    test_create_staging_buffer_mapped()
    test_queue_write_and_map_read_buffer()
    print("test_buffer: ALL PASSED")
