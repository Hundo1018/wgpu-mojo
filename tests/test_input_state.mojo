"""
tests/test_input_state.mojo — Unit tests for InputState logic.
No GPU or display server required. Tests use manually constructed events.
"""

from std.testing import assert_equal, assert_true, assert_false
from rendercanvas.glfw import (
    MojoInputEvent, InputEventType,
    GLFW_PRESS, GLFW_RELEASE, GLFW_REPEAT,
    GLFW_KEY_A, GLFW_KEY_ESCAPE,
    GLFW_MOUSE_BUTTON_LEFT, GLFW_MOUSE_BUTTON_RIGHT,
)
from rendercanvas.input import InputState


def _key_event(key: Int32, action: Int32, mods: Int32 = Int32(0)) -> MojoInputEvent:
    return MojoInputEvent(
        type=InputEventType.KEY,
        key_or_button=key,
        action=action,
        mods=mods,
        x=0.0, y=0.0,
    )


def _mouse_button_event(button: Int32, action: Int32, mods: Int32 = Int32(0)) -> MojoInputEvent:
    return MojoInputEvent(
        type=InputEventType.MOUSE_BUTTON,
        key_or_button=button,
        action=action,
        mods=mods,
        x=0.0, y=0.0,
    )


def _cursor_event(x: Float64, y: Float64) -> MojoInputEvent:
    return MojoInputEvent(
        type=InputEventType.CURSOR_POS,
        key_or_button=Int32(0),
        action=Int32(0),
        mods=Int32(0),
        x=x, y=y,
    )


def _scroll_event(dx: Float64, dy: Float64) -> MojoInputEvent:
    return MojoInputEvent(
        type=InputEventType.SCROLL,
        key_or_button=Int32(0),
        action=Int32(0),
        mods=Int32(0),
        x=dx, y=dy,
    )


def test_initial_state() raises:
    """All keys/buttons unpressed, cursor at origin, no scroll."""
    var s = InputState()
    assert_false(s.is_key_pressed(GLFW_KEY_A))
    assert_false(s.is_key_just_pressed(GLFW_KEY_A))
    assert_false(s.is_key_just_released(GLFW_KEY_A))
    assert_false(s.is_mouse_button_pressed(GLFW_MOUSE_BUTTON_LEFT))
    assert_equal(s.mouse_x, 0.0)
    assert_equal(s.mouse_y, 0.0)
    assert_equal(s.mouse_dx, 0.0)
    assert_equal(s.mouse_dy, 0.0)
    assert_equal(s.scroll_x, 0.0)
    assert_equal(s.scroll_y, 0.0)
    _ = s^


def test_key_press_and_release() raises:
    """Press → just_pressed + pressed; Release → just_released + not pressed."""
    var s = InputState()

    # Frame 1: Press A
    s.begin_frame()
    s.process_event(_key_event(GLFW_KEY_A, GLFW_PRESS))
    assert_true(s.is_key_pressed(GLFW_KEY_A))
    assert_true(s.is_key_just_pressed(GLFW_KEY_A))
    assert_false(s.is_key_just_released(GLFW_KEY_A))

    # Frame 2: No events — still pressed, but not just_pressed
    s.begin_frame()
    assert_true(s.is_key_pressed(GLFW_KEY_A))
    assert_false(s.is_key_just_pressed(GLFW_KEY_A))
    assert_false(s.is_key_just_released(GLFW_KEY_A))

    # Frame 3: Release A
    s.begin_frame()
    s.process_event(_key_event(GLFW_KEY_A, GLFW_RELEASE))
    assert_false(s.is_key_pressed(GLFW_KEY_A))
    assert_false(s.is_key_just_pressed(GLFW_KEY_A))
    assert_true(s.is_key_just_released(GLFW_KEY_A))

    # Frame 4: No events — clean state
    s.begin_frame()
    assert_false(s.is_key_pressed(GLFW_KEY_A))
    assert_false(s.is_key_just_pressed(GLFW_KEY_A))
    assert_false(s.is_key_just_released(GLFW_KEY_A))

    _ = s^


def test_key_repeat() raises:
    """REPEAT keeps pressed=True but does NOT set just_pressed."""
    var s = InputState()

    # Press first
    s.begin_frame()
    s.process_event(_key_event(GLFW_KEY_A, GLFW_PRESS))
    assert_true(s.is_key_just_pressed(GLFW_KEY_A))

    # Repeat
    s.begin_frame()
    s.process_event(_key_event(GLFW_KEY_A, GLFW_REPEAT))
    assert_true(s.is_key_pressed(GLFW_KEY_A))
    assert_false(s.is_key_just_pressed(GLFW_KEY_A))
    assert_false(s.is_key_just_released(GLFW_KEY_A))

    _ = s^


