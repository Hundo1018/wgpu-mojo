"""
Tests/test_buffer.mojo — Integration tests for Buffer creation, write, map, read.
Requires GPU hardware.
"""

from std.testing import assert_true, assert_equal
from wgpu.device import Device
from wgpu.instance import Instance
from wgpu._ffi.alloc_guard import AllocGuard
from wgpu._ffi.types import WGPUBufferUsage


def create_test_device() raises -> Device:
    var instance = Instance()
    var adapter = instance.request_adapter()
    return adapter.request_device()


def test_create_storage_buffer() raises:
    """Create a GPU storage buffer; handle should be non-null."""
    var device = create_test_device()
    var buf = device.create_buffer(
        UInt64(256),
        WGPUBufferUsage.STORAGE | WGPUBufferUsage.COPY_DST,
        False,
        "test_storage_buf",
    )
    assert_true(buf)


def test_create_staging_buffer_mapped() raises:
    """Create a mappable staging buffer with mapped_at_creation=True."""
    var device = create_test_device()
    var usage  = WGPUBufferUsage.MAP_WRITE | WGPUBufferUsage.COPY_SRC
    var buf = device.create_buffer(UInt64(64), usage, True, "staging")
    assert_true(buf)
    var ptr = device._lib[].buffer_get_mapped_range(buf.handle().raw, UInt(0), UInt(64))
    assert_true(ptr != OpaquePointer[MutExternalOrigin](unsafe_from_address=0))
    buf.unmap()


def test_queue_write_and_map_read_buffer() raises:
    """Write to a buffer via queue, copy to readback, map and verify data."""
    var device = create_test_device()

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
    with AllocGuard[Float32](4) as data:
        data[0] = Float32(1.0)
        data[1] = Float32(2.0)
        data[2] = Float32(3.0)
        data[3] = Float32(4.0)
        device._lib[].queue_write_buffer(
            device.queue().raw, gpu_buf.handle().raw, UInt64(0),
            data.bitcast[NoneType](), UInt(16)
        )

    # Copy gpu -> readback
    var enc = device.create_command_encoder("copy_enc")
    enc.copy_buffer_to_buffer(gpu_buf, UInt64(0), read_buf, UInt64(0), n)
    var cmd_buf = enc^.finish()
    device.queue_submit(cmd_buf)

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
    # Pin: wgpu-native may free device on release; map_read needs it alive
    _ = device^


def main() raises:
    test_create_storage_buffer()
    test_create_staging_buffer_mapped()
    test_queue_write_and_map_read_buffer()
    print("test_buffer: ALL PASSED")
