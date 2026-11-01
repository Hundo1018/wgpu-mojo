"""Pins what `c_fn_ptr` yields on wasm64 (issue #13). Not a regular test: it is
built to a wasm module by scripts/check-wasm-fnptr.sh and driven by
fnptr_probe.mjs.

On wasm a C function pointer is an index into the module's function table, not
a code address. The host (emscripten / emdawnwebgpu) calls a callback through
that table, so this checks the value is such an index and that the table entry
behind it is the Mojo function.
"""

from wgpu._backend.wgpu_native.callbacks import c_fn_ptr, buffer_map_callback


def add1(x: Int32) abi("C") -> Int32:
    return x + 1


@export
def fnptr_add1() abi("C") -> UInt64:
    return UInt64(Int(c_fn_ptr(add1)))


@export
def fnptr_buffer_map_callback() abi("C") -> UInt64:
    # What the loader stores in WGPUBufferMapCallbackInfo.callback.
    return UInt64(Int(buffer_map_callback()))
