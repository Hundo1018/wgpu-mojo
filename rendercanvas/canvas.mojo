"""
rendercanvas.canvas — RenderCanvas: GLFW window + wgpu Surface, glued together.

Usage (typical render loop):

    var inst   = request_adapter()
    var device = inst.request_device()
    var canvas = RenderCanvas(inst, device, 800, 600, "Hello wgpu")

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
from wgpu.instance import Instance
from wgpu.device import Device
from wgpu.surface import Surface, SurfaceFrame
from rendercanvas.glfw import GLFWLib, GLFW_CLIENT_API, GLFW_NO_API, GLFW_RESIZABLE, GLFW_TRUE


struct RenderCanvas(Movable):
    """Owns a GLFW window and a configured wgpu Surface.

    The caller retains ownership of their Instance and Device —
    both must outlive the RenderCanvas.
    """

    var _glfw:    GLFWLib
    var _window:  OpaquePtr
    var _surface: Surface
    var _width:   Int32
    var _height:  Int32

    def __init__(
        out self,
        inst:   Instance,
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

        # --- Detect platform and create Surface --------------------------
        # Try Wayland first (preferred on modern Linux); fall back to X11.
        var display = glfw.get_wayland_display()
        var surface: Surface
        if Bool(display):
            var wl_surf = glfw.get_wayland_window(window)
            if not Bool(wl_surf):
                glfw.destroy_window(window)
                glfw.terminate()
                raise Error("glfwGetWaylandWindow() returned NULL")
            surface = inst.create_surface_wayland(display, wl_surf)
        else:
            var x11_disp = glfw.get_x11_display()
            if not Bool(x11_disp):
                glfw.destroy_window(window)
                glfw.terminate()
                raise Error("No Wayland or X11 display available from GLFW")
            var x11_win = glfw.get_x11_window(window)
            surface = inst.create_surface_xlib(x11_disp, x11_win)

        # --- Configure surface (pick format, set up swapchain) -----------
        surface.configure(inst.adapter_handle(), device.handle(), UInt32(width), UInt32(height))

        # --- Store ---
        self._glfw    = glfw^
        self._window  = window
        self._surface = surface^
        self._width   = width
        self._height  = height

    def __init__(out self, *, deinit take: Self):
        self._glfw    = take._glfw^
        self._window  = take._window
        self._surface = take._surface^
        self._width   = take._width
        self._height  = take._height

    def __del__(deinit self):
        self._glfw.destroy_window(self._window)
        self._glfw.terminate()

    # ------------------------------------------------------------------
    # Render loop helpers
    # ------------------------------------------------------------------

    def is_open(self) -> Bool:
        """Returns True while the window close button has not been pressed."""
        return not Bool(self._glfw.window_should_close(self._window))

    def poll(self):
        """Process pending window / input events (call once per frame)."""
        self._glfw.poll_events()

    def next_frame(self) -> SurfaceFrame:
        """Acquire the next swapchain texture.

        Returns a SurfaceFrame. Check status: 1 or 2 = renderable, else skip.
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
