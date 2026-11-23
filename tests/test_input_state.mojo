"""
Tests for InputState, fed through process_event. No window, no GPU.
"""

from std.testing import assert_true, assert_false, assert_equal
from wgpu.rendercanvas.glfw import MojoInputEvent
from wgpu.rendercanvas.input import InputState

comptime KEY: Int32 = 1
comptime BUTTON: Int32 = 2
comptime CURSOR: Int32 = 3
comptime AXIS: Int32 = 5
comptime RELEASE: Int32 = 0
comptime PRESS: Int32 = 1


def test_first_cursor_event_has_no_delta() raises:
    """The first cursor event places the cursor; only later ones move it."""
    var s = InputState()
    s.process_event(MojoInputEvent(CURSOR, 0, 0, 0, 640.0, 360.0))
    assert_equal(s.mouse_x, 640.0)
    assert_equal(s.mouse_y, 360.0)
    assert_equal(s.mouse_dx, 0.0)
    assert_equal(s.mouse_dy, 0.0)
    s.process_event(MojoInputEvent(CURSOR, 0, 0, 0, 652.0, 356.0))
    assert_equal(s.mouse_dx, 12.0)
    assert_equal(s.mouse_dy, -4.0)
    s.begin_frame()
    assert_equal(s.mouse_dx, 0.0)
    s.process_event(MojoInputEvent(CURSOR, 0, 0, 0, 650.0, 356.0))
    assert_equal(s.mouse_dx, -2.0)


def test_key_edges() raises:
    var s = InputState()
    s.process_event(MojoInputEvent(KEY, 65, PRESS, 0, 0.0, 0.0))
    assert_true(s.is_key_pressed(65) and s.is_key_just_pressed(65))
    s.begin_frame()
    assert_true(s.is_key_pressed(65))
    assert_false(s.is_key_just_pressed(65))


def test_release_all() raises:
    """Focus loss: every held key and button is released, with a release edge."""
    var s = InputState()
    s.process_event(MojoInputEvent(KEY, 65, PRESS, 0, 0.0, 0.0))
    s.process_event(MojoInputEvent(KEY, 87, PRESS, 0, 0.0, 0.0))
    s.process_event(MojoInputEvent(BUTTON, 0, PRESS, 0, 0.0, 0.0))
    s.begin_frame()
    s.release_all()
    assert_false(s.is_key_pressed(65))
    assert_false(s.is_key_pressed(87))
    assert_false(s.is_mouse_button_pressed(0))
    assert_true(s.is_key_just_released(65) and s.is_key_just_released(87))
    assert_true(s.is_mouse_button_just_released(0))
    assert_false(s.is_key_just_released(66))  # a key that was not held gets no edge
    s.begin_frame()
    assert_false(s.is_key_just_released(65))


def test_axis_events() raises:
    """AXIS events: latest value per (device, axis), held across frames."""
    var s = InputState()
    assert_equal(s.get_axis(0, 0), 0.0)
    s.process_event(MojoInputEvent(AXIS, 0, 0, 0, 0.3, 0.0))
    s.process_event(MojoInputEvent(AXIS, 1, 0, 0, -0.75, 0.0))
    s.process_event(MojoInputEvent(AXIS, 5, 1, 0, 1.0, 0.0))
    assert_equal(s.get_axis(0, 0), 0.3)
    assert_equal(s.get_axis(0, 1), -0.75)
    assert_equal(s.get_axis(1, 5), 1.0)
    assert_equal(s.get_axis(1, 0), 0.0)  # other device untouched
    s.process_event(MojoInputEvent(AXIS, 0, 0, 0, 1.0, 0.0))
    assert_equal(s.get_axis(0, 0), 1.0)  # latest value wins
    s.begin_frame()
    assert_equal(s.get_axis(0, 0), 1.0)  # holds across frames
    assert_equal(s.get_axis(0, 1), -0.75)
    assert_false(s.is_key_pressed(0))  # no key or button side effects
    assert_false(s.is_mouse_button_pressed(0))


def test_axis_out_of_range_ignored() raises:
    var s = InputState()
    s.process_event(MojoInputEvent(AXIS, 8, 0, 0, 0.5, 0.0))   # axis too high
    s.process_event(MojoInputEvent(AXIS, -1, 0, 0, 0.5, 0.0))  # axis negative
    s.process_event(MojoInputEvent(AXIS, 0, 4, 0, 0.5, 0.0))   # device too high
    s.process_event(MojoInputEvent(AXIS, 0, -1, 0, 0.5, 0.0))  # device negative
    for d in range(4):
        for a in range(8):
            assert_equal(s.get_axis(Int32(d), Int32(a)), 0.0)
    assert_equal(s.get_axis(8, 0), 0.0)
    assert_equal(s.get_axis(0, 8), 0.0)
    assert_equal(s.get_axis(-1, 0), 0.0)
    assert_equal(s.get_axis(0, -1), 0.0)
    s.process_event(MojoInputEvent(AXIS, 7, 3, 0, 0.5, 0.0))   # last valid slot
    assert_equal(s.get_axis(3, 7), 0.5)


def test_release_all_zeroes_axes() raises:
    var s = InputState()
    s.process_event(MojoInputEvent(AXIS, 0, 0, 0, 0.6, 0.0))
    s.process_event(MojoInputEvent(AXIS, 3, 2, 0, -0.2, 0.0))
    s.release_all()
    assert_equal(s.get_axis(0, 0), 0.0)
    assert_equal(s.get_axis(2, 3), 0.0)


def main() raises:
    test_first_cursor_event_has_no_delta()
    test_key_edges()
    test_release_all()
    test_axis_events()
    test_axis_out_of_range_ignored()
    test_release_all_zeroes_axes()
    print("test_input_state: ALL PASSED")
