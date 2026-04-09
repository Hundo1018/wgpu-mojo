"""
examples/compute_add.mojo — GPU vector addition via pure Mojo wgpu-native bindings.

Demonstrates:
  1. Instance + Adapter creation (synchronous)
  2. Device + Queue creation (callback-based, blocking)
  3. Buffer upload via queue.write_buffer
  4. Compute shader dispatch
  5. Buffer readback via buffer.map_async (blocking)

Run from project root:
    pixi run example-compute
"""

from wgpu._ffi.lib import WGPULib
from wgpu._ffi.types import (
    OpaquePtr, WGPUBufferUsage, WGPUShaderStage,
    WGPUMapAsyncStatus,
)
from wgpu._ffi.structs import (
    WGPUInstanceDescriptor,
    WGPUDeviceDescriptor, WGPUQueueDescriptor,
    WGPUDeviceLostCallbackInfo, WGPUUncapturedErrorCallbackInfo,
    WGPULimits, WGPUStringView, str_to_sv,
    WGPUBindGroupLayoutEntry, WGPUBindGroupLayoutDescriptor,
    WGPUBufferBindingLayout, WGPUSamplerBindingLayout,
    WGPUTextureBindingLayout, WGPUStorageTextureBindingLayout,
    WGPUBindGroupEntry, WGPUBindGroupDescriptor,
    WGPUPipelineLayoutDescriptor,
    WGPUComputeState, WGPUComputePipelineDescriptor,
    WGPUConstantEntry,
    WGPUCommandBufferDescriptor,
    WGPUComputePassDescriptor,
)
from wgpu._ffi.types import WGPU_WHOLE_SIZE


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
    return data


def make_storage_entry(binding: UInt32, readonly: Bool) -> WGPUBindGroupLayoutEntry:
    var buf_type: UInt32 = 3 if readonly else 2
    return WGPUBindGroupLayoutEntry(
        OpaquePtr(), binding, WGPUShaderStage.Compute.value, UInt32(0),
        WGPUBufferBindingLayout(OpaquePtr(), buf_type, UInt32(0), UInt64(0)),
        WGPUSamplerBindingLayout(OpaquePtr(), UInt32(0)),
        WGPUTextureBindingLayout(OpaquePtr(), UInt32(0), UInt32(0), UInt32(0)),
        WGPUStorageTextureBindingLayout(OpaquePtr(), UInt32(0), UInt32(0), UInt32(0)),
    )


