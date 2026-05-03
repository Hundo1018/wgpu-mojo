"""Phase 1 strong-handle groundwork tests."""

from std.testing import assert_true, assert_false
from wgpu._ffi import (
    BufferHandle, TextureHandle, DeviceHandle, CommandBufferHandle,
)


def test_null_constructors() raises:
    var b = BufferHandle.null()
    var t = TextureHandle.null()
    var d = DeviceHandle.null()
    assert_true(b.raw == OpaquePointer[MutExternalOrigin](unsafe_from_address=0))
    assert_true(t.raw == OpaquePointer[MutExternalOrigin](unsafe_from_address=0))
    assert_true(d.raw == OpaquePointer[MutExternalOrigin](unsafe_from_address=0))


def test_wrap_raw_pointer() raises:
    var raw = OpaquePointer[MutExternalOrigin](unsafe_from_address=0)
    var cmd = CommandBufferHandle(raw)
    assert_true(cmd.raw == OpaquePointer[MutExternalOrigin](unsafe_from_address=0))


def main() raises:
    test_null_constructors()
    print("  PASS: test_null_constructors")
    test_wrap_raw_pointer()
    print("  PASS: test_wrap_raw_pointer")
