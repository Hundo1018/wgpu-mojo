"""Probe 03 (expected FAIL): rebind def abi("C") callback to OpaquePointer."""

def c_callback(status: UInt32, ud1: OpaquePointer[MutExternalOrigin], ud2: OpaquePointer[MutExternalOrigin]) abi("C"):
    _ = status
    _ = ud1
    _ = ud2


def main() raises:
    # Expected to fail: rebind input is !kgen.generator, not !kgen.pointer.
    var ptr = rebind[OpaquePointer[MutExternalOrigin]](c_callback)
    print(ptr)
