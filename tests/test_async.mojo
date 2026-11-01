"""
The non-blocking request API (#14) against its blocking twin.

Each async request is driven only through ready(), the way a frame-driven host
calls it, and must give the same result as the blocking call. Requires GPU
hardware.
"""

from std.testing import assert_true, assert_equal
from wgpu.device import Device
from wgpu.instance import Instance
from wgpu._ffi.alloc_guard import AllocGuard
from wgpu._ffi.types import WGPUBufferUsage, WGPUMapMode




def async_device() raises -> Device:
    var instance = Instance()
    var areq = instance.request_adapter_async()
    for _ in range(1_000_000):
        if areq.ready():
            break
    var adapter = areq.take()
    var dreq = adapter.request_device_async("async")
    for _ in range(1_000_000):
        if dreq.ready():
            break
    return dreq.take()


def test_adapter_and_device_async() raises:
    """The async route yields a working device, like the blocking one."""
    var device = async_device()
    var buf = device.create_buffer(UInt64(64), WGPUBufferUsage.COPY_DST, False, "probe")
    assert_true(buf)


def upload_and_copy(device: Device, n: Int, read_buf_label: String) raises -> List[Float32]:
    """Write 0..n-1 to a GPU buffer and copy it into a readback buffer, then
    read it back once blocking and once through map_async + ready()."""
    var size = UInt64(n * 4)
    var gpu = device.create_buffer(size, WGPUBufferUsage.COPY_DST | WGPUBufferUsage.COPY_SRC, False, "gpu")
    var rb_block = device.create_buffer(size, WGPUBufferUsage.MAP_READ | WGPUBufferUsage.COPY_DST, False, read_buf_label + "_b")
    var rb_async = device.create_buffer(size, WGPUBufferUsage.MAP_READ | WGPUBufferUsage.COPY_DST, False, read_buf_label + "_a")
    with AllocGuard[Float32](n) as data:
        for i in range(n):
            data[unsafe_offset=i] = Float32(i)
        device._lib[].queue_write_buffer(
            device.queue().raw, gpu.handle().raw, UInt64(0), data.unsafe_bitcast[NoneType](), UInt(size)
        )
    var enc = device.create_command_encoder("copy")
    enc.copy_buffer_to_buffer(gpu, UInt64(0), rb_block, UInt64(0), size)
    enc.copy_buffer_to_buffer(gpu, UInt64(0), rb_async, UInt64(0), size)
    device.queue_submit(enc^.finish())

    var blocking = rb_block.read_data[Float32]()

    var req = rb_async.map_async(WGPUMapMode.READ)
    var polls = 0
    while not req.ready():
        polls += 1
        if polls > 1_000_000:
            raise Error("map_async never completed")
    var p = req.take().unsafe_bitcast[Float32]()
    for i in range(n):
        assert_equal(p[unsafe_offset=i], blocking[i])
    rb_async.unmap()
    _ = gpu^
    _ = rb_block^
    _ = rb_async^
    return blocking^


def test_map_async_matches_map_read() raises:
    var device = async_device()
    var got = upload_and_copy(device, 256, "rb")
    assert_equal(got[255], Float32(255))
    _ = device^


def test_work_done_async() raises:
    var device = async_device()
    var src = device.create_buffer(64, WGPUBufferUsage.COPY_SRC | WGPUBufferUsage.COPY_DST, False, "src")
    var dst = device.create_buffer(64, WGPUBufferUsage.COPY_DST, False, "dst")
    var enc = device.create_command_encoder("wd")
    enc.copy_buffer_to_buffer(src, UInt64(0), dst, UInt64(0), 64)
    device.queue_submit(enc^.finish())
    var req = device.on_submitted_work_done_async()
    var polls = 0
    while not req.ready():
        polls += 1
        if polls > 1_000_000:
            raise Error("work-done never completed")
    req.take()
    _ = src^
    _ = dst^
    _ = device^


def invalid_buffer(device: Device) raises:
    # MAP_READ may only be combined with COPY_DST: a validation error.
    try:
        _ = device.create_buffer(64, WGPUBufferUsage.MAP_READ | WGPUBufferUsage.STORAGE, False, "bad")
    except:
        pass


def test_error_scope_async_matches_blocking() raises:
    var device = async_device()

    device.push_error_scope()
    invalid_buffer(device)
    var blocking = device.pop_error_scope()

    device.push_error_scope()
    invalid_buffer(device)
    var req = device.pop_error_scope_async()
    var polls = 0
    while not req.ready():
        polls += 1
        if polls > 1_000_000:
            raise Error("pop_error_scope_async never completed")
    var nonblocking = req.take()

    assert_true(blocking.byte_length() > 0, "expected a validation error")
    assert_equal(nonblocking, blocking)

    device.push_error_scope()
    var empty = device.pop_error_scope_async()
    while not empty.ready():
        pass
    assert_equal(empty.take(), "")
    _ = device^


def main() raises:
    test_adapter_and_device_async()
    print("  PASS: adapter + device through ready()")
    test_map_async_matches_map_read()
    print("  PASS: map_async bytes == map_read bytes")
    test_work_done_async()
    print("  PASS: on_submitted_work_done_async")
    test_error_scope_async_matches_blocking()
    print("  PASS: pop_error_scope_async == pop_error_scope")
    print("test_async: ALL PASSED")
