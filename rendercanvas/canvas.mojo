"""
rendercanvas.canvas — RenderCanvas: GLFW window + wgpu Surface, glued together.

Usage (typical render loop):

    var gpu    = GPU()
    var device = gpu.request_device()
    var canvas = RenderCanvas(gpu, device, 800, 600, "Hello wgpu")

    while canvas.is_open():
        canvas.poll()
        var (tex, status) = canvas.next_frame()
        if status == 1 or status == 2:
            # ... render to tex via device ...
            canvas.present()

    _ = canvas^   # explicit drop (calls glfwDestroyWindow + glfwTerminate)

The title String must not be empty (GLFW requirement).
"""

from wgpu._ffi.types import OpaquePtr, WGPUTextureHandle
from wgpu.gpu import GPU
from wgpu.device import Device
from wgpu.surface import Surface, SurfaceFrame
from rendercanvas.glfw import GLFWLib, GLFW_CLIENT_API, GLFW_NO_API, GLFW_RESIZABLE, GLFW_TRUE
from rendercanvas.input import InputState


struct RenderCanvas(Movable):
    """Owns a GLFW window and a configured wgpu Surface.

    The caller retains ownership of their GPU and Device —
    both must outlive the RenderCanvas.
    """

    var _glfw:    GLFWLib
    var _window:  OpaquePtr
    var _surface: Surface
    var _width:   Int32
    var _height:  Int32
    var input:    InputState

    def __init__(
        out self,
        gpu: GPU,
        device: Device,
        width:  Int32,
        height: Int32,
        title:  String,
    ) raises:
        # --- Init GLFW ---------------------------------------------------
        var glfw = GLFWLib()
        var ok = glfw.init()
        if not Bool(ok):
            raise Error("glfwInit() failed")

        glfw.window_hint(GLFW_CLIENT_API, GLFW_NO_API)  # no OpenGL context
        glfw.window_hint(GLFW_RESIZABLE, GLFW_TRUE)

        # Pass null-terminated title; String internal buffer is null-terminated.
        var title_bytes = title.as_bytes()
        var raw         = title_bytes.unsafe_ptr().bitcast[NoneType]()
        var title_ptr   = rebind[OpaquePtr](raw)
        var window = glfw.create_window(width, height, title_ptr)
        _ = title_bytes  # keep alive past glfwCreateWindow
        if not Bool(window):
            glfw.terminate()
            raise Error("glfwCreateWindow() returned NULL")

        # --- Detect platform, create Surface, then configure --------------
        # Any failure in this block must tear down GLFW resources.
        var surface: Surface
        # try:
        # Try Wayland first (preferred on modern Linux); fall back to X11.
        var display = glfw.get_wayland_display()
        if Bool(display):
            var wl_surf = glfw.get_wayland_window(window)
            if not Bool(wl_surf):
                pass
                # raise Error("glfwGetWaylandWindow() returned NULL")
            surface = gpu.create_surface_wayland(display, wl_surf)
        else:
            var x11_disp = glfw.get_x11_display()
            if not Bool(x11_disp):
                pass
                # raise Error("No Wayland or X11 display available from GLFW")
            var x11_win = glfw.get_x11_window(window)
            surface = gpu.create_surface_xlib(x11_disp, x11_win)

        # Configure surface (pick format, set up swapchain).
        surface.configure(gpu.adapter_handle(), device.handle().raw, UInt32(width), UInt32(height))
        # except:
        #     glfw.destroy_window(window)
        #     glfw.terminate()
        #     raise

        # --- Install input callbacks (key, mouse, cursor, scroll) --------
        glfw.install_input_callbacks(window)

        # --- Store ---
        self._glfw    = glfw^
        self._window  = window
        self._surface = surface^
        self._width   = width
        self._height  = height
        self.input    = InputState()

    def __init__(out self, *, deinit take: Self):
        self._glfw    = take._glfw^
        self._window  = take._window
        self._surface = take._surface^
        self._width   = take._width
        self._height  = take._height
        self.input    = take.input^

    def __del__(deinit self):
        self._glfw.destroy_window(self._window)
        self._glfw.terminate()

    # ------------------------------------------------------------------
    # Render loop helpers
    # ------------------------------------------------------------------

    def is_open(self) -> Bool:
        """Returns True while the window close button has not been pressed."""
        return not Bool(self._glfw.window_should_close(self._window))

    def poll(mut self):
        """Process pending window / input events (call once per frame).

        Clears per-frame input state, pumps GLFW events, then drains the
        C-side event queue into self.input.
        """
        self.input.begin_frame()
        self._glfw.poll_events()
        self.input.update(self._glfw)

    def next_frame(self) -> SurfaceFrame:
        """Acquire the next swapchain texture.

        Returns a SurfaceFrame. Call is_renderable() to decide whether
        to draw — skip the frame body when it returns False.
        """
        return self._surface.get_current_texture()

    def present(self):
        """Present the rendered frame to the window."""
        self._surface.present()

    # ------------------------------------------------------------------
    # Properties
    # ------------------------------------------------------------------

    def surface_format(self) -> UInt32:
        return self._surface.format()

    def width(self) -> Int32:
        return self._width

    def height(self) -> Int32:
        return self._height
