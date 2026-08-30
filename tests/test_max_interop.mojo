"""
tests/test_max_interop.mojo — round trips across the wgpu <-> MAX bridge.

Requires GPU hardware AND the opt-in `max` dependency. Run via:
    pixi run -e maxinterop test-max-interop

This test is not in `pixi run test` or `check-compile` on purpose: the default
environment has no `max`, so it would not even compile there.
"""

from std.sys import has_accelerator
from std.testing import assert_equal, assert_true
from max.gpu.host import DeviceContext

from wgpu.device import Device
from wgpu.buffer import Buffer
from wgpu.instance import Instance
from wgpu._ffi.types import WGPUBufferUsage
from wgpu_max import (
    device_buffer_to_list,
    list_to_device_buffer,
    wgpu_to_device_buffer,
    wgpu_storage_to_device_buffer,
    device_buffer_to_wgpu,
)

comptime dtype = DType.float32
comptime N = 64
comptime BUF_BYTES = N * 4


def create_test_device() raises -> Device:
    var instance = Instance()
    var adapter = instance.request_adapter()
    return adapter.request_device()


def ramp(n: Int, scale: Float32) -> List[Scalar[dtype]]:
    var out = List[Scalar[dtype]](capacity=n)
    for i in range(n):
        out.append(Scalar[dtype](Float32(i) * scale))
    return out^


def test_max_host_round_trip() raises:
    """list -> MAX device buffer -> list preserves every element."""
    var ctx = DeviceContext()
    var dev = ctx.enqueue_create_buffer[dtype](N)
    var src = ramp(N, 1.5)

    list_to_device_buffer[dtype](ctx, src, dev)
    var back = device_buffer_to_list[dtype](ctx, dev, N)

    assert_equal(len(back), N)
    for i in range(N):
        assert_equal(back[i], src[i])


def storage_buffer(device: Device, label: String) raises -> Buffer:
    """A COPY_DST|COPY_SRC buffer -- the shape real compute work uses."""
    return device.create_buffer(
        UInt64(BUF_BYTES),
        WGPUBufferUsage.COPY_DST | WGPUBufferUsage.COPY_SRC,
        False,
        label,
    )


def drain_wgpu(device: Device, src: Buffer) raises -> List[Scalar[dtype]]:
    """Stage a non-mappable wgpu buffer down to the host and read it.

    Mirrors tests/test_buffer.mojo: the submit is what flushes pending queue
    writes, so this must not be replaced with a bare map_read.
    """
    var staging = device.create_buffer(
        UInt64(BUF_BYTES),
        WGPUBufferUsage.MAP_READ | WGPUBufferUsage.COPY_DST,
        False,
        "assert_staging",
    )
    var enc = device.create_command_encoder("assert_enc")
    enc.copy_buffer_to_buffer(src, UInt64(0), staging, UInt64(0), UInt64(BUF_BYTES))
    var cmd = enc^.finish()
    device.queue_submit(cmd)
    _ = device.poll(True)
    return staging.read_data[Scalar[dtype]]()


def test_max_to_wgpu() raises:
    """MAX device buffer -> wgpu buffer, verified by wgpu-side readback."""
    var ctx = DeviceContext()
    var device = create_test_device()

    var dev = ctx.enqueue_create_buffer[dtype](N)
    var src = ramp(N, 2.0)
    list_to_device_buffer[dtype](ctx, src, dev)

    var wbuf = storage_buffer(device, "max_to_wgpu")
    device_buffer_to_wgpu[dtype](ctx, dev, N, device, wbuf)

    var got = drain_wgpu(device, wbuf)
    for i in range(N):
        assert_equal(got[i], src[i])
    _ = device^


def test_wgpu_to_max() raises:
    """wgpu storage buffer -> MAX device buffer, verified by reading MAX back."""
    var ctx = DeviceContext()
    var device = create_test_device()

    var src = ramp(N, 3.0)
    var wbuf = storage_buffer(device, "wgpu_to_max")
    device.queue_write_data(wbuf, UInt64(0), src)

    var dev = ctx.enqueue_create_buffer[dtype](N)
    wgpu_storage_to_device_buffer[dtype](ctx, device, wbuf, dev, N)

    var got = device_buffer_to_list[dtype](ctx, dev, N)
    for i in range(N):
        assert_equal(got[i], src[i])
    _ = device^


def test_wgpu_to_max_mappable_source() raises:
    """The low-level MAP_READ entry point works on an already-mappable buffer."""
    var ctx = DeviceContext()
    var device = create_test_device()

    var src = ramp(N, 0.5)
    var staged = storage_buffer(device, "mappable_src")
    device.queue_write_data(staged, UInt64(0), src)

    var mappable = device.create_buffer(
        UInt64(BUF_BYTES),
        WGPUBufferUsage.MAP_READ | WGPUBufferUsage.COPY_DST,
        False,
        "mappable",
    )
    var enc = device.create_command_encoder("stage_enc")
    enc.copy_buffer_to_buffer(staged, UInt64(0), mappable, UInt64(0), UInt64(BUF_BYTES))
    var cmd = enc^.finish()
    device.queue_submit(cmd)
    _ = device.poll(True)

    var dev = ctx.enqueue_create_buffer[dtype](N)
    wgpu_to_device_buffer[dtype](ctx, mappable, dev)

    var got = device_buffer_to_list[dtype](ctx, dev, N)
    for i in range(N):
        assert_equal(got[i], src[i])
    _ = device^


def test_bridge_is_lossless_both_ways() raises:
    """A full wgpu -> MAX -> wgpu loop returns the original values."""
    var ctx = DeviceContext()
    var device = create_test_device()

    var src = ramp(N, 0.25)
    var a = storage_buffer(device, "loop_a")
    device.queue_write_data(a, UInt64(0), src)

    var dev = ctx.enqueue_create_buffer[dtype](N)
    wgpu_storage_to_device_buffer[dtype](ctx, device, a, dev, N)

    var b = storage_buffer(device, "loop_b")
    device_buffer_to_wgpu[dtype](ctx, dev, N, device, b)

    var got = drain_wgpu(device, b)
    for i in range(N):
        assert_equal(got[i], src[i])
    _ = device^


def run_all() raises:
    test_max_host_round_trip()
    print("  PASS: MAX host round trip")
    test_max_to_wgpu()
    print("  PASS: MAX -> wgpu")
    test_wgpu_to_max()
    print("  PASS: wgpu storage -> MAX")
    test_wgpu_to_max_mappable_source()
    print("  PASS: wgpu MAP_READ -> MAX")
    test_bridge_is_lossless_both_ways()
    print("  PASS: wgpu -> MAX -> wgpu lossless")
    print("test_max_interop: ALL PASSED")


def main() raises:
    # Same `comptime if` guard as examples/max_interop.mojo: instantiating the
    # bridge for a concrete dtype pulls in MAX device code, and MAX compiles
    # that for the *building* machine's GPU -- on a GPU-less box it is a
    # compile error, not a runtime one. Guarding lets CI compile-check this
    # file; see the max-interop job in .github/workflows/ci.yml for what that
    # does and does not buy.
    comptime if not has_accelerator():
        print("test_max_interop: SKIPPED (no GPU accelerator)")
    else:
        run_all()
