"""Phase 1 strong-handle groundwork tests."""

from std.testing import assert_false
from wgpu._ffi import (
    OpaquePtr,
    BufferHandle, TextureHandle, DeviceHandle, CommandBufferHandle,
)


def test_null_constructors() raises:
    var b = BufferHandle.null()
    var t = TextureHandle.null()
    var d = DeviceHandle.null()
    assert_false(Bool(b.raw))
    assert_false(Bool(t.raw))
    assert_false(Bool(d.raw))


def test_wrap_raw_pointer() raises:
    var raw = OpaquePtr()
    var cmd = CommandBufferHandle(raw)
    assert_false(Bool(cmd.raw))


def main() raises:
    test_null_constructors()
    print("  PASS: test_null_constructors")
    test_wrap_raw_pointer()
    print("  PASS: test_wrap_raw_pointer")
