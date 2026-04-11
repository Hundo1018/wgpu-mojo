"""
tests/test_glfw_input.mojo — Integration test for GLFW input bindings.
Requires a display server (Wayland or X11) and libglfw.so.
Creates a hidden window, exercises polling APIs, and verifies the event queue
bridge loads and returns no spurious events.
"""

from std.testing import assert_equal, assert_true, assert_false
from wgpu._ffi.types import OpaquePtr
from rendercanvas.glfw import (
    GLFWLib, MojoInputEvent, InputEventType,
    GLFW_CLIENT_API, GLFW_NO_API, GLFW_RESIZABLE, GLFW_FALSE, GLFW_TRUE,
    GLFW_PRESS, GLFW_RELEASE,
    GLFW_KEY_A, GLFW_KEY_ESCAPE,
    GLFW_MOUSE_BUTTON_LEFT,
    GLFW_CURSOR,
)


def test_glfw_input_integration() raises:
    """Single GLFW lifecycle: polling APIs + event queue verification.

    NOTE: glfwInit()/glfwTerminate() can only be called once per process on
    Wayland (GTK types cannot be re-registered), so all checks share one
    init/terminate pair.
    """
    var glfw = GLFWLib()
    var ok = glfw.init()
    assert_equal(ok, GLFW_TRUE)

    glfw.window_hint(GLFW_CLIENT_API, GLFW_NO_API)
    glfw.window_hint(GLFW_RESIZABLE, GLFW_FALSE)

    # ── Part 1: Polling APIs ────────────────────────────────────────────
    var title = String("test_input")
    var title_bytes = title.as_bytes()
    var raw = title_bytes.unsafe_ptr().bitcast[NoneType]()
    var title_ptr = rebind[OpaquePtr](raw)
    var window = glfw.create_window(Int32(1), Int32(1), title_ptr)
    _ = title_bytes
    assert_true(Bool(window))

    # Exercise polling functions — should not crash
    var key_state = glfw.get_key(window, GLFW_KEY_A)
    assert_equal(key_state, GLFW_RELEASE)  # no key pressed

    var btn_state = glfw.get_mouse_button(window, GLFW_MOUSE_BUTTON_LEFT)
    assert_equal(btn_state, GLFW_RELEASE)

    var cx_p = alloc[Float64](1)
    var cy_p = alloc[Float64](1)
    glfw.get_cursor_pos(window, cx_p, cy_p)
    # Cursor pos is undefined for newly created window; just check it doesn't crash
    _ = cx_p[]
    _ = cy_p[]
    cx_p.free()
    cy_p.free()

    var cursor_mode = glfw.get_input_mode(window, GLFW_CURSOR)
    assert_true(cursor_mode > Int32(0))  # should be GLFW_CURSOR_NORMAL (0x34001)

    print("  PASS: polling_apis")

    # ── Part 2: Event queue (same window) ───────────────────────────────
    glfw.install_input_callbacks(window)

    # Poll once to let GLFW process — should produce no input events
    glfw.poll_events()

    var count = glfw.input_queue_count()
    # On some compositors a cursor_pos event may fire when window appears;
    # we just verify count is small (not a flood of spurious events)
    assert_true(count < Int32(10))

    # Drain any events that appeared
    var evt = alloc[MojoInputEvent](1)
    var drained = 0
    while Bool(glfw.poll_input_event(evt)):
        drained += 1
    evt.free()

    # After draining, queue must be empty
    assert_equal(glfw.input_queue_count(), Int32(0))

    print("  PASS: event_queue_empty")

    # ── Cleanup ─────────────────────────────────────────────────────────
    glfw.remove_input_callbacks(window)
    glfw.destroy_window(window)
    glfw.terminate()
    _ = glfw^


def main() raises:
    test_glfw_input_integration()
    print("All test_glfw_input tests passed")
