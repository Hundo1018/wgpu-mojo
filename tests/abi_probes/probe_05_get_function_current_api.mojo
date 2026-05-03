"""Probe 05 (expected PASS): current OwnedDLHandle.get_function API behavior."""

from std.ffi import OwnedDLHandle


def main() raises:
    var lib = OwnedDLHandle("ffi/lib/libwgpu_native.so")
    # In current stdlib, get_function[result_type](name) returns the symbol bitcasted to result_type.
    var fn_addr = lib.get_function[UInt64]("wgpuGetVersion")
    print("PASS: get_function[UInt64] returned symbol-sized value:", fn_addr)
