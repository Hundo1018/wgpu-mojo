"""Probe 02 (expected FAIL): OpaquePointer ctor from def abi("C") callback."""


def c_callback(status: UInt32, ud1: OpaquePointer[MutExternalOrigin], ud2: OpaquePointer[MutExternalOrigin]) abi("C"):
    _ = status
    _ = ud1
    _ = ud2


def main() raises:
    # Expected to fail at compile-time: function is kgen.generator, not pointer.
    var ptr = OpaquePointer[MutExternalOrigin](c_callback)
    print(ptr)
