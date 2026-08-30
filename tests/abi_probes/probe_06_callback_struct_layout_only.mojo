"""Probe 06 (expected PASS): callback-info struct accepts OpaquePointer fields.

This only validates struct construction, not Mojo-function-to-pointer conversion.
"""

from wgpu._ffi.structs import WGPURequestAdapterCallbackInfo
from wgpu._ffi.types import WGPUCallbackMode


def _dummy_ptr(addr: Int) -> OpaquePointer[MutUntrackedOrigin]:
    return rebind[OpaquePointer[MutUntrackedOrigin]](
        Pointer[NoneType, MutUntrackedOrigin](unsafe_from_address=addr)
    )


def main() raises:
    # OpaquePointer/Pointer are non-nullable in current Mojo nightly;
    # this probe only validates struct construction, so a non-null dummy is fine.
    var p = _dummy_ptr(1)
    var info = WGPURequestAdapterCallbackInfo(
        p,
        WGPUCallbackMode.AllowSpontaneous,
        p,
        p,
        p,
    )
    print("PASS: callback-info struct constructed, callback field:", info.callback)
