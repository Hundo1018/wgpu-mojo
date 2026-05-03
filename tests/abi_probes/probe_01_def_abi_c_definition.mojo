"""Probe 01 (expected PASS): def with abi("C") compiles."""

def c_callback(status: UInt32, ud1: OpaquePointer[MutExternalOrigin], ud2: OpaquePointer[MutExternalOrigin]) abi("C"):
    _ = status
    _ = ud1
    _ = ud2


def main() raises:
    print("PASS: def abi(\"C\") definition compiled")
