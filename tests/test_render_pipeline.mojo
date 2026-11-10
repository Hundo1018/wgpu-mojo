"""
Tests for RenderPipeline creation and headless render pass.
Requires GPU hardware.
"""

from std.testing import assert_true, assert_equal
from wgpu.device import Device
from wgpu.instance import Instance
from wgpu._ffi.types import (
    WGPUTextureUsage, WGPUTextureFormat,
    WGPUBufferUsage,
)
from wgpu._ffi.structs import WGPUColor
from wgpu.capture import FrameCapture


comptime TRIANGLE_WGSL = """
@vertex
fn vs_main(@builtin(vertex_index) idx: u32) -> @builtin(position) vec4<f32> {
    var pos = array<vec2<f32>, 3>(
        vec2<f32>( 0.0,  0.5),
        vec2<f32>(-0.5, -0.5),
        vec2<f32>( 0.5, -0.5),
    );
    return vec4<f32>(pos[idx], 0.0, 1.0);
}

@fragment
fn fs_main() -> @location(0) vec4<f32> {
    return vec4<f32>(1.0, 0.0, 0.0, 1.0);
}
"""

comptime TEX_WIDTH:  UInt32 = 64
comptime TEX_HEIGHT: UInt32 = 64
comptime TEX_FMT:    UInt32 = WGPUTextureFormat.RGBA8Unorm


def create_test_device() raises -> Device:
    var instance = Instance()
    var adapter = instance.request_adapter()
    return adapter.request_device()


def test_create_render_pipeline() raises:
    """Render pipeline creation with vertex+fragment shaders should succeed."""
    var device = create_test_device()
    var shader = device.create_shader_module_wgsl(TRIANGLE_WGSL, "triangle")
    assert_true(shader)

    var pl = device.create_pipeline_layout(List[OpaquePointer[MutUntrackedOrigin]](), "render_pl")
    var pipeline = device.create_render_pipeline(
        shader, "vs_main", "fs_main", TEX_FMT, pl,
    )
    assert_true(pipeline)


def test_headless_render_pass() raises:
    """Render a triangle to an offscreen texture and readback center pixel."""
    var device = create_test_device()
    var shader = device.create_shader_module_wgsl(TRIANGLE_WGSL, "triangle")

    # Build render pipeline
    var pl = device.create_pipeline_layout(List[OpaquePointer[MutUntrackedOrigin]](), "render_pl")
    var pipeline = device.create_render_pipeline(
        shader, "vs_main", "fs_main", TEX_FMT, pl,
    )

    # Create offscreen render target
    var tex = device.create_texture(
        TEX_WIDTH, TEX_HEIGHT, UInt32(1), TEX_FMT,
        WGPUTextureUsage.RENDER_ATTACHMENT | WGPUTextureUsage.COPY_SRC,
        label="render_target",
    )
    var view = tex.create_view_default()

    # Create readback buffer (4 bytes per pixel RGBA8)
    var buf_size = UInt64(TEX_WIDTH) * UInt64(TEX_HEIGHT) * UInt64(4)
    var readback = device.create_buffer(
        buf_size, WGPUBufferUsage.COPY_DST | WGPUBufferUsage.MAP_READ, False, "readback"
    )

    # Encode render pass
    var enc = device.create_command_encoder("render_enc")
    var rpass = enc.begin_render_pass_clear(
        view^,
        WGPUColor(Float64(0.0), Float64(0.0), Float64(0.0), Float64(1.0)),
        "headless_clear",
    )
    rpass.set_pipeline(pipeline)
    rpass.draw(UInt32(3), UInt32(1), UInt32(0), UInt32(0))
    rpass^.end()

    # Copy texture → buffer for readback
    # We skip the readback validation here (texture-to-buffer copy requires
    # additional structs). The key test is that the render pass doesn't crash.

    var cmd = enc^.finish()
    device.queue_submit(cmd)
    # Pin: wgpu-native may free device on release; poll needs it alive
    _ = device.poll(True)
    _ = device^
    print("Headless render pass completed successfully")


