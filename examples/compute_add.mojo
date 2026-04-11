"""
examples/compute_add.mojo — GPU vector addition using high-level wgpu RAII wrappers.

Demonstrates:
  1. Instance + Device creation via request_adapter()
  2. RAII Buffer, ShaderModule, Pipeline, CommandEncoder wrappers
  3. Typed buffer upload via queue_write_buffer
  4. Compute shader dispatch
  5. Buffer readback via Buffer.map_read()

Run from project root:
    pixi run example-compute
"""

from wgpu import (
    request_adapter,
    OpaquePtr,
    WGPUBufferUsage, WGPUShaderStage, WGPU_WHOLE_SIZE,
    WGPUBufferBindingType,
    WGPUBindGroupLayoutEntry, WGPUBindGroupLayoutDescriptor,
    WGPUBufferBindingLayout, WGPUSamplerBindingLayout,
    WGPUTextureBindingLayout, WGPUStorageTextureBindingLayout,
    WGPUBindGroupEntry, WGPUBindGroupDescriptor,
    WGPUComputeState, WGPUComputePipelineDescriptor,
    WGPUConstantEntry, WGPUStringView, str_to_sv,
)


comptime SHADER_SRC = """
@group(0) @binding(0) var<storage, read>       a : array<f32>;
@group(0) @binding(1) var<storage, read>       b : array<f32>;
@group(0) @binding(2) var<storage, read_write> c : array<f32>;

@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let i = gid.x;
    if i < arrayLength(&a) {
        c[i] = a[i] + b[i];
    }
}
"""

comptime N = 1024
comptime BUF_BYTES = N * 4  # float32 = 4 bytes


def make_data(n: Int, start: Float32, stride: Float32) -> List[Float32]:
    var data = List[Float32](capacity=n)
    for i in range(n):
        data.append(start + Float32(i) * stride)
    return data^


def make_storage_entry(binding: UInt32, readonly: Bool) -> WGPUBindGroupLayoutEntry:
    var buf_type = WGPUBufferBindingType.ReadOnlyStorage if readonly else WGPUBufferBindingType.Storage
    return WGPUBindGroupLayoutEntry(
        OpaquePtr(), binding, WGPUShaderStage.COMPUTE.value, UInt32(0),
        WGPUBufferBindingLayout(OpaquePtr(), buf_type, UInt32(0), UInt64(0)),
        WGPUSamplerBindingLayout(OpaquePtr(), UInt32(0)),
        WGPUTextureBindingLayout(OpaquePtr(), UInt32(0), UInt32(0), UInt32(0)),
        WGPUStorageTextureBindingLayout(OpaquePtr(), UInt32(0), UInt32(0), UInt32(0)),
    )


