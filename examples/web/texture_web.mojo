"""
A sampled texture in the browser: `wgpuQueueWriteTexture`, `wgpuDeviceCreateSampler`, a 2D-array view with mip levels.

A 4x4 RGBA8 array texture with two layers and two mip levels. Each (layer, level) image has its left half in one
colour and its right half black:

    layer 0, level 0  red      layer 1, level 0  green
    layer 0, level 1  blue     layer 1, level 1  white

A full-screen triangle draws it into a 4x2 target: the left half samples layer 0 and the right half layer 1, the top
row level 0 and the bottom row level 1, at u = 1.25. A repeating sampler wraps that into the coloured half; a clamping
one would return black. The host reads the four corner pixels back without blocking and expects red, green, blue,
white.

    pixi run build-web && pixi run test-web
"""

from wgpu._ffi.nulls import null_opaque
from wgpu._backend.wgpu_native.alloc_guard import raw_alloc
from wgpu import (
    WGPUShaderStage, WGPUBindGroupLayoutEntry, WGPUBufferBindingLayout, WGPUSamplerBindingLayout,
    WGPUTextureBindingLayout, WGPUStorageTextureBindingLayout, WGPUBindGroupEntry,
)
from wgpu._ffi.types import (
    WGPUTextureUsage, WGPUTextureFormat, WGPUSamplerBindingType, WGPUTextureSampleType, WGPUTextureViewDimension,
    WGPUTextureAspect, WGPUAddressMode, WGPUFilterMode, WGPUMipmapFilterMode,
)
from wgpu._ffi.structs import WGPUColor, WGPUOrigin3D, WGPUStringView, WGPUTextureViewDescriptor
from wgpu.buffer import MapRequest
from wgpu.capture import FrameCapture
from wgpu.texture import Texture
from wgpu.web.boot import GPUBoot

comptime W: UInt32 = 4
comptime H: UInt32 = 2
comptime UNDEFINED: UInt32 = 0xFFFFFFFF

comptime SHADER = """
@group(0) @binding(0) var tex : texture_2d_array<f32>;
@group(0) @binding(1) var samp : sampler;

@vertex
fn vs_main(@builtin(vertex_index) i : u32) -> @builtin(position) vec4<f32> {
    var p = array<vec2<f32>, 3>(vec2<f32>(-1.0, -1.0), vec2<f32>(3.0, -1.0), vec2<f32>(-1.0, 3.0));
    return vec4<f32>(p[i], 0.0, 1.0);
}

@fragment
fn fs_main(@builtin(position) at : vec4<f32>) -> @location(0) vec4<f32> {
    let layer = i32(at.x >= 2.0);
    let level = f32(at.y >= 1.0);
    // u = 1.25 is outside 0..1. A repeating sampler wraps it to 0.25, the coloured left half;
    // a clamping one reads the right edge, which is black.
    return textureSampleLevel(tex, samp, vec2<f32>(1.25, 0.25), layer, level);
}
"""


def halves(r: UInt8, g: UInt8, b: UInt8, side: Int) -> List[UInt8]:
    """A `side` x `side` image: the left half in the given colour, the right half black."""
    var out = List[UInt8](capacity=side * side * 4)
    for _ in range(side):
        for x in range(side):
            var lit = x < side // 2
            out.append(r if lit else UInt8(0))
            out.append(g if lit else UInt8(0))
            out.append(b if lit else UInt8(0))
            out.append(255)
    return out^


def layout_entry(binding: UInt32, is_sampler: Bool) -> WGPUBindGroupLayoutEntry:
    return WGPUBindGroupLayoutEntry(
        null_opaque(), binding, WGPUShaderStage.FRAGMENT.value, UInt32(0),
        WGPUBufferBindingLayout(null_opaque(), UInt32(0), UInt32(0), UInt64(0)),
        WGPUSamplerBindingLayout(null_opaque(), WGPUSamplerBindingType.Filtering if is_sampler else UInt32(0)),
        WGPUTextureBindingLayout(
            null_opaque(),
            UInt32(0) if is_sampler else WGPUTextureSampleType.Float,
            UInt32(0) if is_sampler else WGPUTextureViewDimension.D2Array,
            UInt32(0),
        ),
        WGPUStorageTextureBindingLayout(null_opaque(), UInt32(0), UInt32(0), UInt32(0)),
    )


