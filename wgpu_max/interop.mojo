"""Data bridge between wgpu-mojo buffers and MAX `DeviceBuffer`s.

Why this lives outside the `wgpu` package
-----------------------------------------
Mojo's own GPU stack is split across two conda packages. Kernel-side indexing
(`std.gpu`: `global_idx`, `thread_idx`, `lane_id`) ships in the base `mojo`
package, but *host-side dispatch* — `DeviceContext`, `DeviceBuffer`,
`enqueue_function` — ships only in `max`. wgpu-mojo depends on `mojo` and
`glfw` and nothing else, and forcing `max` onto every downstream consumer to
serve an optional bridge is a bad trade. So the bridge is a separate top-level
package: `mojo precompile wgpu` does not compile it, the published package does
not declare `max`, and only users who ask for it pay for it.

What the bridge can and cannot do
---------------------------------
Every transfer here goes **through host memory**. There is no zero-copy path:
sharing GPU allocations between the two stacks would require importing an
external-memory handle (`VK_KHR_external_memory_fd` and friends), and
wgpu-native exposes no API to obtain or import one. Both stacks may well be
driving the same physical device, but each owns its allocations privately.

Budget accordingly — a round trip costs two host copies plus a queue
synchronisation, so bridge once at a stage boundary rather than per frame.

Direction summary
-----------------
    wgpu -> MAX   `wgpu_to_device_buffer`          source needs MAP_READ
    wgpu -> MAX   `wgpu_storage_to_device_buffer`  source needs COPY_SRC
    MAX  -> wgpu  `device_buffer_to_wgpu`          destination needs COPY_DST

Prefer `wgpu_storage_to_device_buffer` for compute output: storage buffers are
not mappable, so the data has to pass through a MAP_READ staging buffer and a
submitted copy first, and that helper does it for you.
"""

from std.sys import size_of

from max.gpu.host import DeviceContext, DeviceBuffer

from wgpu import Buffer, Device
from wgpu._ffi.types import WGPUBufferUsage


def device_buffer_to_list[
    dtype: DType
](ctx: DeviceContext, src: DeviceBuffer[dtype], count: Int) raises -> List[Scalar[dtype]]:
    """Copy `count` elements out of a MAX device buffer into a Mojo list.

    Synchronises `ctx` before reading — the copy is enqueued, not immediate.
    """
    var host = ctx.enqueue_create_host_buffer[dtype](count)
    ctx.enqueue_copy(dst_buf=host, src_buf=src)
    ctx.synchronize()

    var out = List[Scalar[dtype]](capacity=count)
    for i in range(count):
        out.append(host[i])
    return out^


def list_to_device_buffer[
    dtype: DType
](ctx: DeviceContext, data: List[Scalar[dtype]], dst: DeviceBuffer[dtype]) raises:
    """Copy a Mojo list into an existing MAX device buffer.

    `dst` must already hold at least `len(data)` elements.
    """
    var host = ctx.enqueue_create_host_buffer[dtype](len(data))
    ctx.synchronize()
    for i in range(len(data)):
        host[i] = data[i]
    ctx.enqueue_copy(dst_buf=dst, src_buf=host)
    ctx.synchronize()


def wgpu_to_device_buffer[
    dtype: DType
](ctx: DeviceContext, src: Buffer, dst: DeviceBuffer[dtype]) raises:
    """Copy a wgpu buffer's contents into a MAX device buffer.

    `src` must have been created with `WGPUBufferUsage.MAP_READ`; it is mapped
    and unmapped internally. To move a compute result out of wgpu, copy it into
    a MAP_READ staging buffer first, exactly as `examples/compute_add.mojo`
    does for its own readback.
    """
    var data = src.read_data[Scalar[dtype]]()
    list_to_device_buffer[dtype](ctx, data, dst)


def device_buffer_to_wgpu[
    dtype: DType
](
    ctx: DeviceContext,
    src: DeviceBuffer[dtype],
    count: Int,
    device: Device,
    dst: Buffer,
) raises:
    """Copy a MAX device buffer's contents into an existing wgpu buffer.

    `dst` must have been created with `WGPUBufferUsage.COPY_DST`. The write is
    queued on `device`'s queue; it lands before any subsequently submitted
    command buffer observes it.
    """
    var data = device_buffer_to_list[dtype](ctx, src, count)
    device.queue_write_data(dst, UInt64(0), data)


def wgpu_storage_to_device_buffer[
    dtype: DType
](
    ctx: DeviceContext,
    device: Device,
    src: Buffer,
    dst: DeviceBuffer[dtype],
    count: Int,
) raises:
    """Copy a non-mappable wgpu buffer into a MAX device buffer.

    Storage buffers -- where compute results actually land -- cannot be mapped,
    so this stages through a MAP_READ buffer: allocate staging, record a
    buffer-to-buffer copy, submit, wait, then bridge. `src` must have been
    created with `WGPUBufferUsage.COPY_SRC`.

    Submitting is also what flushes any pending `queue_write_data` on this
    device, so a value written just before this call is included.
    """
    var byte_count = UInt64(count * size_of[Scalar[dtype]]())

    var staging = device.create_buffer(
        byte_count,
        WGPUBufferUsage.MAP_READ | WGPUBufferUsage.COPY_DST,
        False,
        "wgpu_max_staging",
    )

    var enc = device.create_command_encoder("wgpu_max_bridge")
    enc.copy_buffer_to_buffer(src, UInt64(0), staging, UInt64(0), byte_count)
    var cmd = enc^.finish("wgpu_max_bridge_cmd")
    device.queue_submit(cmd)
    _ = device.poll(True)

    wgpu_to_device_buffer[dtype](ctx, staging, dst)