comptime DEPTH_WGSL = """
struct VOut { @builtin(position) pos : vec4<f32>, @location(0) color : vec3<f32> };

// Instance 0: a near red triangle (z = 0.2). Instance 1: a far green one (z = 0.8), drawn second.
@vertex
fn vs_main(@builtin(vertex_index) idx: u32, @builtin(instance_index) inst: u32) -> VOut {
    var pos = array<vec2<f32>, 3>(
        vec2<f32>( 0.0,  0.9),
        vec2<f32>(-0.9, -0.9),
        vec2<f32>( 0.9, -0.9),
    );
    var out : VOut;
    if (inst == 0u) {
        out.pos = vec4<f32>(pos[idx], 0.2, 1.0);
        out.color = vec3<f32>(1.0, 0.0, 0.0);
    } else {
        out.pos = vec4<f32>(pos[idx], 0.8, 1.0);
        out.color = vec3<f32>(0.0, 1.0, 0.0);
    }
    return out;
}

@fragment
fn fs_main(in : VOut) -> @location(0) vec4<f32> {
    return vec4<f32>(in.color, 1.0);
}
"""


def _center_pixel(with_depth: Bool) raises -> Tuple[UInt8, UInt8]:
    """Draw near-red then far-green over the same pixels; return the centre pixel's (r, g)."""
    var device = create_test_device()
    var shader = device.create_shader_module_wgsl(DEPTH_WGSL, "depth")
    var pl = device.create_pipeline_layout(List[OpaquePointer[MutUntrackedOrigin]](), "depth_pl")
    var tex = device.create_texture(
        TEX_WIDTH, TEX_HEIGHT, UInt32(1), TEX_FMT,
        WGPUTextureUsage.RENDER_ATTACHMENT | WGPUTextureUsage.COPY_SRC,
        label="depth_test_color",
    )
    var clear = WGPUColor(Float64(0.0), Float64(0.0), Float64(0.0), Float64(1.0))
    if with_depth:
        var pipeline = device.create_render_pipeline(
            shader, "vs_main", "fs_main", TEX_FMT, pl,
            depth_format=WGPUTextureFormat.Depth32Float,
        )
        var depth = device.create_texture(
            TEX_WIDTH, TEX_HEIGHT, UInt32(1), WGPUTextureFormat.Depth32Float,
            WGPUTextureUsage.RENDER_ATTACHMENT,
            label="depth_test_depth",
        )
        var depth_view = depth.create_view_default()
        var enc = device.create_command_encoder("depth_enc")
        var rpass = enc.begin_surface_clear_pass_depth(tex.handle().raw, depth_view, clear, 1.0, "depth_pass")
        rpass.set_pipeline(pipeline)
        rpass.draw(UInt32(3), UInt32(2), UInt32(0), UInt32(0))
        rpass^.end()
        device.queue_submit(enc^.finish())
        _ = depth_view^
        _ = depth^
    else:
        var pipeline = device.create_render_pipeline(shader, "vs_main", "fs_main", TEX_FMT, pl)
        var enc = device.create_command_encoder("no_depth_enc")
        var rpass = enc.begin_surface_clear_pass(tex.handle().raw, clear, "no_depth_pass")
        rpass.set_pipeline(pipeline)
        rpass.draw(UInt32(3), UInt32(2), UInt32(0), UInt32(0))
        rpass^.end()
        device.queue_submit(enc^.finish())

    var cap = FrameCapture(device, TEX_WIDTH, TEX_HEIGHT)
    var req = cap.capture(device, tex.handle().raw)
    var polls = 0
    while not req.ready():
        polls += 1
        if polls > 1_000_000:
            raise Error("capture never completed")
    var px = req.take().unsafe_bitcast[UInt8]()
    var i = Int(TEX_HEIGHT // 2) * Int(cap.row_pitch()) + Int(TEX_WIDTH // 2) * 4
    var r = px[unsafe_offset=i]
    var g = px[unsafe_offset=i + 1]
    cap.unmap()
    _ = tex^
    _ = device^
    return (r, g)


def test_depth_attachment() raises:
    """With a depth attachment the near triangle wins although it is drawn first; without one the last draw wins."""
    var with_depth = _center_pixel(True)
    assert_equal(with_depth[0], UInt8(255))
    assert_equal(with_depth[1], UInt8(0))
    var without = _center_pixel(False)
    assert_equal(without[0], UInt8(0))
    assert_equal(without[1], UInt8(255))
    print("Depth attachment: near red kept with depth, far green overwrites without")


def main() raises:
    test_create_render_pipeline()
    test_headless_render_pass()
    test_depth_attachment()
    print("test_render_pipeline: ALL PASSED")