struct WebTexture(Movable):
    var boot: GPUBoot
    var capture: Optional[FrameCapture]
    var target: Optional[Texture]
    var req: Optional[MapRequest]
    var pixels: List[UInt8]  # W * H * 4, row by row, once read back
    var polls: Int

    def __init__(out self) raises:
        self.boot = GPUBoot("texture")
        self.capture = None
        self.target = None
        self.req = None
        self.pixels = List[UInt8]()
        self.polls = 0

    def __init__(out self, *, deinit move: Self):
        self.boot = move.boot^
        self.capture = move.capture^
        self.target = move.target^
        self.req = move.req^
        self.pixels = move.pixels^
        self.polls = move.polls

    def draw(mut self) raises:
        ref device = self.boot.device()
        var tex = device.create_texture(
            UInt32(4), UInt32(4), UInt32(2), WGPUTextureFormat.RGBA8Unorm,
            WGPUTextureUsage.TEXTURE_BINDING | WGPUTextureUsage.COPY_DST,
            UInt32(2), UInt32(2), UInt32(1), "layers",
        )
        # one write per (layer, level): the layer is the z of the origin
        device.queue_write_texture(tex, 0, WGPUOrigin3D(0, 0, 0), WGPUTextureAspect.All, halves(255, 0, 0, 4), 16, 4, 4, 4, 1)
        device.queue_write_texture(tex, 0, WGPUOrigin3D(0, 0, 1), WGPUTextureAspect.All, halves(0, 255, 0, 4), 16, 4, 4, 4, 1)
        device.queue_write_texture(tex, 1, WGPUOrigin3D(0, 0, 0), WGPUTextureAspect.All, halves(0, 0, 255, 2), 8, 2, 2, 2, 1)
        device.queue_write_texture(tex, 1, WGPUOrigin3D(0, 0, 1), WGPUTextureAspect.All, halves(255, 255, 255, 2), 8, 2, 2, 2, 1)

        var vd = raw_alloc[WGPUTextureViewDescriptor](1)
        vd[] = WGPUTextureViewDescriptor(
            null_opaque(), WGPUStringView.null_view(), UInt32(0), WGPUTextureViewDimension.D2Array,
            UInt32(0), UNDEFINED, UInt32(0), UNDEFINED, WGPUTextureAspect.All, UInt64(0),
        )
        var view = tex.create_view(vd)
        vd.unsafe_free()
        var sampler = device.create_sampler(
            WGPUAddressMode.Repeat, WGPUAddressMode.Repeat, WGPUAddressMode.Repeat,
            WGPUFilterMode.Nearest, WGPUFilterMode.Nearest, WGPUMipmapFilterMode.Nearest,
            label="repeat_nearest",
        )

        var bgl_entries: List[WGPUBindGroupLayoutEntry] = [layout_entry(0, False), layout_entry(1, True)]
        var bgl = device.create_bind_group_layout(bgl_entries)
        var bg_entries: List[WGPUBindGroupEntry] = [
            WGPUBindGroupEntry(null_opaque(), UInt32(0), null_opaque(), UInt64(0), UInt64(0), null_opaque(), view.handle().raw),
            WGPUBindGroupEntry(null_opaque(), UInt32(1), null_opaque(), UInt64(0), UInt64(0), sampler.handle().raw, null_opaque()),
        ]
        var bg = device.create_bind_group(bgl, bg_entries)
        var pl = device.create_pipeline_layout(bgl, "texture_pl")
        var shader = device.create_shader_module_wgsl(SHADER, "texture_shader")
        var pipeline = device.create_render_pipeline(shader, "vs_main", "fs_main", WGPUTextureFormat.RGBA8Unorm, pl)

        var target = device.create_texture(
            W, H, UInt32(1), WGPUTextureFormat.RGBA8Unorm,
            WGPUTextureUsage.RENDER_ATTACHMENT | WGPUTextureUsage.COPY_SRC, label="texture_target",
        )
        var target_view = target.create_view_default()  # before the encoder: nothing may raise while it is open
        var enc = device.create_command_encoder("texture_draw")
        var rpass = enc.begin_render_pass_clear(target_view^, WGPUColor(0.0, 0.0, 0.0, 1.0), "texture_pass")
        rpass.set_pipeline(pipeline)
        rpass.set_bind_group(UInt32(0), bg)
        rpass.draw(UInt32(3), UInt32(1), UInt32(0), UInt32(0))
        rpass^.end()
        device.queue_submit(enc^.finish())

        self.capture = FrameCapture(device, W, H)
        self.req = self.capture.value().capture(device, target.handle().raw)
        self.target = target^
        _ = pipeline^
        _ = bg^
        _ = view^
        _ = sampler^
        _ = tex^

    def step(mut self) raises -> Int32:
        """0 = still working, 1 = the pixels are read back."""
        if len(self.pixels) > 0:
            return 1
        if not self.boot.step():
            return 0
        if not self.capture:
            self.draw()
            return 0
        self.polls += 1
        if not self.req.value().ready():
            return 0
        var req = self.req.take()
        var p = req.take().unsafe_bitcast[UInt8]()
        var pitch = Int(self.capture.value().row_pitch())
        for y in range(Int(H)):
            for x in range(Int(W) * 4):
                self.pixels.append(p[unsafe_offset=y * pitch + x])
        self.capture.value().unmap()
        return 1


def _app(handle: UInt64) -> Pointer[WebTexture, MutUntrackedOrigin]:
    return Pointer[WebTexture, MutUntrackedOrigin](unsafe_from_address=Int(handle))


@export
def texture_start() abi("C") -> UInt64:
    try:
        var p = raw_alloc[WebTexture](1)
        p.unsafe_write(WebTexture())
        return UInt64(Int(p))
    except e:
        print("texture_start:", e)
        return 0


@export
def texture_step(app: UInt64) abi("C") -> Int32:
    """0 = working, 1 = done, -1 = error."""
    try:
        return _app(app)[].step()
    except e:
        print("texture_step:", e)
        return -1


@export
def texture_pixel(app: UInt64, x: Int32, y: Int32, channel: Int32) abi("C") -> Int32:
    return Int32(_app(app)[].pixels[(Int(y) * Int(W) + Int(x)) * 4 + Int(channel)])


@export
def texture_polls(app: UInt64) abi("C") -> Int32:
    return Int32(_app(app)[].polls)
