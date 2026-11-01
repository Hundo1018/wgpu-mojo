"""
Web driver for examples/web/triangle_app.mojo (#14).

The host owns the loop: web/wgpu_host.mjs calls the exports below, frame() once
per requestAnimationFrame. Mojo has no globals, so init() returns the app state
as an opaque handle that JS passes back to every call.

Build and run:
    pixi run build-web      # -> build/web/triangle.{mjs,wasm}
    pixi run test-web       # headless Chrome, checks the captured pixels
"""

from wgpu._backend.wgpu_native.alloc_guard import raw_alloc
from wgpu._ffi.types import WGPUTextureUsage
from wgpu.texture import Texture
from wgpu.buffer import MapRequest
from wgpu.capture import FrameCapture, padded_row_pitch
from wgpu.rendercanvas.glfw import MojoInputEvent
from wgpu.rendercanvas.input import InputState
from wgpu.surface import Surface, create_surface_canvas
from wgpu.web.boot import GPUBoot
from triangle_app import TriangleApp


struct WebTriangle(Movable):
    var boot: GPUBoot
    var surface: Surface
    var width: UInt32
    var height: UInt32
    var app: Optional[TriangleApp]
    var input: InputState
    var capture: Optional[FrameCapture]
    var capture_target: Optional[Texture]
    var capture_req: Optional[MapRequest]
    var capture_ptr: UInt64
    var want_capture: Bool
    var frames: Int

    def __init__(out self, selector: String, width: UInt32, height: UInt32) raises:
        self.boot = GPUBoot("triangle")
        self.surface = create_surface_canvas(
            self.boot.instance.lib(), self.boot.instance.handle(), selector
        )
        self.width = width
        self.height = height
        self.app = None
        self.input = InputState()
        self.capture = None
        self.capture_target = None
        self.capture_req = None
        self.capture_ptr = 0
        self.want_capture = False
        self.frames = 0

    def __init__(out self, *, deinit move: Self):
        self.boot = move.boot^
        self.surface = move.surface^
        self.width = move.width
        self.height = move.height
        self.app = move.app^
        self.input = move.input^
        self.capture = move.capture^
        self.capture_target = move.capture_target^
        self.capture_req = move.capture_req^
        self.capture_ptr = move.capture_ptr
        self.want_capture = move.want_capture
        self.frames = move.frames

    def frame(mut self) raises -> Int32:
        """0 while the GPU is still being set up, 1 once a frame was drawn."""
        if not self.boot.step():
            return 0
        if not self.app:
            self.surface.configure(
                self.boot.adapter().handle(), self.boot.device().handle().raw,
                self.width, self.height,
            )
            self.app = TriangleApp(self.boot.device(), self.surface.format())
            self.capture = FrameCapture(self.boot.device(), self.width, self.height)
            # Frames are captured from an app-owned target, not the canvas's
            # texture: headless Chrome cannot read a canvas texture back.
            self.capture_target = self.boot.device().create_texture(
                self.width, self.height, 1, self.surface.format(),
                WGPUTextureUsage.RENDER_ATTACHMENT | WGPUTextureUsage.COPY_SRC,
                label="capture_target",
            )

        var tex = self.surface.get_current_texture()
        if tex.is_renderable():
            self.app.value().render(self.boot.device(), tex.texture)
            if self.want_capture and not self.capture_req:
                var target = self.capture_target.value().handle().raw
                self.app.value().render(self.boot.device(), target)
                self.capture_req = self.capture.value().capture(self.boot.device(), target)
                self.want_capture = False
            self.surface.present()
            self.frames += 1

        if self.capture_req and self.capture_req.value().ready():
            var req = self.capture_req.take()
            self.capture_ptr = UInt64(Int(req.take()))
        self.input.begin_frame()
        return 1


def _app(handle: UInt64) -> Pointer[WebTriangle, MutUntrackedOrigin]:
    return Pointer[WebTriangle, MutUntrackedOrigin](unsafe_from_address=Int(handle))


@export
def wgpu_app_init(selector: UInt64, selector_len: UInt64, width: UInt32, height: UInt32) abi("C") -> UInt64:
    """Create the app on the canvas matching `selector` (UTF-8, not NUL-terminated).
    Returns 0 on failure."""
    try:
        var bytes = Span(
            unsafe_ptr=Pointer[UInt8, MutUntrackedOrigin](unsafe_from_address=Int(selector)),
            length=Int(selector_len),
        )
        var sel = String(StringSlice(unsafe_from_utf8=bytes))
        var p = raw_alloc[WebTriangle](1)
        p.unsafe_write(WebTriangle(sel, width, height))
        return UInt64(Int(p))
    except e:
        print("wgpu_app_init:", e)
        return 0


@export
def wgpu_app_frame(app: UInt64, dt: Float64) abi("C") -> Int32:
    """Advance one frame. 0 = setting up, 1 = drew a frame, -1 = error."""
    try:
        return _app(app)[].frame()
    except e:
        print("wgpu_app_frame:", e)
        return -1


@export
def wgpu_app_input(
    app: UInt64, kind: Int32, key: Int32, action: Int32, mods: Int32, x: Float64, y: Float64
) abi("C"):
    """A DOM event, already translated to the GLFW codes InputState uses."""
    _app(app)[].input.process_event(MojoInputEvent(kind, key, action, mods, x, y))


@export
def wgpu_app_mouse_x(app: UInt64) abi("C") -> Float64:
    return _app(app)[].input.mouse_x


@export
def wgpu_app_request_capture(app: UInt64) abi("C"):
    """Capture the next drawn frame; poll wgpu_app_capture_ptr for the pixels."""
    _app(app)[].want_capture = True


@export
def wgpu_app_capture_ptr(app: UInt64) abi("C") -> UInt64:
    """Address of the captured pixels in wasm memory, 0 until ready. Rows are
    wgpu_app_capture_pitch bytes; format is the surface's (wgpu_app_format)."""
    return _app(app)[].capture_ptr


@export
def wgpu_app_capture_pitch(app: UInt64) abi("C") -> UInt32:
    return padded_row_pitch(_app(app)[].width)


@export
def wgpu_app_capture_release(app: UInt64) abi("C"):
    """Unmap the captured frame so another capture can follow."""
    var a = _app(app)
    if a[].capture_ptr != 0:
        a[].capture.value().unmap()
        a[].capture_ptr = 0


@export
def wgpu_app_format(app: UInt64) abi("C") -> UInt32:
    return _app(app)[].surface.format()


@export
def wgpu_app_frames(app: UInt64) abi("C") -> Int32:
    return Int32(_app(app)[].frames)


@export
def wgpu_app_destroy(app: UInt64) abi("C"):
    var p = _app(app)
    _ = p.unsafe_take_pointee()
    p.unsafe_free()
