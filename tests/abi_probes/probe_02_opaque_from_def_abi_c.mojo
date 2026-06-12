"""Probe 02 (expected FAIL): OpaquePointer ctor from def abi("C") callback."""


def c_callback(status: UInt32, ud1: OpaquePointer[MutUntrackedOrigin], ud2: OpaquePointer[MutUntrackedOrigin]) abi("C"):
    _ = status
    _ = ud1
    _ = ud2


def main() raises:
    # Expected to fail at compile-time: function is kgen.generator, not pointer.
    var ptr = OpaquePointer[MutUntrackedOrigin](c_callback)
    print(ptr)