def main() raises:
    print("=== wgpu-mojo: GPU Vector Addition ===")
    print("N =", N)

    # ----------------------------------------------------------------
    # 1. Instance
    # ----------------------------------------------------------------
    var lib  = WGPULib()
    var desc_p = alloc[WGPUInstanceDescriptor](1)
    desc_p[] = WGPUInstanceDescriptor(
        OpaquePtr(), UInt(0),
        UnsafePointer[UInt32, MutExternalOrigin](),
        UnsafePointer[NoneType, MutExternalOrigin](),
    )
    var inst = lib.create_instance(desc_p)
    desc_p.free()
    if not inst:
        raise Error("wgpuCreateInstance failed")

    # ----------------------------------------------------------------
    # 2. Adapter (synchronous enumerate)
    # ----------------------------------------------------------------
    var n_adapters = lib.enumerate_adapters(inst, OpaquePtr(), UnsafePointer[OpaquePtr, MutExternalOrigin]())
    if n_adapters == 0:
        raise Error("No GPU adapters found")
    var adapter_arr = alloc[OpaquePtr](n_adapters)
    _ = lib.enumerate_adapters(inst, OpaquePtr(), adapter_arr)
    var adapter = adapter_arr[0]
    adapter_arr.free()
    print("Adapter selected.")

    # ----------------------------------------------------------------
    # 3. Device + Queue
    # ----------------------------------------------------------------
    var lost_cb = WGPUDeviceLostCallbackInfo(OpaquePtr(), UInt32(0), OpaquePtr(), OpaquePtr(), OpaquePtr())
    var err_cb  = WGPUUncapturedErrorCallbackInfo(OpaquePtr(), OpaquePtr(), OpaquePtr(), OpaquePtr())
    var q_desc  = WGPUQueueDescriptor(OpaquePtr(), WGPUStringView.null_view())
    var dev_desc_p = alloc[WGPUDeviceDescriptor](1)
    dev_desc_p[] = WGPUDeviceDescriptor(
        OpaquePtr(), WGPUStringView.null_view(),
        UInt(0), UnsafePointer[UInt32, MutExternalOrigin](),
        UnsafePointer[WGPULimits, MutExternalOrigin](),
        q_desc, lost_cb, err_cb,
    )
    var dev_result = lib.adapter_request_device_sync(
        inst, adapter, dev_desc_p
    )
    dev_desc_p.free()
    var device = dev_result.device
    var dev_status = dev_result.status
    if dev_status != UInt32(1):  # RequestDeviceStatus.Success
        raise Error("Device creation failed, status=" + String(dev_status))
    var queue = lib.device_get_queue(device)
    print("Device and queue ready.")

    # ----------------------------------------------------------------
    # 4. Shader
    # ----------------------------------------------------------------
    var shader = device_create_shader_wgsl(lib, device, SHADER_SRC, "vec_add")
    print("Shader compiled.")

    # ----------------------------------------------------------------
    # 5. Bind group layout
    # ----------------------------------------------------------------
    var entries = List[WGPUBindGroupLayoutEntry](
        make_storage_entry(UInt32(0), True),   # a: read
        make_storage_entry(UInt32(1), True),   # b: read
        make_storage_entry(UInt32(2), False),  # c: read_write
    )
    var bgl_desc_p = alloc[WGPUBindGroupLayoutDescriptor](1)
    bgl_desc_p[] = WGPUBindGroupLayoutDescriptor(
        OpaquePtr(), WGPUStringView.null_view(), UInt(3), entries.unsafe_ptr()
    )
    var bgl = lib.device_create_bind_group_layout(device, bgl_desc_p)
    bgl_desc_p.free()

    # ----------------------------------------------------------------
    # 6. Pipeline layout
    # ----------------------------------------------------------------
    var bgls = List[OpaquePtr](bgl)
    var pl_desc_p = alloc[WGPUPipelineLayoutDescriptor](1)
    pl_desc_p[] = WGPUPipelineLayoutDescriptor(
        OpaquePtr(), WGPUStringView.null_view(), UInt(1), bgls.unsafe_ptr(), UInt32(0)
    )
    var pl = lib.device_create_pipeline_layout(device, pl_desc_p)
    pl_desc_p.free()

    # ----------------------------------------------------------------
    # 7. Compute pipeline
    # ----------------------------------------------------------------
    var entry_sv = str_to_sv(String("main"))
    var cs = WGPUComputeState(OpaquePtr(), shader, entry_sv, UInt(0),
                              UnsafePointer[WGPUConstantEntry, MutExternalOrigin]())
    var pipe_desc_p = alloc[WGPUComputePipelineDescriptor](1)
    pipe_desc_p[] = WGPUComputePipelineDescriptor(
        OpaquePtr(), WGPUStringView.null_view(), pl, cs
    )
    var pipeline = lib.device_create_compute_pipeline(device, pipe_desc_p)
    pipe_desc_p.free()
    print("Compute pipeline created.")

    # ----------------------------------------------------------------
    # 8. Buffers
    # ----------------------------------------------------------------
    var a_data = make_data(N, 0.0, 1.0)   # [0, 1, 2, ..., N-1]
    var b_data = make_data(N, 0.0, 2.0)   # [0, 2, 4, ..., 2*(N-1)]

    var buf_a = create_buf(lib, device, UInt64(BUF_BYTES),
                           WGPUBufferUsage.Storage | WGPUBufferUsage.CopyDst, "buf_a")
    var buf_b = create_buf(lib, device, UInt64(BUF_BYTES),
                           WGPUBufferUsage.Storage | WGPUBufferUsage.CopyDst, "buf_b")
    var buf_c = create_buf(lib, device, UInt64(BUF_BYTES),
                           WGPUBufferUsage.Storage | WGPUBufferUsage.CopySrc, "buf_c")
    var buf_r = create_buf(lib, device, UInt64(BUF_BYTES),
                           WGPUBufferUsage.MapRead | WGPUBufferUsage.CopyDst, "buf_r")

    lib.queue_write_buffer(queue, buf_a, UInt64(0),
                           a_data.unsafe_ptr().bitcast[NoneType](), UInt(BUF_BYTES))
    lib.queue_write_buffer(queue, buf_b, UInt64(0),
                           b_data.unsafe_ptr().bitcast[NoneType](), UInt(BUF_BYTES))
    print("Data uploaded.")

    # ----------------------------------------------------------------
    # 9. Bind group
    # ----------------------------------------------------------------
    var bg_entries = List[WGPUBindGroupEntry](
        WGPUBindGroupEntry(OpaquePtr(), UInt32(0), buf_a, UInt64(0), WGPU_WHOLE_SIZE, OpaquePtr(), OpaquePtr()),
        WGPUBindGroupEntry(OpaquePtr(), UInt32(1), buf_b, UInt64(0), WGPU_WHOLE_SIZE, OpaquePtr(), OpaquePtr()),
        WGPUBindGroupEntry(OpaquePtr(), UInt32(2), buf_c, UInt64(0), WGPU_WHOLE_SIZE, OpaquePtr(), OpaquePtr()),
    )
    var bg_desc_p = alloc[WGPUBindGroupDescriptor](1)
    bg_desc_p[] = WGPUBindGroupDescriptor(
        OpaquePtr(), WGPUStringView.null_view(), bgl, UInt(3), bg_entries.unsafe_ptr()
    )
    var bg = lib.device_create_bind_group(device, bg_desc_p)
    bg_desc_p.free()

    # ----------------------------------------------------------------
    # 10. Record and submit
    # ----------------------------------------------------------------
    var enc_desc_null = UnsafePointer[WGPUCommandEncoderDescriptor, MutExternalOrigin]()
    var enc = lib.device_create_command_encoder(device, enc_desc_null)
    var pass_desc_p = alloc[WGPUComputePassDescriptor](1)
    pass_desc_p[] = WGPUComputePassDescriptor(OpaquePtr(), WGPUStringView.null_view(), OpaquePtr())
    var cpass = lib.command_encoder_begin_compute_pass(enc, pass_desc_p)
    pass_desc_p.free()
    lib.compute_pass_set_pipeline(cpass, pipeline)
    lib.compute_pass_set_bind_group(cpass, UInt32(0), bg, UInt(0), OpaquePtr())
    var workgroups = UInt32((N + 63) // 64)  # ceil(N / 64)
    lib.compute_pass_dispatch_workgroups(cpass, workgroups, UInt32(1), UInt32(1))
    lib.compute_pass_end(cpass)

    # Copy result to readback buffer
    lib.command_encoder_copy_buffer_to_buffer(enc, buf_c, 0, buf_r, 0, UInt64(BUF_BYTES))

    var cmd_desc_p = alloc[WGPUCommandBufferDescriptor](1)
    cmd_desc_p[] = WGPUCommandBufferDescriptor(OpaquePtr(), WGPUStringView.null_view())
    var cmd_buf  = lib.command_encoder_finish(enc, cmd_desc_p)
    cmd_desc_p.free()
    var cmds = List[OpaquePtr](cmd_buf)
    lib.queue_submit(queue, UInt(1), cmds.unsafe_ptr())
    print("Commands submitted.")

    # ----------------------------------------------------------------
    # 11. Readback
    # ----------------------------------------------------------------
    var map_status = lib.buffer_map_async(
        inst, device, buf_r, UInt64(1),  # MapMode.Read
        UInt(0), UInt(BUF_BYTES)
    )
    if map_status != UInt32(1):  # MapAsyncStatus.Success
        raise Error("Buffer map failed, status=" + String(map_status))

    var raw    = lib.buffer_get_const_mapped_range(buf_r, UInt(0), UInt(BUF_BYTES))
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

    lib.buffer_unmap(buf_r)

    # ----------------------------------------------------------------
    # 12. Cleanup
    # ----------------------------------------------------------------
    lib.bind_group_release(bg)
    lib.compute_pass_release(cpass)
    lib.command_buffer_release(cmd_buf)
    lib.command_encoder_release(enc)
    lib.compute_pipeline_release(pipeline)
    lib.pipeline_layout_release(pl)
    lib.bind_group_layout_release(bgl)
    lib.shader_module_release(shader)
    lib.buffer_release(buf_a)
    lib.buffer_release(buf_b)
    lib.buffer_release(buf_c)
    lib.buffer_release(buf_r)
    lib.queue_release(queue)
    lib.device_destroy(device)
    lib.device_release(device)
    lib.adapter_release(adapter)
    lib.instance_release(inst)
    print("=== Done ===")


# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

fn create_buf(
    lib: WGPULib,
    device: OpaquePtr,
    size: UInt64,
    usage: WGPUBufferUsage,
    label: String,
) -> OpaquePtr:
    from wgpu._ffi.structs import WGPUBufferDescriptor
    var sv     = str_to_sv(label)
    var desc_p = alloc[WGPUBufferDescriptor](1)
    desc_p[] = WGPUBufferDescriptor(OpaquePtr(), sv, usage.value, size, UInt32(0))
    var result = lib.device_create_buffer(device, desc_p)
    desc_p.free()
    return result


fn device_create_shader_wgsl(
    lib: WGPULib,
    device: OpaquePtr,
    code: String,
    label: String,
) -> OpaquePtr:
    from wgpu._ffi.structs import WGPUShaderModuleDescriptor, WGPUShaderSourceWGSL, WGPUChainedStruct
    from wgpu._ffi.types import WGPUSType
    var code_sv  = str_to_sv(code)
    var label_sv = str_to_sv(label)
    var chain_val = WGPUChainedStruct(OpaquePtr(), WGPUSType.ShaderSourceWGSL)
    var source_p  = alloc[WGPUShaderSourceWGSL](1)
    source_p[] = WGPUShaderSourceWGSL(chain_val, code_sv)
    var desc_p    = alloc[WGPUShaderModuleDescriptor](1)
    desc_p[] = WGPUShaderModuleDescriptor(source_p.bitcast[NoneType](), label_sv)
    var result = lib.device_create_shader_module(device, desc_p)
    source_p.free()
    desc_p.free()
    return result
