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

# --- Key action codes -----------------------------------------------------
comptime GLFW_RELEASE: Int32 = 0
comptime GLFW_PRESS:   Int32 = 1
comptime GLFW_REPEAT:  Int32 = 2

# --- Mouse button IDs -----------------------------------------------------
comptime GLFW_MOUSE_BUTTON_LEFT:   Int32 = 0
comptime GLFW_MOUSE_BUTTON_RIGHT:  Int32 = 1
comptime GLFW_MOUSE_BUTTON_MIDDLE: Int32 = 2
comptime GLFW_MOUSE_BUTTON_LAST:   Int32 = 7

# --- Modifier key bitmasks -------------------------------------------------
comptime GLFW_MOD_SHIFT:   Int32 = 0x0001
comptime GLFW_MOD_CONTROL: Int32 = 0x0002
comptime GLFW_MOD_ALT:     Int32 = 0x0004
comptime GLFW_MOD_SUPER:   Int32 = 0x0008

# --- Cursor / input mode ---------------------------------------------------
comptime GLFW_CURSOR:               Int32 = 0x00033001
comptime GLFW_STICKY_KEYS:          Int32 = 0x00033002
comptime GLFW_STICKY_MOUSE_BUTTONS: Int32 = 0x00033003
comptime GLFW_CURSOR_NORMAL:        Int32 = 0x00034001
comptime GLFW_CURSOR_HIDDEN:        Int32 = 0x00034002
comptime GLFW_CURSOR_DISABLED:      Int32 = 0x00034003

# --- Printable key codes (match ASCII) ------------------------------------
comptime GLFW_KEY_SPACE:      Int32 = 32
comptime GLFW_KEY_APOSTROPHE: Int32 = 39
comptime GLFW_KEY_COMMA:      Int32 = 44
comptime GLFW_KEY_MINUS:      Int32 = 45
comptime GLFW_KEY_PERIOD:     Int32 = 46
comptime GLFW_KEY_SLASH:      Int32 = 47
comptime GLFW_KEY_0: Int32 = 48
comptime GLFW_KEY_1: Int32 = 49
comptime GLFW_KEY_2: Int32 = 50
comptime GLFW_KEY_3: Int32 = 51
comptime GLFW_KEY_4: Int32 = 52
comptime GLFW_KEY_5: Int32 = 53
comptime GLFW_KEY_6: Int32 = 54
comptime GLFW_KEY_7: Int32 = 55
comptime GLFW_KEY_8: Int32 = 56
comptime GLFW_KEY_9: Int32 = 57
comptime GLFW_KEY_SEMICOLON: Int32 = 59
comptime GLFW_KEY_EQUAL:     Int32 = 61
comptime GLFW_KEY_A: Int32 = 65
comptime GLFW_KEY_B: Int32 = 66
comptime GLFW_KEY_C: Int32 = 67
comptime GLFW_KEY_D: Int32 = 68
comptime GLFW_KEY_E: Int32 = 69
comptime GLFW_KEY_F: Int32 = 70
comptime GLFW_KEY_G: Int32 = 71
comptime GLFW_KEY_H: Int32 = 72
comptime GLFW_KEY_I: Int32 = 73
comptime GLFW_KEY_J: Int32 = 74
comptime GLFW_KEY_K: Int32 = 75
comptime GLFW_KEY_L: Int32 = 76
comptime GLFW_KEY_M: Int32 = 77
comptime GLFW_KEY_N: Int32 = 78
comptime GLFW_KEY_O: Int32 = 79
comptime GLFW_KEY_P: Int32 = 80
comptime GLFW_KEY_Q: Int32 = 81
comptime GLFW_KEY_R: Int32 = 82
comptime GLFW_KEY_S: Int32 = 83
comptime GLFW_KEY_T: Int32 = 84
comptime GLFW_KEY_U: Int32 = 85
comptime GLFW_KEY_V: Int32 = 86
comptime GLFW_KEY_W: Int32 = 87
comptime GLFW_KEY_X: Int32 = 88
comptime GLFW_KEY_Y: Int32 = 89
comptime GLFW_KEY_Z: Int32 = 90

