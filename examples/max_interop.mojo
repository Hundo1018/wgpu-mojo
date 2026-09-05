"""
One pipeline, two GPU stacks.

A Mojo kernel dispatched through MAX's `DeviceContext` produces data; that data
crosses into wgpu via `wgpu_max`; a WGSL compute shader consumes it; the result
comes back and is checked on the host.

    MAX kernel        y[i] = i * 2
        |  wgpu_max.device_buffer_to_wgpu
    WGSL shader       c[i] = y[i] + 1
        |  wgpu_max.wgpu_storage_to_device_buffer
    MAX device buffer, verified as i * 2 + 1

Requires GPU hardware AND the opt-in `max` dependency:
    pixi run -e maxinterop example-max-interop

Note the two stacks do NOT share allocations -- each bridge crossing is a host
round trip. See wgpu_max/interop.mojo for why, and bridge at stage boundaries
rather than per frame.
"""

from std.math import ceildiv
from std.sys import has_accelerator
from std.gpu import global_idx
from max.gpu.host import DeviceContext
from layout import TileTensor, row_major

from wgpu._ffi.nulls import null_opaque
from wgpu import (
    Instance,
    WGPUBufferUsage, WGPUShaderStage, WGPU_WHOLE_SIZE,
    WGPUBufferBindingType,
    WGPUBindGroupLayoutEntry,
    WGPUBufferBindingLayout, WGPUSamplerBindingLayout,
    WGPUTextureBindingLayout, WGPUStorageTextureBindingLayout,
    WGPUBindGroupEntry,
)
from wgpu_max import device_buffer_to_wgpu, wgpu_storage_to_device_buffer

comptime dtype = DType.float32
comptime N = 1024
comptime BUF_BYTES = N * 4
comptime BLOCK = 256
comptime layout = row_major[N]()

comptime SHADER_SRC = """
@group(0) @binding(0) var<storage, read>       a : array<f32>;
@group(0) @binding(1) var<storage, read_write> c : array<f32>;

@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let i = gid.x;
    if i < arrayLength(&a) {
        c[i] = a[i] + 1.0;
    }
}
"""


def ramp_kernel(
    out_t: TileTensor[dtype, type_of(layout), MutAnyOrigin],
    size: Int32,
):
    """MAX-side work: out[i] = i * 2."""
    var tid = global_idx.x
    if tid < Int(size):
        out_t[tid] = Scalar[dtype](Float32(tid) * 2.0)


def make_storage_entry(binding: UInt32, readonly: Bool) -> WGPUBindGroupLayoutEntry:
    var buf_type = WGPUBufferBindingType.ReadOnlyStorage if readonly else WGPUBufferBindingType.Storage
    return WGPUBindGroupLayoutEntry(
        null_opaque(), binding, WGPUShaderStage.COMPUTE.value, UInt32(0),
        WGPUBufferBindingLayout(null_opaque(), buf_type, UInt32(0), UInt64(0)),
        WGPUSamplerBindingLayout(null_opaque(), UInt32(0)),
        WGPUTextureBindingLayout(null_opaque(), UInt32(0), UInt32(0), UInt32(0)),
        WGPUStorageTextureBindingLayout(null_opaque(), UInt32(0), UInt32(0), UInt32(0)),
    )


