"""Phase 4 ABI probe: pass Mojo def callback into C and invoke it."""

from std.ffi import OwnedDLHandle
from std.testing import assert_equal


def triple(x: Int64) -> Int64:
    return x * Int64(3)


def plus_two(x: Int64) -> Int64:
    return x + Int64(2)


def main() raises:
    var lib = OwnedDLHandle("ffi/lib/libmojo_callback_probe.so")

    var a = lib.call["mojo_probe_invoke", Int64](triple, Int64(7))
    assert_equal(a, Int64(21))
    print("  PASS: callback triple")

    var b = lib.call["mojo_probe_invoke", Int64](plus_two, Int64(40))
    assert_equal(b, Int64(42))
    print("  PASS: callback plus_two")