# --- Function keys ---------------------------------------------------------
comptime GLFW_KEY_ESCAPE:       Int32 = 256
comptime GLFW_KEY_ENTER:        Int32 = 257
comptime GLFW_KEY_TAB:          Int32 = 258
comptime GLFW_KEY_BACKSPACE:    Int32 = 259
comptime GLFW_KEY_INSERT:       Int32 = 260
comptime GLFW_KEY_DELETE:       Int32 = 261
comptime GLFW_KEY_RIGHT:        Int32 = 262
comptime GLFW_KEY_LEFT:         Int32 = 263
comptime GLFW_KEY_DOWN:         Int32 = 264
comptime GLFW_KEY_UP:           Int32 = 265
comptime GLFW_KEY_PAGE_UP:      Int32 = 266
comptime GLFW_KEY_PAGE_DOWN:    Int32 = 267
comptime GLFW_KEY_HOME:         Int32 = 268
comptime GLFW_KEY_END:          Int32 = 269
comptime GLFW_KEY_CAPS_LOCK:    Int32 = 280
comptime GLFW_KEY_SCROLL_LOCK:  Int32 = 281
comptime GLFW_KEY_NUM_LOCK:     Int32 = 282
comptime GLFW_KEY_PRINT_SCREEN: Int32 = 283
comptime GLFW_KEY_PAUSE:        Int32 = 284
comptime GLFW_KEY_F1:  Int32 = 290
comptime GLFW_KEY_F2:  Int32 = 291
comptime GLFW_KEY_F3:  Int32 = 292
comptime GLFW_KEY_F4:  Int32 = 293
comptime GLFW_KEY_F5:  Int32 = 294
comptime GLFW_KEY_F6:  Int32 = 295
comptime GLFW_KEY_F7:  Int32 = 296
comptime GLFW_KEY_F8:  Int32 = 297
comptime GLFW_KEY_F9:  Int32 = 298
comptime GLFW_KEY_F10: Int32 = 299
comptime GLFW_KEY_F11: Int32 = 300
comptime GLFW_KEY_F12: Int32 = 301

# --- Modifier keys ---------------------------------------------------------
comptime GLFW_KEY_LEFT_SHIFT:    Int32 = 340
comptime GLFW_KEY_LEFT_CONTROL:  Int32 = 341
comptime GLFW_KEY_LEFT_ALT:      Int32 = 342
comptime GLFW_KEY_LEFT_SUPER:    Int32 = 343
comptime GLFW_KEY_RIGHT_SHIFT:   Int32 = 344
comptime GLFW_KEY_RIGHT_CONTROL: Int32 = 345
comptime GLFW_KEY_RIGHT_ALT:     Int32 = 346
comptime GLFW_KEY_RIGHT_SUPER:   Int32 = 347

comptime GLFW_KEY_LAST: Int32 = 348

comptime _GLFW_LIB = "libglfw.so"
comptime _GLFW_INPUT_CB_LIB = "ffi/lib/libglfw_input_cb.so"


# ---------------------------------------------------------------------------
# GLFWLib — runtime-loaded libglfw.so
# ---------------------------------------------------------------------------

