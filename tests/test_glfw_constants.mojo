"""
tests/test_glfw_constants.mojo — Verify GLFW constant values and MojoInputEvent layout.
No GPU or display server required.
"""

from std.testing import assert_equal, assert_true
from rendercanvas.glfw import (
    GLFW_TRUE, GLFW_FALSE,
    GLFW_CLIENT_API, GLFW_NO_API, GLFW_RESIZABLE,
    GLFW_PRESS, GLFW_RELEASE, GLFW_REPEAT,
    GLFW_MOUSE_BUTTON_LEFT, GLFW_MOUSE_BUTTON_RIGHT, GLFW_MOUSE_BUTTON_MIDDLE,
    GLFW_MOD_SHIFT, GLFW_MOD_CONTROL, GLFW_MOD_ALT, GLFW_MOD_SUPER,
    GLFW_CURSOR, GLFW_CURSOR_NORMAL, GLFW_CURSOR_HIDDEN, GLFW_CURSOR_DISABLED,
    GLFW_KEY_SPACE, GLFW_KEY_ESCAPE, GLFW_KEY_ENTER, GLFW_KEY_TAB,
    GLFW_KEY_BACKSPACE, GLFW_KEY_DELETE,
    GLFW_KEY_RIGHT, GLFW_KEY_LEFT, GLFW_KEY_DOWN, GLFW_KEY_UP,
    GLFW_KEY_A, GLFW_KEY_Z,
    GLFW_KEY_0, GLFW_KEY_9,
    GLFW_KEY_F1, GLFW_KEY_F12,
    GLFW_KEY_LEFT_SHIFT, GLFW_KEY_LEFT_CONTROL, GLFW_KEY_LEFT_ALT,
    GLFW_KEY_LAST,
    MojoInputEvent, InputEventType,
)


def test_window_constants() raises:
    assert_equal(GLFW_TRUE, Int32(1))
    assert_equal(GLFW_FALSE, Int32(0))
    assert_equal(GLFW_CLIENT_API, Int32(0x00022001))
    assert_equal(GLFW_NO_API, Int32(0))
    assert_equal(GLFW_RESIZABLE, Int32(0x00020003))


def test_action_constants() raises:
    assert_equal(GLFW_RELEASE, Int32(0))
    assert_equal(GLFW_PRESS, Int32(1))
    assert_equal(GLFW_REPEAT, Int32(2))


def test_mouse_button_constants() raises:
    assert_equal(GLFW_MOUSE_BUTTON_LEFT, Int32(0))
    assert_equal(GLFW_MOUSE_BUTTON_RIGHT, Int32(1))
    assert_equal(GLFW_MOUSE_BUTTON_MIDDLE, Int32(2))


def test_modifier_constants() raises:
    assert_equal(GLFW_MOD_SHIFT, Int32(0x0001))
    assert_equal(GLFW_MOD_CONTROL, Int32(0x0002))
    assert_equal(GLFW_MOD_ALT, Int32(0x0004))
    assert_equal(GLFW_MOD_SUPER, Int32(0x0008))


def test_cursor_mode_constants() raises:
    assert_equal(GLFW_CURSOR, Int32(0x00033001))
    assert_equal(GLFW_CURSOR_NORMAL, Int32(0x00034001))
    assert_equal(GLFW_CURSOR_HIDDEN, Int32(0x00034002))
    assert_equal(GLFW_CURSOR_DISABLED, Int32(0x00034003))


def test_key_code_ranges() raises:
    # Printable ASCII keys
    assert_equal(GLFW_KEY_SPACE, Int32(32))
    assert_equal(GLFW_KEY_0, Int32(48))
    assert_equal(GLFW_KEY_9, Int32(57))
    assert_equal(GLFW_KEY_A, Int32(65))
    assert_equal(GLFW_KEY_Z, Int32(90))

    # Function keys
    assert_equal(GLFW_KEY_ESCAPE, Int32(256))
    assert_equal(GLFW_KEY_ENTER, Int32(257))
    assert_equal(GLFW_KEY_TAB, Int32(258))
    assert_equal(GLFW_KEY_BACKSPACE, Int32(259))
    assert_equal(GLFW_KEY_DELETE, Int32(261))

    # Arrow keys
    assert_equal(GLFW_KEY_RIGHT, Int32(262))
    assert_equal(GLFW_KEY_LEFT, Int32(263))
    assert_equal(GLFW_KEY_DOWN, Int32(264))
    assert_equal(GLFW_KEY_UP, Int32(265))

    # F-keys
    assert_equal(GLFW_KEY_F1, Int32(290))
    assert_equal(GLFW_KEY_F12, Int32(301))

    # Modifier keys
    assert_equal(GLFW_KEY_LEFT_SHIFT, Int32(340))
    assert_equal(GLFW_KEY_LEFT_CONTROL, Int32(341))
    assert_equal(GLFW_KEY_LEFT_ALT, Int32(342))

    assert_equal(GLFW_KEY_LAST, Int32(348))


def test_input_event_type_constants() raises:
    assert_equal(InputEventType.KEY, Int32(1))
    assert_equal(InputEventType.MOUSE_BUTTON, Int32(2))
    assert_equal(InputEventType.CURSOR_POS, Int32(3))
    assert_equal(InputEventType.SCROLL, Int32(4))


def test_mojo_input_event_construction() raises:
    var evt = MojoInputEvent(
        type=Int32(1),
        key_or_button=Int32(65),
        action=Int32(1),
        mods=Int32(0),
        x=0.0,
        y=0.0,
    )
    assert_equal(evt.type, Int32(1))
    assert_equal(evt.key_or_button, Int32(65))
    assert_equal(evt.action, Int32(1))
    assert_equal(evt.mods, Int32(0))
    assert_equal(evt.x, 0.0)
    assert_equal(evt.y, 0.0)


def main() raises:
    test_window_constants()
    print("  PASS: test_window_constants")
    test_action_constants()
    print("  PASS: test_action_constants")
    test_mouse_button_constants()
    print("  PASS: test_mouse_button_constants")
    test_modifier_constants()
    print("  PASS: test_modifier_constants")
    test_cursor_mode_constants()
    print("  PASS: test_cursor_mode_constants")
    test_key_code_ranges()
    print("  PASS: test_key_code_ranges")
    test_input_event_type_constants()
    print("  PASS: test_input_event_type_constants")
    test_mojo_input_event_construction()
    print("  PASS: test_mojo_input_event_construction")
    print("All test_glfw_constants tests passed (8)")
