"""Probe 05 (expected PASS): current OwnedDLHandle.get_function API behavior."""

from std.ffi import OwnedDLHandle


def main() raises:
    var lib = OwnedDLHandle("ffi/lib/libwgpu_native.so")
    # On Mojo 1.1.0, get_function[result_type](name) returns an opaque
    # `_DLCallable` (not Writable, so it cannot be printed). Resolution of the
    # symbol is the behavior under test: a missing symbol would raise here.
    _ = lib.get_function[UInt64]("wgpuGetVersion")
    print("PASS: get_function[UInt64] resolved wgpuGetVersion")
