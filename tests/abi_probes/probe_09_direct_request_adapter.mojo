"""Probe 09: Direct wgpuInstanceRequestAdapter call without struct-by-pointer wrapper.

Tests whether WGPURequestAdapterCallbackInfo (40 bytes) can be passed by value
directly to wgpuInstanceRequestAdapter via DLHandle.call, without the
wgpu_mojo_instance_request_adapter C bridge wrapper.

EXPECTED: FAIL (struct-by-value ABI via DLHandle.call is still broken for
>16-byte structs on x86_64 System V ABI even in Mojo nightly 1.0.0b2 with
abi("C") — the abi("C") fix applies to callback definitions, not to the
DLHandle.call caller side).

The callback fn-ptr is sourced from libwgpu_mojo_cb.so (via getter) so that
only the struct-by-value ABI is under test here.
"""

from std.ffi import OwnedDLHandle
from wgpu._ffi.alloc_guard import AllocGuard
from wgpu._ffi.types import (
    WGPUInstanceHandle, WGPUAdapterHandle, WGPUCallbackMode,
    WGPURequestAdapterStatus,
)
from wgpu._ffi.structs import (
    WGPUStringView, WGPUFuture,
    WGPURequestAdapterOptions, WGPURequestAdapterCallbackInfo,
)


@fieldwise_init
struct _AdapterResult(TrivialRegisterPassable):
    var adapter: WGPUAdapterHandle
    var status: UInt32


def main() raises:
    var wgpu = OwnedDLHandle("ffi/lib/libwgpu_native.so")
    var cb_lib = OwnedDLHandle("ffi/lib/libwgpu_mojo_cb.so")

    # Create instance — descriptor is nullable
    var instance = wgpu.call["wgpuCreateInstance", WGPUInstanceHandle](
        OpaquePointer[MutExternalOrigin](unsafe_from_address=0)
    )
    if UInt(Int(instance)) == 0:
        raise Error("wgpuCreateInstance returned null")

    # Get C callback pointer from existing bridge (not under test here)
    var cb_ptr = cb_lib.call["wgpu_mojo_get_adapter_callback",
                              OpaquePointer[MutExternalOrigin]]()

    with AllocGuard[_AdapterResult](1) as result_ptr:
        result_ptr[] = _AdapterResult(
            WGPUAdapterHandle(unsafe_from_address=0),
            UInt32(99),  # sentinel
        )

        var cb_info = WGPURequestAdapterCallbackInfo(
            OpaquePointer[MutExternalOrigin](unsafe_from_address=0),  # next_in_chain
            WGPUCallbackMode.AllowSpontaneous,
            cb_ptr,
            result_ptr.bitcast[NoneType](),
            OpaquePointer[MutExternalOrigin](unsafe_from_address=0),  # userdata2
        )

        # Attempt: call wgpuInstanceRequestAdapter directly with struct by value.
        # This is expected to crash/fail because DLHandle.call does not correctly
        # spill 40-byte TrivialRegisterPassable structs to the stack per SysV ABI.
        _ = wgpu.call["wgpuInstanceRequestAdapter", WGPUFuture](
            instance,
            OpaquePointer[MutExternalOrigin](unsafe_from_address=0),  # options=NULL
            cb_info,
        )
        wgpu.call["wgpuInstanceProcessEvents"](instance)

        if result_ptr[].status == UInt32(99):
            raise Error("FAIL: callback never invoked (struct-by-value ABI broken)")
        if result_ptr[].status != UInt32(WGPURequestAdapterStatus.Success):
            raise Error("FAIL: adapter request failed, status=" + String(result_ptr[].status))

        print("PASS: struct-by-value ABI works — no bridge wrapper needed, adapter=",
              Int(result_ptr[].adapter))
        wgpu.call["wgpuAdapterRelease"](result_ptr[].adapter)

    wgpu.call["wgpuInstanceRelease"](instance)

