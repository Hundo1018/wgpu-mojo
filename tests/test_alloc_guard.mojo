"""Tests/test_alloc_guard.mojo — Unit tests for scoped FFI allocations."""

from std.testing import assert_equal, assert_true
from wgpu._ffi.alloc_guard import AllocGuard


def test_alloc_guard_basic() raises:
    with AllocGuard[Int](3) as p:
        p[0] = 11
        p[1] = 22
        p[2] = 33
        assert_equal(p[0], 11)
        assert_equal(p[1], 22)
        assert_equal(p[2], 33)


def _raise_inside_guard() raises:
    with AllocGuard[Int](1) as p:
        p[0] = 7
        raise Error("expected alloc_guard test error")


def test_alloc_guard_error_path() raises:
    var saw_error = False
    try:
        _raise_inside_guard()
    except e:
        saw_error = True
        assert_true("alloc_guard" in String(e))
    assert_true(saw_error)


def main() raises:
    test_alloc_guard_basic()
    print("  PASS: test_alloc_guard_basic")
    test_alloc_guard_error_path()
    print("  PASS: test_alloc_guard_error_path")
    print("test_alloc_guard: ALL PASSED")