def test_mouse_button_press_release() raises:
    var s = InputState()

    s.begin_frame()
    s.process_event(_mouse_button_event(GLFW_MOUSE_BUTTON_LEFT, GLFW_PRESS))
    assert_true(s.is_mouse_button_pressed(GLFW_MOUSE_BUTTON_LEFT))
    assert_true(s.is_mouse_button_just_pressed(GLFW_MOUSE_BUTTON_LEFT))
    assert_false(s.is_mouse_button_pressed(GLFW_MOUSE_BUTTON_RIGHT))

    s.begin_frame()
    s.process_event(_mouse_button_event(GLFW_MOUSE_BUTTON_LEFT, GLFW_RELEASE))
    assert_false(s.is_mouse_button_pressed(GLFW_MOUSE_BUTTON_LEFT))
    assert_true(s.is_mouse_button_just_released(GLFW_MOUSE_BUTTON_LEFT))

    _ = s^


def test_cursor_position_and_delta() raises:
    var s = InputState()

    # First cursor event — delta from (0,0) to (100,200)
    s.begin_frame()
    s.process_event(_cursor_event(100.0, 200.0))
    assert_equal(s.mouse_x, 100.0)
    assert_equal(s.mouse_y, 200.0)
    assert_equal(s.mouse_dx, 100.0)
    assert_equal(s.mouse_dy, 200.0)

    # Next frame: cursor moves to (150, 180)
    s.begin_frame()
    s.process_event(_cursor_event(150.0, 180.0))
    assert_equal(s.mouse_x, 150.0)
    assert_equal(s.mouse_y, 180.0)
    assert_equal(s.mouse_dx, 50.0)
    assert_equal(s.mouse_dy, -20.0)

    # Frame with no cursor events — delta should be zero
    s.begin_frame()
    assert_equal(s.mouse_dx, 0.0)
    assert_equal(s.mouse_dy, 0.0)
    # Position should remain
    assert_equal(s.mouse_x, 150.0)
    assert_equal(s.mouse_y, 180.0)

    _ = s^


def test_scroll_accumulation() raises:
    var s = InputState()

    s.begin_frame()
    s.process_event(_scroll_event(0.0, 3.0))
    s.process_event(_scroll_event(0.0, -1.0))
    assert_equal(s.scroll_x, 0.0)
    assert_equal(s.scroll_y, 2.0)

    # Next frame: scroll resets
    s.begin_frame()
    assert_equal(s.scroll_x, 0.0)
    assert_equal(s.scroll_y, 0.0)

    _ = s^


def test_out_of_range_key() raises:
    """Querying out-of-range key codes returns False (no crash)."""
    var s = InputState()
    assert_false(s.is_key_pressed(Int32(-1)))
    assert_false(s.is_key_pressed(Int32(999)))
    assert_false(s.is_mouse_button_pressed(Int32(-1)))
    assert_false(s.is_mouse_button_pressed(Int32(99)))
    _ = s^


def test_multiple_keys_same_frame() raises:
    """Multiple keys pressed in the same frame."""
    var s = InputState()

    s.begin_frame()
    s.process_event(_key_event(GLFW_KEY_A, GLFW_PRESS))
    s.process_event(_key_event(GLFW_KEY_ESCAPE, GLFW_PRESS))

    assert_true(s.is_key_pressed(GLFW_KEY_A))
    assert_true(s.is_key_pressed(GLFW_KEY_ESCAPE))
    assert_true(s.is_key_just_pressed(GLFW_KEY_A))
    assert_true(s.is_key_just_pressed(GLFW_KEY_ESCAPE))

    _ = s^


def main() raises:
    test_initial_state()
    print("  PASS: test_initial_state")
    test_key_press_and_release()
    print("  PASS: test_key_press_and_release")
    test_key_repeat()
    print("  PASS: test_key_repeat")
    test_mouse_button_press_release()
    print("  PASS: test_mouse_button_press_release")
    test_cursor_position_and_delta()
    print("  PASS: test_cursor_position_and_delta")
    test_scroll_accumulation()
    print("  PASS: test_scroll_accumulation")
    test_out_of_range_key()
    print("  PASS: test_out_of_range_key")
    test_multiple_keys_same_frame()
    print("  PASS: test_multiple_keys_same_frame")
    print("All test_input_state tests passed (8)")