def main() raises:
    print("=== wgpu-mojo: GPU Vector Addition ===")
    print("N =", N)

    # ----------------------------------------------------------------
    # 1. Instance + Device (high-level)
    # ----------------------------------------------------------------
    var instance = request_adapter()
    var device = instance.request_device()
    print("Device and queue ready.")

    # ----------------------------------------------------------------
    # 2. Shader (RAII)
    # ----------------------------------------------------------------
    var shader = device.create_shader_module_wgsl(SHADER_SRC, "vec_add")
    print("Shader compiled.")

    # ----------------------------------------------------------------
    # 3. Bind group layout
    # ----------------------------------------------------------------
    var entries_p = alloc[WGPUBindGroupLayoutEntry](3)
    entries_p[0] = make_storage_entry(UInt32(0), True)   # a: read
    entries_p[1] = make_storage_entry(UInt32(1), True)   # b: read
    entries_p[2] = make_storage_entry(UInt32(2), False)  # c: read_write
    var bgl_desc = WGPUBindGroupLayoutDescriptor(
        OpaquePtr(), WGPUStringView.null_view(), UInt(3), entries_p
    )
    var bgl = device.create_bind_group_layout(bgl_desc)
    entries_p.free()

    # ----------------------------------------------------------------
    # 4. Pipeline layout (RAII)
    # ----------------------------------------------------------------
    var bgls: List[OpaquePtr] = [bgl.handle()]
    var pl = device.create_pipeline_layout(bgls, "compute_pl")

    # ----------------------------------------------------------------
    # 5. Compute pipeline (RAII)
    # ----------------------------------------------------------------
    var entry_str = String("main")
    var entry_sv = str_to_sv(entry_str)
    var cs = WGPUComputeState(
        OpaquePtr(), shader.handle(), entry_sv, UInt(0),
        UnsafePointer[WGPUConstantEntry, MutExternalOrigin](),
    )
    var pipe_desc = WGPUComputePipelineDescriptor(
        OpaquePtr(), WGPUStringView.null_view(), pl.handle(), cs,
    )
    var pipeline = device.create_compute_pipeline(pipe_desc)
    _ = pl^       # prevent ASAP destruction before create_compute_pipeline
    _ = shader^   # prevent ASAP destruction before create_compute_pipeline
    _ = entry_str
    print("Compute pipeline created.")

    # ----------------------------------------------------------------
    # 6. Buffers (RAII)
    # ----------------------------------------------------------------
    var a_data = make_data(N, 0.0, 1.0)   # [0, 1, 2, ..., N-1]
    var b_data = make_data(N, 0.0, 2.0)   # [0, 2, 4, ..., 2*(N-1)]

    var buf_a = device.create_buffer(
        UInt64(BUF_BYTES), WGPUBufferUsage.STORAGE | WGPUBufferUsage.COPY_DST, label="buf_a")
    var buf_b = device.create_buffer(
        UInt64(BUF_BYTES), WGPUBufferUsage.STORAGE | WGPUBufferUsage.COPY_DST, label="buf_b")
    var buf_c = device.create_buffer(
        UInt64(BUF_BYTES), WGPUBufferUsage.STORAGE | WGPUBufferUsage.COPY_SRC, label="buf_c")
    var buf_r = device.create_buffer(
        UInt64(BUF_BYTES), WGPUBufferUsage.MAP_READ | WGPUBufferUsage.COPY_DST, label="buf_r")

    device.queue_write_buffer(
        buf_a.handle(), UInt64(0),
        rebind[UnsafePointer[Float32, MutExternalOrigin]](a_data.unsafe_ptr()),
        UInt(BUF_BYTES))
    _ = a_data^  # prevent ASAP destruction during queue_write_buffer
    device.queue_write_buffer(
        buf_b.handle(), UInt64(0),
        rebind[UnsafePointer[Float32, MutExternalOrigin]](b_data.unsafe_ptr()),
        UInt(BUF_BYTES))
    _ = b_data^  # prevent ASAP destruction during queue_write_buffer
    print("Data uploaded.")

    # ----------------------------------------------------------------
    # 7. Bind group (RAII)
    # ----------------------------------------------------------------
    var bg_entries_p = alloc[WGPUBindGroupEntry](3)
    bg_entries_p[0] = WGPUBindGroupEntry(
        OpaquePtr(), UInt32(0), buf_a.handle(), UInt64(0), WGPU_WHOLE_SIZE, OpaquePtr(), OpaquePtr())
    bg_entries_p[1] = WGPUBindGroupEntry(
        OpaquePtr(), UInt32(1), buf_b.handle(), UInt64(0), WGPU_WHOLE_SIZE, OpaquePtr(), OpaquePtr())
    bg_entries_p[2] = WGPUBindGroupEntry(
        OpaquePtr(), UInt32(2), buf_c.handle(), UInt64(0), WGPU_WHOLE_SIZE, OpaquePtr(), OpaquePtr())
    var bg_desc = WGPUBindGroupDescriptor(
        OpaquePtr(), WGPUStringView.null_view(), bgl.handle(), UInt(3), bg_entries_p,
    )
    var bg = device.create_bind_group(bg_desc)
    bg_entries_p.free()

    # ----------------------------------------------------------------
    # 8. Record and submit
    # ----------------------------------------------------------------
    var enc = device.create_command_encoder("compute_enc")
    var cpass = enc.begin_compute_pass("add_pass")
    cpass.set_pipeline(pipeline.handle())
    cpass.set_bind_group(UInt32(0), bg.handle())
    var workgroups = UInt32((N + 63) // 64)  # ceil(N / 64)
    cpass.dispatch_workgroups(workgroups)
    cpass.end()

    # Copy result to readback buffer
    enc.copy_buffer_to_buffer(
        buf_c.handle(), UInt64(0), buf_r.handle(), UInt64(0), UInt64(BUF_BYTES))

    var cmd_buf = enc.finish("compute_cmd")
    var cmds: List[OpaquePtr] = [cmd_buf]
    device.queue_submit(cmds)
    print("Commands submitted.")

    # Pin GPU resource lifetimes past queue_submit — Mojo's ASAP destruction
    # would otherwise release wgpu handles before the GPU finishes with them.
    _ = pipeline^
    _ = bg^
    _ = bgl^
    _ = buf_a^
    _ = buf_b^
    _ = buf_c^

    # ----------------------------------------------------------------
    # 9. Readback
    # ----------------------------------------------------------------
    var raw    = buf_r.map_read()
    var result = raw.bitcast[Float32]()
    print("Result[0]:", result[0], "expected:", Float32(0.0))
    print("Result[1]:", result[1], "expected:", Float32(3.0))
    print("Result[N-1]:", result[N - 1], "expected:", Float32(Float32(N - 1) * Float32(3.0)))

    # Validate
    var ok = True
    for i in range(N):
        var expected = Float32(i) * Float32(3.0)
        if result[i] != expected:
            print("MISMATCH at", i, "got", result[i], "expected", expected)
            ok = False
            break
    if ok:
        print("✓ All", N, "elements match!")
    else:
        raise Error("Vector add result mismatch")

    buf_r.unmap()

    # Pin remaining GPU object lifetimes past all usage.
    # Without these, Mojo's ASAP destruction releases wgpu handles too early.
    _ = device^
    _ = instance^
    print("=== Done ===")
