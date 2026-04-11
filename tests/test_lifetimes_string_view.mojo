"""Validate origin-aware borrowed string view helpers."""

from std.testing import assert_equal, assert_true
from std.sys import align_of
from wgpu._ffi import WGPUBorrowedStringView, str_to_borrowed_sv


def test_borrowed_view_roundtrip() raises:
    var label = String("compute_main")
    var borrowed = str_to_borrowed_sv(label)
    var raw = borrowed.to_ffi()
    assert_equal(raw.length, UInt(len(label.as_bytes())))


def test_borrowed_view_alignment() raises:
    # Alignment is encoded on type so stack/heap allocations are consistent.
    assert_true(align_of[WGPUBorrowedStringView[ImmutExternalOrigin]]() >= 16)


def main() raises:
    test_borrowed_view_roundtrip()
    print("  PASS: test_borrowed_view_roundtrip")
    test_borrowed_view_alignment()
    print("  PASS: test_borrowed_view_alignment")
