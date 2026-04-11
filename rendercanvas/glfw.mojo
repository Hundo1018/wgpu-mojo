"""
rendercanvas.glfw — Minimal GLFW FFI (DLHandle-based, Wayland-first).

Only the functions needed for wgpu surface creation and the render loop are
bound.  GLFW must be compiled with Wayland + X11 native extensions enabled
(the conda-forge `glfw` package satisfies this on Linux).

Usage:
    var glfw = GLFWLib()
    _ = glfw.init()
    glfw.window_hint(GLFW_CLIENT_API, GLFW_NO_API)  # no OpenGL context
    var win = glfw.create_window(800, 600, "Hello wgpu")
    ...
    while not Bool(glfw.window_should_close(win)):
        glfw.poll_events()
        # render...
    glfw.destroy_window(win)
    glfw.terminate()
"""

from std.ffi import OwnedDLHandle
from wgpu._ffi.types import OpaquePtr


# ---------------------------------------------------------------------------
# GLFW integer constants
# ---------------------------------------------------------------------------
comptime GLFW_CLIENT_API: Int32 = 0x00022001
comptime GLFW_NO_API:     Int32 = 0
comptime GLFW_RESIZABLE:  Int32 = 0x00020003
comptime GLFW_TRUE:       Int32 = 1
comptime GLFW_FALSE:      Int32 = 0

comptime _GLFW_LIB = "libglfw.so"


# ---------------------------------------------------------------------------
# GLFWLib — runtime-loaded libglfw.so
# ---------------------------------------------------------------------------

struct GLFWLib(Movable):
    """Dynamically loaded libglfw.so; mirrors the pattern in WGPULib."""

    var _lib: OwnedDLHandle

    def __init__(out self) raises:
        self._lib = OwnedDLHandle(_GLFW_LIB)

    def __init__(out self, *, deinit take: Self):
        self._lib = take._lib^

    def __del__(deinit self):
        pass  # OwnedDLHandle handles dlclose

    # --- Core lifecycle ------------------------------------------------

    def init(self) -> Int32:
        """Call glfwInit(). Returns GLFW_TRUE on success."""
        return self._lib.call["glfwInit", Int32]()

    def terminate(self):
        self._lib.call["glfwTerminate"]()

    # --- Window hints and creation ------------------------------------

    def window_hint(self, hint: Int32, value: Int32):
        self._lib.call["glfwWindowHint"](hint, value)

    def create_window(
        self,
        width: Int32,
        height: Int32,
        title: OpaquePtr,
        monitor: OpaquePtr = OpaquePtr(),
        share: OpaquePtr = OpaquePtr(),
    ) -> OpaquePtr:
        """Create a GLFW window; returns GLFWwindow* (or NULL on failure)."""
        return self._lib.call["glfwCreateWindow", OpaquePtr](
            width, height, title, monitor, share
        )

    def destroy_window(self, window: OpaquePtr):
        self._lib.call["glfwDestroyWindow"](window)

    # --- Event loop ---------------------------------------------------

    def window_should_close(self, window: OpaquePtr) -> Int32:
        return self._lib.call["glfwWindowShouldClose", Int32](window)

    def poll_events(self):
        self._lib.call["glfwPollEvents"]()

    # --- Size query ---------------------------------------------------

    def get_framebuffer_size(self, window: OpaquePtr) -> (Int32, Int32):
        var w_p = alloc[Int32](1)
        var h_p = alloc[Int32](1)
        self._lib.call["glfwGetFramebufferSize"](window, w_p, h_p)
        var w = w_p[]
        var h = h_p[]
        w_p.free()
        h_p.free()
        return (w, h)

    # --- Wayland native pointers (for wgpu surface creation) ----------

    def get_wayland_display(self) -> OpaquePtr:
        """Returns wl_display* for the Wayland display connection.

        Returns NULL if GLFW is not running on Wayland.
        """
        return self._lib.call["glfwGetWaylandDisplay", OpaquePtr]()

    def get_wayland_window(self, window: OpaquePtr) -> OpaquePtr:
        """Returns wl_surface* for the given GLFW window on Wayland."""
        return self._lib.call["glfwGetWaylandWindow", OpaquePtr](window)

    # --- X11 native pointers (XWayland / bare X11 fallback) ----------

    def get_x11_display(self) -> OpaquePtr:
        """Returns X11 Display* pointer."""
        return self._lib.call["glfwGetX11Display", OpaquePtr]()

    def get_x11_window(self, window: OpaquePtr) -> UInt64:
        """Returns X11 Window (unsigned long) for the given GLFW window."""
        return self._lib.call["glfwGetX11Window", UInt64](window)