def run_pipeline() raises:
    print("=== wgpu-mojo <-> MAX interop ===")
    print("N =", N)

    # ------------------------------------------------------------------
    # 1. MAX side: dispatch a Mojo kernel
    # ------------------------------------------------------------------
    var ctx = DeviceContext()
    var max_out = ctx.enqueue_create_buffer[dtype](N)
    ctx.enqueue_function[ramp_kernel](
        TileTensor(max_out, layout),
        Int32(N),
        grid_dim=ceildiv(N, BLOCK),
        block_dim=BLOCK,
    )
    ctx.synchronize()
    print("MAX kernel done      -> y[i] = i * 2")

    # ------------------------------------------------------------------
    # 2. wgpu side: device + compute pipeline
    # ------------------------------------------------------------------
    var instance = Instance()
    var adapter = instance.request_adapter()
    var device = adapter.request_device()

    var shader = device.create_shader_module_wgsl(SHADER_SRC, "add_one")
    var bgl_entries: List[WGPUBindGroupLayoutEntry] = [
        make_storage_entry(UInt32(0), True),
        make_storage_entry(UInt32(1), False),
    ]
    var bgl = device.create_bind_group_layout(bgl_entries)
    var pl = device.create_pipeline_layout(bgl, "interop_pl")
    var pipeline = device.create_compute_pipeline(shader, "main", pl)

    var buf_a = device.create_buffer(
        UInt64(BUF_BYTES),
        WGPUBufferUsage.STORAGE | WGPUBufferUsage.COPY_DST,
        label="from_max")
    var buf_c = device.create_buffer(
        UInt64(BUF_BYTES),
        WGPUBufferUsage.STORAGE | WGPUBufferUsage.COPY_SRC,
        label="to_max")

    # ------------------------------------------------------------------
    # 3. Bridge MAX -> wgpu
    # ------------------------------------------------------------------
    device_buffer_to_wgpu[dtype](ctx, max_out, N, device, buf_a)
    print("bridged MAX -> wgpu")

    # ------------------------------------------------------------------
    # 4. Dispatch the WGSL shader
    # ------------------------------------------------------------------
    var bg_entries: List[WGPUBindGroupEntry] = [
        WGPUBindGroupEntry(
            null_opaque(), UInt32(0), buf_a.handle().raw, UInt64(0),
            WGPU_WHOLE_SIZE, null_opaque(), null_opaque()),
        WGPUBindGroupEntry(
            null_opaque(), UInt32(1), buf_c.handle().raw, UInt64(0),
            WGPU_WHOLE_SIZE, null_opaque(), null_opaque()),
    ]
    var bg = device.create_bind_group(bgl, bg_entries)

    var enc = device.create_command_encoder("interop_enc")
    var cpass = enc.begin_compute_pass("add_one_pass")
    cpass.set_pipeline(pipeline)
    cpass.set_bind_group(UInt32(0), bg)
    cpass.dispatch_workgroups(UInt32((N + 63) // 64))
    cpass^.end()
    var cmd = enc^.finish("interop_cmd")
    device.queue_submit(cmd)
    _ = device.poll(True)
    print("WGSL shader done     -> c[i] = y[i] + 1")

    # Pin wgpu resources past queue_submit (Mojo's ASAP drop would release the
    # handles the in-flight command buffer still needs).
    _ = pipeline^
    _ = bg^
    _ = bgl^

    # ------------------------------------------------------------------
    # 5. Bridge wgpu -> MAX and verify
    # ------------------------------------------------------------------
    var max_back = ctx.enqueue_create_buffer[dtype](N)
    wgpu_storage_to_device_buffer[dtype](ctx, device, buf_c, max_back, N)
    print("bridged wgpu -> MAX")

    var ok = True
    with max_back.map_to_host() as host:
        for i in range(N):
            var expected = Scalar[dtype](Float32(i) * 2.0 + 1.0)
            if host[i] != expected:
                print("MISMATCH at", i, "got", host[i], "expected", expected)
                ok = False
                break
        print("result[0] =", host[0], " result[N-1] =", host[N - 1])

    _ = buf_a^
    _ = buf_c^
    _ = device^

    if not ok:
        raise Error("interop pipeline result mismatch")
    print("OK: all", N, "elements match i * 2 + 1")
    print("=== Done ===")


def main() raises:
    # `comptime if`, not `comptime assert`: MAX compiles kernels for the GPU
    # present on the *building* machine, so an unguarded kernel launch is a
    # compile error on a GPU-less box. Guarding it here elides the whole GPU
    # path at compile time, which is what lets CI compile-check this file on a
    # runner with no accelerator.
    comptime if not has_accelerator():
        print("No GPU accelerator found - this example requires one.")
    else:
        run_pipeline()
