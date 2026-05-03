"""Probe 06 (expected PASS): callback-info struct accepts OpaquePointer fields.

This only validates struct construction, not Mojo-function-to-pointer conversion.
"""

from wgpu._ffi.structs import WGPURequestAdapterCallbackInfo
from wgpu._ffi.types import WGPUCallbackMode


def main() raises:
    var null_ptr = OpaquePointer[MutExternalOrigin](unsafe_from_address=0)
    var info = WGPURequestAdapterCallbackInfo(
        null_ptr,
        WGPUCallbackMode.AllowSpontaneous,
        null_ptr,
        null_ptr,
        null_ptr,
    )
    print("PASS: callback-info struct constructed, callback field:", info.callback)
