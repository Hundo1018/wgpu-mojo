"""
GPU tests for the wgpu-native v29.0.1.1 ABI changes.

  * set_immediates  — v29.0.1.1 moved wgpu*SetImmediates into webgpu.h and
    swapped its last two parameters to (offset, data, size). A binding still
    passing (offset, size, data) links, resolves and passes check-signatures'
    arity check; only a round trip through a shader proves the order.
  * clear_texture   — wgpuCommandEncoderClearTexture, new in v29.0.1.1.
  * create_shader_module_wgsl_trusted — wgpuDeviceCreateShaderModuleTrusted,
    new in v29.0.1.1.

Requires GPU hardware.
"""

from std.testing import assert_equal
from wgpu._ffi.nulls import null_opaque
from wgpu.device import Device
from wgpu.instance import Instance
from wgpu._ffi.types import (
    WGPUBufferUsage, WGPUShaderStage, WGPUTextureUsage, WGPUTextureFormat,
    WGPU_WHOLE_SIZE,
)
from wgpu._ffi.structs import (
    WGPUBindGroupLayoutEntry,
    WGPUBufferBindingLayout, WGPUSamplerBindingLayout,
    WGPUTextureBindingLayout, WGPUStorageTextureBindingLayout,
    WGPUBindGroupEntry, WGPUOrigin3D,
)
from wgpu._backend.wgpu_native.structs import wgpu_limits_default
from wgpu._native import WGPUNativeFeature, WGPUShaderRuntimeChecks


comptime IMMEDIATE_WGSL = """
var<immediate> k: vec2<u32>;
@group(0) @binding(0) var<storage, read_write> out: array<u32>;

@compute @workgroup_size(1)
fn main() {
    out[0] = k.x;
    out[1] = k.y;
}
"""

comptime CONST_WGSL = """
@group(0) @binding(0) var<storage, read_write> out: array<u32>;

@compute @workgroup_size(1)
fn main() {
    out[0] = 0xC0FFEEu;
    out[1] = 0xBEEFu;
}
"""

comptime OUT_SIZE: UInt64 = 8


def _storage_entry() -> WGPUBindGroupLayoutEntry:
    return WGPUBindGroupLayoutEntry(
        null_opaque(), UInt32(0),
        WGPUShaderStage.COMPUTE.value, UInt32(0),
        WGPUBufferBindingLayout(null_opaque(), UInt32(3), UInt32(0), UInt64(0)),  # Storage
        WGPUSamplerBindingLayout(null_opaque(), UInt32(0)),
        WGPUTextureBindingLayout(null_opaque(), UInt32(0), UInt32(0), UInt32(0)),
        WGPUStorageTextureBindingLayout(null_opaque(), UInt32(0), UInt32(0), UInt32(0)),
    )


def _run_and_read(
    mut device: Device, wgsl: String, immediate_size: UInt32,
    imm0: UInt32, imm1: UInt32, trusted: Bool,
) raises -> List[UInt32]:
    """Dispatch a 1-invocation shader writing two u32s; return them."""
    var shader = device.create_shader_module_wgsl_trusted(
        wgsl, WGPUShaderRuntimeChecks.ALL, "trusted"
    ) if trusted else device.create_shader_module_wgsl(wgsl, "plain")
    var bgl_entries: List[WGPUBindGroupLayoutEntry] = [_storage_entry()]
    var bgl = device.create_bind_group_layout(bgl_entries)
    var pl = device.create_pipeline_layout(bgl, "pl", immediate_size)
    var pipeline = device.create_compute_pipeline(shader, "main", pl)

    var out = device.create_buffer(OUT_SIZE, WGPUBufferUsage.STORAGE | WGPUBufferUsage.COPY_SRC, False, "out")
    var rb = device.create_buffer(OUT_SIZE, WGPUBufferUsage.MAP_READ | WGPUBufferUsage.COPY_DST, False, "rb")
    var bg_entries: List[WGPUBindGroupEntry] = [
        WGPUBindGroupEntry(null_opaque(), UInt32(0), out.handle().raw, UInt64(0), WGPU_WHOLE_SIZE, null_opaque(), null_opaque())
    ]
    var bg = device.create_bind_group(bgl, bg_entries)

    var enc = device.create_command_encoder("enc")
    var cpass = enc.begin_compute_pass()
    cpass.set_pipeline(pipeline)
    cpass.set_bind_group(UInt32(0), bg)
    if immediate_size > 0:
        var data: List[UInt32] = [imm0, imm1]
        cpass.set_immediates(
            UInt32(0), UInt32(8),
            rebind[OpaquePointer[MutUntrackedOrigin]](data.unsafe_ptr()),
        )
        _ = data^
    cpass.dispatch_workgroups(UInt32(1), UInt32(1), UInt32(1))
    cpass^.end()
    enc.copy_buffer_to_buffer(out, UInt64(0), rb, UInt64(0), OUT_SIZE)
    device.queue_submit(enc^.finish())

    var p = rb.map_read(UInt64(0), OUT_SIZE).unsafe_bitcast[UInt32]()
    var result: List[UInt32] = [p[unsafe_offset=0], p[unsafe_offset=1]]
    rb.unmap()
    _ = bgl^
    _ = out^
    return result^


