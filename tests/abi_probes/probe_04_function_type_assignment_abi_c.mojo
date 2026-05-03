"""Probe 04 (expected FAIL): assign def abi("C") to def function type variable."""

comptime CallbackType = def(UInt32, OpaquePointer[MutExternalOrigin], OpaquePointer[MutExternalOrigin]) -> None

def c_callback(status: UInt32, ud1: OpaquePointer[MutExternalOrigin], ud2: OpaquePointer[MutExternalOrigin]) abi("C"):
    _ = status
    _ = ud1
    _ = ud2


def main() raises:
    # Expected to fail: abi("C") and non-abi function types are not implicitly compatible.
    var cb: CallbackType = c_callback
    print(cb)
