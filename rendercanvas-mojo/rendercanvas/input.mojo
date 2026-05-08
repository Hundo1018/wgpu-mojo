"""
rendercanvas.input — High-level input state tracking for GLFW-backed windows.

Drains the C-side event ring buffer each frame and maintains per-key /
per-button pressed / just-pressed / just-released state, cursor position
with delta, and scroll accumulator.

Usage (inside a render loop):

    var input = InputState()
    while canvas.is_open():
        input.begin_frame()
        glfw.poll_events()
        input.update(glfw)

        if input.is_key_just_pressed(GLFW_KEY_ESCAPE):
            break
        var (mx, my) = input.get_mouse_pos()
"""

from rendercanvas.glfw import (
    GLFWLib, MojoInputEvent, InputEventType,
    GLFW_PRESS, GLFW_RELEASE,
)

comptime _MAX_KEYS: Int = 512
comptime _MAX_MOUSE_BUTTONS: Int = 8


struct InputState(Movable):
    """Per-frame input state tracker.

    Call begin_frame() before poll_events(), then update() after.
    Query state with is_key_pressed(), get_mouse_pos(), etc.
    """

    # Key state arrays — indexed by GLFW key code (0..511)
    var _keys_pressed:       UnsafePointer[Bool, MutExternalOrigin]
    var _keys_just_pressed:  UnsafePointer[Bool, MutExternalOrigin]
    var _keys_just_released: UnsafePointer[Bool, MutExternalOrigin]

    # Mouse button state (0..7)
    var _mouse_pressed:       UnsafePointer[Bool, MutExternalOrigin]
    var _mouse_just_pressed:  UnsafePointer[Bool, MutExternalOrigin]
    var _mouse_just_released: UnsafePointer[Bool, MutExternalOrigin]

    # Cursor position and per-frame delta
    var mouse_x:  Float64
    var mouse_y:  Float64
    var mouse_dx: Float64
    var mouse_dy: Float64

    # Scroll accumulator (reset each frame)
    var scroll_x: Float64
    var scroll_y: Float64

    def __init__(out self):
        self._keys_pressed       = alloc[Bool](_MAX_KEYS)
        self._keys_just_pressed  = alloc[Bool](_MAX_KEYS)
        self._keys_just_released = alloc[Bool](_MAX_KEYS)
        self._mouse_pressed       = alloc[Bool](_MAX_MOUSE_BUTTONS)
        self._mouse_just_pressed  = alloc[Bool](_MAX_MOUSE_BUTTONS)
        self._mouse_just_released = alloc[Bool](_MAX_MOUSE_BUTTONS)

        # Zero-initialize all arrays
        for i in range(_MAX_KEYS):
            (self._keys_pressed + i)[]       = False
            (self._keys_just_pressed + i)[]  = False
            (self._keys_just_released + i)[] = False
        for i in range(_MAX_MOUSE_BUTTONS):
            (self._mouse_pressed + i)[]       = False
            (self._mouse_just_pressed + i)[]  = False
            (self._mouse_just_released + i)[] = False

        self.mouse_x  = 0.0
        self.mouse_y  = 0.0
        self.mouse_dx = 0.0
        self.mouse_dy = 0.0
        self.scroll_x = 0.0
        self.scroll_y = 0.0

    def __init__(out self, *, deinit take: Self):
        self._keys_pressed       = take._keys_pressed
        self._keys_just_pressed  = take._keys_just_pressed
        self._keys_just_released = take._keys_just_released
        self._mouse_pressed       = take._mouse_pressed
        self._mouse_just_pressed  = take._mouse_just_pressed
        self._mouse_just_released = take._mouse_just_released
        self.mouse_x  = take.mouse_x
        self.mouse_y  = take.mouse_y
        self.mouse_dx = take.mouse_dx
        self.mouse_dy = take.mouse_dy
        self.scroll_x = take.scroll_x
        self.scroll_y = take.scroll_y

    def __del__(deinit self):
        self._keys_pressed.free()
        self._keys_just_pressed.free()
        self._keys_just_released.free()
        self._mouse_pressed.free()
        self._mouse_just_pressed.free()
        self._mouse_just_released.free()

    # ------------------------------------------------------------------
    # Frame lifecycle
    # ------------------------------------------------------------------

    def begin_frame(mut self):
        """Clear per-frame transient state. Call BEFORE poll_events()."""
        for i in range(_MAX_KEYS):
            (self._keys_just_pressed + i)[]  = False
            (self._keys_just_released + i)[] = False
        for i in range(_MAX_MOUSE_BUTTONS):
            (self._mouse_just_pressed + i)[]  = False
            (self._mouse_just_released + i)[] = False
        self.mouse_dx = 0.0
        self.mouse_dy = 0.0
        self.scroll_x = 0.0
        self.scroll_y = 0.0

    def update(mut self, glfw: GLFWLib):
        """Drain the C-side event queue and update state. Call AFTER poll_events()."""
        var evt = alloc[MojoInputEvent](1)
        while Bool(glfw.poll_input_event(evt)):
            self._process_event(evt[])
        evt.free()

    def process_event(mut self, event: MojoInputEvent):
        """Process a single input event (public, for testing without GLFW)."""
        self._process_event(event)

    # ------------------------------------------------------------------
    # Keyboard queries
    # ------------------------------------------------------------------

    def is_key_pressed(self, key: Int32) -> Bool:
        """True if the key is currently held down."""
        var idx = Int(key)
        if idx < 0 or idx >= _MAX_KEYS:
            return False
        return (self._keys_pressed + idx)[]

    def is_key_just_pressed(self, key: Int32) -> Bool:
        """True if the key was pressed this frame."""
        var idx = Int(key)
        if idx < 0 or idx >= _MAX_KEYS:
            return False
        return (self._keys_just_pressed + idx)[]

    def is_key_just_released(self, key: Int32) -> Bool:
        """True if the key was released this frame."""
        var idx = Int(key)
        if idx < 0 or idx >= _MAX_KEYS:
            return False
        return (self._keys_just_released + idx)[]

    # ------------------------------------------------------------------
    # Mouse queries
    # ------------------------------------------------------------------

    def is_mouse_button_pressed(self, button: Int32) -> Bool:
        var idx = Int(button)
        if idx < 0 or idx >= _MAX_MOUSE_BUTTONS:
            return False
        return (self._mouse_pressed + idx)[]

    def is_mouse_button_just_pressed(self, button: Int32) -> Bool:
        var idx = Int(button)
        if idx < 0 or idx >= _MAX_MOUSE_BUTTONS:
            return False
        return (self._mouse_just_pressed + idx)[]

    def is_mouse_button_just_released(self, button: Int32) -> Bool:
        var idx = Int(button)
        if idx < 0 or idx >= _MAX_MOUSE_BUTTONS:
            return False
        return (self._mouse_just_released + idx)[]

    # Mouse position/delta/scroll — access the public fields directly:
    #   input.mouse_x, input.mouse_y
    #   input.mouse_dx, input.mouse_dy
    #   input.scroll_x, input.scroll_y

    # ------------------------------------------------------------------
    # Internal
    # ------------------------------------------------------------------

    def _process_event(mut self, event: MojoInputEvent):
        if event.type == InputEventType.KEY:
            var idx = Int(event.key_or_button)
            if idx >= 0 and idx < _MAX_KEYS:
                if event.action == GLFW_PRESS:
                    (self._keys_pressed + idx)[]      = True
                    (self._keys_just_pressed + idx)[]  = True
                elif event.action == GLFW_RELEASE:
                    (self._keys_pressed + idx)[]       = False
                    (self._keys_just_released + idx)[] = True
                # GLFW_REPEAT: keys_pressed stays True, no just_pressed
        elif event.type == InputEventType.MOUSE_BUTTON:
            var idx = Int(event.key_or_button)
            if idx >= 0 and idx < _MAX_MOUSE_BUTTONS:
                if event.action == GLFW_PRESS:
                    (self._mouse_pressed + idx)[]      = True
                    (self._mouse_just_pressed + idx)[]  = True
                elif event.action == GLFW_RELEASE:
                    (self._mouse_pressed + idx)[]       = False
                    (self._mouse_just_released + idx)[] = True
        elif event.type == InputEventType.CURSOR_POS:
            var old_x = self.mouse_x
            var old_y = self.mouse_y
            self.mouse_x = event.x
            self.mouse_y = event.y
            self.mouse_dx += event.x - old_x
            self.mouse_dy += event.y - old_y
        elif event.type == InputEventType.SCROLL:
            self.scroll_x += event.x
            self.scroll_y += event.y