struct GLFWLib(Movable):
    """Dynamically loaded libglfw.so; mirrors the pattern in WGPULib."""

    var _lib: OwnedDLHandle
    var _input_cb: OwnedDLHandle

    def __init__(out self) raises:
        self._lib = OwnedDLHandle(_GLFW_LIB)
        self._input_cb = OwnedDLHandle(_GLFW_INPUT_CB_LIB)

    def __init__(out self, *, deinit take: Self):
        self._lib = take._lib^
        self._input_cb = take._input_cb^

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

    def get_framebuffer_size(
        self,
        window: OpaquePtr,
        out_w: UnsafePointer[Int32, MutExternalOrigin],
        out_h: UnsafePointer[Int32, MutExternalOrigin],
    ):
        """Write framebuffer width/height into the provided pointers."""
        self._lib.call["glfwGetFramebufferSize"](window, out_w, out_h)

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

    # --- Keyboard polling -----------------------------------------------

    def get_key(self, window: OpaquePtr, key: Int32) -> Int32:
        """Query key state: returns GLFW_PRESS or GLFW_RELEASE."""
        return self._lib.call["glfwGetKey", Int32](window, key)

    # --- Mouse polling --------------------------------------------------

    def get_mouse_button(self, window: OpaquePtr, button: Int32) -> Int32:
        """Query mouse button state: returns GLFW_PRESS or GLFW_RELEASE."""
        return self._lib.call["glfwGetMouseButton", Int32](window, button)

    def get_cursor_pos(
        self,
        window: OpaquePtr,
        out_x: UnsafePointer[Float64, MutExternalOrigin],
        out_y: UnsafePointer[Float64, MutExternalOrigin],
    ):
        """Write cursor position into the provided pointers."""
        self._lib.call["glfwGetCursorPos"](window, out_x, out_y)

    def set_cursor_pos(self, window: OpaquePtr, xpos: Float64, ypos: Float64):
        """Set cursor position in window coordinates."""
        self._lib.call["glfwSetCursorPos"](window, xpos, ypos)

    # --- Input mode -----------------------------------------------------

    def set_input_mode(self, window: OpaquePtr, mode: Int32, value: Int32):
        """Set input mode (e.g. GLFW_CURSOR → GLFW_CURSOR_DISABLED)."""
        self._lib.call["glfwSetInputMode"](window, mode, value)

    def get_input_mode(self, window: OpaquePtr, mode: Int32) -> Int32:
        """Get current input mode value."""
        return self._lib.call["glfwGetInputMode", Int32](window, mode)

    # --- C callback bridge (event queue) --------------------------------

    def install_input_callbacks(self, window: OpaquePtr):
        """Install all GLFW input callbacks (key, mouse button, cursor, scroll).

        Events are pushed to a ring buffer in C; drain with poll_input_event().
        """
        self._input_cb.call["mojo_glfw_install_input_callbacks"](window)

    def remove_input_callbacks(self, window: OpaquePtr):
        """Remove all GLFW input callbacks (set to NULL)."""
        self._input_cb.call["mojo_glfw_remove_input_callbacks"](window)

    def poll_input_event(self, out_ptr: UnsafePointer[MojoInputEvent, MutExternalOrigin]) -> Int32:
        """Pop one event from the C-side ring buffer.

        Returns 1 if an event was written to out_ptr, 0 if queue empty.
        """
        return self._input_cb.call["mojo_input_poll_event", Int32](out_ptr)

    def input_queue_count(self) -> Int32:
        """Number of pending events in the C-side ring buffer."""
        return self._input_cb.call["mojo_input_queue_count", Int32]()


# ---------------------------------------------------------------------------
# MojoInputEvent — matches the C struct in ffi/glfw_input_callbacks.c
# ---------------------------------------------------------------------------

@fieldwise_init
struct MojoInputEvent(TrivialRegisterPassable):
    """Event from the GLFW callback bridge ring buffer.

    Fields match the C layout (all 8-byte aligned):
      int32 type, int32 key_or_button, int32 action, int32 mods,
      float64 x, float64 y
    Total: 32 bytes.
    """
    var type: Int32           # InputEventType: 1=key, 2=mouse_button, 3=cursor_pos, 4=scroll
    var key_or_button: Int32  # GLFW key code or mouse button ID
    var action: Int32         # GLFW_PRESS / GLFW_RELEASE / GLFW_REPEAT
    var mods: Int32           # Modifier bitmask (GLFW_MOD_*)
    var x: Float64            # cursor x or scroll x offset
    var y: Float64            # cursor y or scroll y offset


struct InputEventType:
    """Constants for MojoInputEvent.type field."""
    comptime KEY: Int32 = 1
    comptime MOUSE_BUTTON: Int32 = 2
    comptime CURSOR_POS: Int32 = 3
    comptime SCROLL: Int32 = 4