def test_set_immediates_round_trip() raises:
    var instance = Instance()
    var adapter = instance.request_adapter()
    var limits = wgpu_limits_default()
    limits.max_immediate_size = 16
    var device = adapter.request_device(
        "immediates", [WGPUNativeFeature.Immediates], limits
    )
    # Two distinct values: a swapped (size, data) pair would hand the driver
    # size=<pointer> and data=8, which wgpu rejects or reads garbage from —
    # it cannot reproduce both values.
    var r = _run_and_read(device, IMMEDIATE_WGSL, UInt32(8), UInt32(0x12345678), UInt32(0x9ABC), False)
    assert_equal(r[0], UInt32(0x12345678))
    assert_equal(r[1], UInt32(0x9ABC))
    _ = device^


def test_create_shader_module_trusted() raises:
    var instance = Instance()
    var adapter = instance.request_adapter()
    var device = adapter.request_device()
    var r = _run_and_read(device, CONST_WGSL, UInt32(0), UInt32(0), UInt32(0), True)
    assert_equal(r[0], UInt32(0xC0FFEE))
    assert_equal(r[1], UInt32(0xBEEF))
    _ = device^


def test_clear_texture() raises:
    var instance = Instance()
    var adapter = instance.request_adapter()
    var device = adapter.request_device("clear", [WGPUNativeFeature.ClearTexture])

    # 64 x R32Uint = 256 bytes per row, the copy alignment.
    comptime W: UInt32 = 64
    var tex = device.create_texture(
        W, UInt32(1), UInt32(1), WGPUTextureFormat.R32Uint,
        WGPUTextureUsage.COPY_SRC | WGPUTextureUsage.COPY_DST,
    )
    var bytes = List[UInt8](capacity=Int(W) * 4)
    for _ in range(Int(W) * 4):
        bytes.append(UInt8(0xAB))
    var origin = WGPUOrigin3D(UInt32(0), UInt32(0), UInt32(0))
    device.queue_write_texture(tex, UInt32(0), origin, UInt32(0), bytes, W * 4, UInt32(1), W, UInt32(1), UInt32(1))

    var rb = device.create_buffer(UInt64(W) * 4, WGPUBufferUsage.MAP_READ | WGPUBufferUsage.COPY_DST, False, "rb")

    # Control: without the clear, the readback is the written pattern. This
    # rules out a readback that is all-zero for an unrelated reason.
    var enc0 = device.create_command_encoder("control")
    enc0.copy_texture_to_buffer(tex, rb, UInt64(0), W * 4, UInt32(1), W, UInt32(1))
    device.queue_submit(enc0^.finish())
    var p0 = rb.map_read(UInt64(0), UInt64(W) * 4).unsafe_bitcast[UInt32]()
    assert_equal(p0[unsafe_offset=0], UInt32(0xABABABAB))
    rb.unmap()

    var enc = device.create_command_encoder("clear")
    enc.clear_texture(tex)
    enc.copy_texture_to_buffer(tex, rb, UInt64(0), W * 4, UInt32(1), W, UInt32(1))
    device.queue_submit(enc^.finish())
    var p = rb.map_read(UInt64(0), UInt64(W) * 4).unsafe_bitcast[UInt32]()
    for i in range(Int(W)):
        assert_equal(p[unsafe_offset=i], UInt32(0))
    rb.unmap()
    _ = tex^
    _ = device^


def main() raises:
    test_set_immediates_round_trip()
    print("  PASS: test_set_immediates_round_trip")
    test_create_shader_module_trusted()
    print("  PASS: test_create_shader_module_trusted")
    test_clear_texture()
    print("  PASS: test_clear_texture")
    print("test_native_v29_0_1: ALL PASSED")
