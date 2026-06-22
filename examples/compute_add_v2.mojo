"""
compute_add_v2.mojo — GPU vector addition using the new Layer 3 API.

Compare with examples/compute_add.mojo (old API):
- No `_ = resource^` lifetime pins
- No manual BindGroup / PipelineLayout / CommandEncoder setup
- No raw pointer access in user code
- Result type: List[Float32] directly from gpu.read[Float32]()

Run with:
    pixi run mojo run -I . examples/compute_add_v2.mojo
"""

from wgpu.gpu import GPU
from wgpu._ffi.types import WGPUBufferUsage

comptime N = 1024
comptime WORKGROUP_SIZE = 64


comptime ADD_WGSL = """
@group(0) @binding(0) var<storage, read>       buf_a : array<f32>;
@group(0) @binding(1) var<storage, read>       buf_b : array<f32>;
@group(0) @binding(2) var<storage, read_write> buf_c : array<f32>;

@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) gid : vec3<u32>) {
    let i = gid.x;
    if (i < arrayLength(&buf_a)) {
        buf_c[i] = buf_a[i] + buf_b[i];
    }
}
"""


def main() raises:
    print("=== compute_add_v2: vector addition via GPU facade ===")

    var gpu = GPU.wgpu()
    print("GPU initialized")

    # Allocate buffers
    var buf_a = gpu.buffer[Float32](
        N,
        WGPUBufferUsage.STORAGE | WGPUBufferUsage.COPY_DST,
        "buf_a",
    )
    var buf_b = gpu.buffer[Float32](
        N,
        WGPUBufferUsage.STORAGE | WGPUBufferUsage.COPY_DST,
        "buf_b",
    )
    var buf_c = gpu.buffer[Float32](
        N,
        WGPUBufferUsage.STORAGE | WGPUBufferUsage.COPY_SRC,
        "buf_c",
    )

    # Upload data
    var data_a = List[Float32](capacity=N)
    var data_b = List[Float32](capacity=N)
    for i in range(N):
        data_a.append(Float32(i))
        data_b.append(Float32(i) * 2.0)

    gpu.write(buf_a, data_a)
    gpu.write(buf_b, data_b)
    print("Data uploaded")

    # Compile shader (one-time, can be reused)
    var prog = gpu.compile_compute(
        ADD_WGSL,
        entry_point="main",
        n_storage_buffers=3,
        label="vec_add",
    )
    print("Shader compiled")

    # Dispatch — no `_ = resource^` needed, Session handles lifetimes
    gpu.dispatch(prog^, [buf_a.handle(), buf_b.handle(), buf_c.handle()], N // WORKGROUP_SIZE, 1, 1, "vec_add_dispatch")
    print("Dispatch complete")

    # Read back (gpu.read() calls poll() internally)
    var result = gpu.read[Float32](buf_c)

    # Verify
    var passed = True
    for i in range(N):
        var expected = Float32(i) + Float32(i) * 2.0  # a[i] + b[i]
        if abs(result[i] - expected) > 1e-4:
            print("FAIL at index", i, ":", result[i], "!=", expected)
            passed = False
            break

    if passed:
        print("PASS: all", N, "elements match expected values")
        print("result[0] =", result[0], "(expected 0.0)")
        print("result[1] =", result[1], "(expected 3.0)")
        print("result[N-1] =", result[N - 1], "(expected", Float32((N - 1) * 3), ")")
    else:
        print("FAIL: some elements did not match")
