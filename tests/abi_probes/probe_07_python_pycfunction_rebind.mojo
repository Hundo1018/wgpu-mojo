"""Probe 07 (expected FAIL): PyCFunction-style rebind to OpaquePointer.

This preserves a reproducer for potential stdlib/compiler issue reports.
"""

from std.python._cpython import PyObjectPtr

comptime PyCFunctionLike = def(PyObjectPtr, PyObjectPtr) -> PyObjectPtr


def my_c_func(py_self: PyObjectPtr, args: PyObjectPtr) -> PyObjectPtr:
    _ = py_self
    _ = args
    return {}


def main() raises:
    # Expected to fail with kgen.generator vs kgen.pointer mismatch.
    var f: PyCFunctionLike = my_c_func
    var raw = rebind[OpaquePointer[MutExternalOrigin]](f)
    print(raw)
