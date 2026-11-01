"""
Vector addition in the browser (#14): c = a + b, read back without blocking.

The host calls compute_step() once per animation frame; each call advances a
small state machine (device setup, dispatch, map) and returns at once, so the
page's main thread is never blocked waiting for the GPU.

    pixi run build-web && pixi run test-web
"""

from wgpu._ffi.nulls import null_opaque
from wgpu._backend.wgpu_native.alloc_guard import raw_alloc
from wgpu import (
    WGPUBufferUsage, WGPUShaderStage, WGPU_WHOLE_SIZE, WGPUBufferBindingType,
    WGPUBindGroupLayoutEntry, WGPUBufferBindingLayout, WGPUSamplerBindingLayout,
    WGPUTextureBindingLayout, WGPUStorageTextureBindingLayout, WGPUBindGroupEntry,
)
from wgpu._ffi.types import WGPUMapMode
from wgpu.buffer import Buffer, MapRequest
from wgpu.web.boot import GPUBoot

comptime N = 1024

comptime SHADER = """
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


def storage_entry(binding: UInt32, readonly: Bool) -> WGPUBindGroupLayoutEntry:
    var kind = WGPUBufferBindingType.ReadOnlyStorage if readonly else WGPUBufferBindingType.Storage
    return WGPUBindGroupLayoutEntry(
        null_opaque(), binding, WGPUShaderStage.COMPUTE.value, UInt32(0),
        WGPUBufferBindingLayout(null_opaque(), kind, UInt32(0), UInt64(0)),
        WGPUSamplerBindingLayout(null_opaque(), UInt32(0)),
        WGPUTextureBindingLayout(null_opaque(), UInt32(0), UInt32(0), UInt32(0)),
        WGPUStorageTextureBindingLayout(null_opaque(), UInt32(0), UInt32(0), UInt32(0)),
    )


struct WebCompute(Movable):
    var boot: GPUBoot
    var readback: Optional[Buffer]
    var req: Optional[MapRequest]
    var result: List[Float32]
    var polls: Int
    var two: Optional[Buffer]
    var two2: Optional[Buffer]
    var two_a: Optional[MapRequest]
    var two_b: Optional[MapRequest]
    var two_done: Bool

    def __init__(out self) raises:
        self.boot = GPUBoot("compute")
        self.readback = None
        self.req = None
        self.result = List[Float32]()
        self.polls = 0
        self.two = None
        self.two2 = None
        self.two_a = None
        self.two_b = None
        self.two_done = False

    def __init__(out self, *, deinit move: Self):
        self.boot = move.boot^
        self.readback = move.readback^
        self.req = move.req^
        self.result = move.result^
        self.polls = move.polls
        self.two = move.two^
        self.two2 = move.two2^
        self.two_a = move.two_a^
        self.two_b = move.two_b^
        self.two_done = move.two_done

    def dispatch(mut self) raises:
        ref device = self.boot.device()
        var shader = device.create_shader_module_wgsl(SHADER, "vec_add")
        var bgl_entries: List[WGPUBindGroupLayoutEntry] = [
            storage_entry(0, True), storage_entry(1, True), storage_entry(2, False),
        ]
        var bgl = device.create_bind_group_layout(bgl_entries)
        var pl = device.create_pipeline_layout(bgl, "compute_pl")
        var pipeline = device.create_compute_pipeline(shader, "main", pl)

        var a = List[Float32](capacity=N)
        var b = List[Float32](capacity=N)
        for i in range(N):
            a.append(Float32(i))
            b.append(Float32(2 * i))
        var bytes = UInt64(N * 4)
        var buf_a = device.create_buffer(bytes, WGPUBufferUsage.STORAGE | WGPUBufferUsage.COPY_DST, label="a")
        var buf_b = device.create_buffer(bytes, WGPUBufferUsage.STORAGE | WGPUBufferUsage.COPY_DST, label="b")
        var buf_c = device.create_buffer(bytes, WGPUBufferUsage.STORAGE | WGPUBufferUsage.COPY_SRC, label="c")
        var buf_r = device.create_buffer(bytes, WGPUBufferUsage.MAP_READ | WGPUBufferUsage.COPY_DST, label="r")
        device.queue_write_data(buf_a, UInt64(0), a)
        device.queue_write_data(buf_b, UInt64(0), b)

        var bg_entries: List[WGPUBindGroupEntry] = [
            WGPUBindGroupEntry(null_opaque(), 0, buf_a.handle().raw, 0, WGPU_WHOLE_SIZE, null_opaque(), null_opaque()),
            WGPUBindGroupEntry(null_opaque(), 1, buf_b.handle().raw, 0, WGPU_WHOLE_SIZE, null_opaque(), null_opaque()),
            WGPUBindGroupEntry(null_opaque(), 2, buf_c.handle().raw, 0, WGPU_WHOLE_SIZE, null_opaque(), null_opaque()),
        ]
        var bg = device.create_bind_group(bgl, bg_entries)

        var enc = device.create_command_encoder("compute")
        var cpass = enc.begin_compute_pass("add")
        cpass.set_pipeline(pipeline)
        cpass.set_bind_group(0, bg)
        cpass.dispatch_workgroups(UInt32((N + 63) // 64))
        cpass^.end()
        enc.copy_buffer_to_buffer(buf_c, 0, buf_r, 0, bytes)
        device.queue_submit(enc^.finish("compute"))

        self.req = buf_r.map_async(WGPUMapMode.READ)
        self.readback = buf_r^
        _ = pipeline^
        _ = bg^
        _ = buf_a^
        _ = buf_b^
        _ = buf_c^

    def step(mut self) raises -> Int32:
        """0 = still working, 1 = result read back."""
        if len(self.result) > 0:
            return 1
        if not self.boot.step():
            return 0
        if not self.readback:
            self.dispatch()
            return 0
        self.polls += 1
        if not self.req.value().ready():
            return 0
        var req = self.req.take()
        var p = req.take().unsafe_bitcast[Float32]()
        for i in range(N):
            self.result.append(p[unsafe_offset=i])
        self.readback.value().unmap()
        return 1

    def two_maps(mut self) raises -> Int32:
        """Two mapAsync calls in one frame (#19). 0 = pending, 1 = both done.
        The host checks the callbacks ran in call order."""
        if self.two_done:
            return 1
        ref device = self.boot.device()
        if not self.two_a:
            var buf = device.create_buffer(
                UInt64(16), WGPUBufferUsage.MAP_READ | WGPUBufferUsage.COPY_DST, label="two"
            )
            var buf2 = device.create_buffer(
                UInt64(16), WGPUBufferUsage.MAP_READ | WGPUBufferUsage.COPY_DST, label="two2"
            )
            self.two_a = buf.map_async(WGPUMapMode.READ)
            self.two_b = buf2.map_async(WGPUMapMode.READ)
            self.two = buf^
            self.two2 = buf2^
            return 0
        if not (self.two_a.value().ready() and self.two_b.value().ready()):
            return 0
        _ = self.two_a.take()
        _ = self.two_b.take()
        self.two.value().unmap()
        self.two2.value().unmap()
        self.two_done = True
        return 1


def _app(handle: UInt64) -> Pointer[WebCompute, MutUntrackedOrigin]:
    return Pointer[WebCompute, MutUntrackedOrigin](unsafe_from_address=Int(handle))


@export
def compute_start() abi("C") -> UInt64:
    try:
        var p = raw_alloc[WebCompute](1)
        p.unsafe_write(WebCompute())
        return UInt64(Int(p))
    except e:
        print("compute_start:", e)
        return 0


@export
def compute_step(app: UInt64) abi("C") -> Int32:
    """0 = working, 1 = done, -1 = error."""
    try:
        return _app(app)[].step()
    except e:
        print("compute_step:", e)
        return -1


@export
def compute_two_maps(app: UInt64) abi("C") -> Int32:
    try:
        return _app(app)[].two_maps()
    except e:
        print("compute_two_maps:", e)
        return -1


@export
def compute_len(app: UInt64) abi("C") -> Int32:
    return Int32(len(_app(app)[].result))


@export
def compute_value(app: UInt64, i: Int32) abi("C") -> Float32:
    return _app(app)[].result[Int(i)]


@export
def compute_polls(app: UInt64) abi("C") -> Int32:
    """How many non-blocking checks the map took (> 0: it never blocked)."""
    return Int32(_app(app)[].polls)
