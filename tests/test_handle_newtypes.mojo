"""Phase 1 strong-handle groundwork tests."""

from wgpu._ffi.nulls import null_opaque, null_ptr, null_any_ptr
from std.testing import assert_true, assert_false
from wgpu._ffi import (
    BufferHandle, TextureHandle, DeviceHandle, CommandBufferHandle,
)


def test_null_constructors() raises:
    var b = BufferHandle.null()
    var t = TextureHandle.null()
    var d = DeviceHandle.null()
    assert_true(b.raw == null_opaque())
    assert_true(t.raw == null_opaque())
    assert_true(d.raw == null_opaque())


def test_wrap_raw_pointer() raises:
    var raw = null_opaque()
    var cmd = CommandBufferHandle(raw)
    assert_true(cmd.raw == null_opaque())


def main() raises:
    test_null_constructors()
    print("  PASS: test_null_constructors")
    test_wrap_raw_pointer()
    print("  PASS: test_wrap_raw_pointer")
