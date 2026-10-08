"""wgpu._backend.wgpu_native.callbacks — Mojo implementations of wgpu-native's
async completion callbacks.

wgpu-native reports every async result (adapter, device, buffer map, queue
done, error scope) through a C function pointer stored in a `*CallbackInfo`
struct that is passed BY VALUE. Until Mojo 1.1.0 both halves needed C:
`def` values could not be turned into storable pointers, and >16-byte structs
did not survive `OwnedDLHandle.call` by value. ffi/wgpu_callbacks.c supplied
the callbacks and a pointer-taking wrapper per entry point. Both limits are
gone on 1.1.0 (tests/test_callback_abi.mojo pins the exact ABI shapes on every
CI platform), so the callbacks live here.

Each callback writes into the `_*Result` struct its caller passes as
`userdata1`. Signatures must match the header typedefs named in the
`# C typedef:` comments; scripts/check_signatures.py compares them.
"""

from std.sys import size_of
from wgpu._backend.wgpu_native.alloc_guard import raw_alloc
from wgpu._backend.wgpu_native.nulls import null_opaque
from wgpu._backend.wgpu_native.structs import WGPUStringView
from wgpu._backend.wgpu_native.types import (
    WGPUAdapterHandle, WGPUDeviceHandle, WGPU_STRLEN,
)


def c_fn_ptr[F: TrivialRegisterPassable](f: F) -> OpaquePointer[MutUntrackedOrigin]:
    """The address of an `abi("C")` function, for a C struct's callback field.

    `rebind` refuses the conversion (a function value is a `!kgen.generator`,
    not a `!kgen.pointer`), but the value itself is the bare code address, so it
    is read back through memory instead.
    """
    comptime assert size_of[F]() == size_of[OpaquePointer[MutUntrackedOrigin]](), (
        "c_fn_ptr takes an abi(\"C\") function value"
    )
    var slot = f
    return Pointer(to=slot).unsafe_bitcast[OpaquePointer[MutUntrackedOrigin]]()[]


# ---------------------------------------------------------------------------
# Result structs, written through userdata1
# ---------------------------------------------------------------------------

@fieldwise_init
struct _AdapterResult(TrivialRegisterPassable):
    var adapter: WGPUAdapterHandle
    var status: UInt32


@fieldwise_init
struct _DeviceResult(TrivialRegisterPassable):
    var device: WGPUDeviceHandle
    var status: UInt32


@fieldwise_init
struct _MapResult(TrivialRegisterPassable):
    var status: UInt32


@fieldwise_init
struct _WorkDoneResult(TrivialRegisterPassable):
    var status: UInt32


@fieldwise_init
struct _PopErrorResult(TrivialRegisterPassable):
    """`message_data` is a heap copy the caller owns (null when empty): the
    view wgpu-native passes is only valid until the callback returns."""
    var status: UInt32
    var type: UInt32
    var message_data: OpaquePointer[MutUntrackedOrigin]
    var message_len: UInt


# ---------------------------------------------------------------------------
# Callbacks
# ---------------------------------------------------------------------------

# C typedef: WGPURequestAdapterCallback
def _on_request_adapter(
    status: UInt32,
    adapter: WGPUAdapterHandle,
    message: WGPUStringView,
    userdata1: OpaquePointer[MutUntrackedOrigin],
    userdata2: OpaquePointer[MutUntrackedOrigin],
) abi("C"):
    userdata1.unsafe_bitcast[_AdapterResult]()[] = _AdapterResult(adapter, status)


# C typedef: WGPURequestDeviceCallback
def _on_request_device(
    status: UInt32,
    device: WGPUDeviceHandle,
    message: WGPUStringView,
    userdata1: OpaquePointer[MutUntrackedOrigin],
    userdata2: OpaquePointer[MutUntrackedOrigin],
) abi("C"):
    userdata1.unsafe_bitcast[_DeviceResult]()[] = _DeviceResult(device, status)


# C typedef: WGPUBufferMapCallback
def _on_buffer_map(
    status: UInt32,
    message: WGPUStringView,
    userdata1: OpaquePointer[MutUntrackedOrigin],
    userdata2: OpaquePointer[MutUntrackedOrigin],
) abi("C"):
    userdata1.unsafe_bitcast[_MapResult]()[] = _MapResult(status)


# C typedef: WGPUQueueWorkDoneCallback
def _on_queue_work_done(
    status: UInt32,
    message: WGPUStringView,
    userdata1: OpaquePointer[MutUntrackedOrigin],
    userdata2: OpaquePointer[MutUntrackedOrigin],
) abi("C"):
    userdata1.unsafe_bitcast[_WorkDoneResult]()[] = _WorkDoneResult(status)


# C typedef: WGPUPopErrorScopeCallback
def _on_pop_error_scope(
    status: UInt32,
    type: UInt32,
    message: WGPUStringView,
    userdata1: OpaquePointer[MutUntrackedOrigin],
    userdata2: OpaquePointer[MutUntrackedOrigin],
) abi("C"):
    var src = message.data.unsafe_bitcast[UInt8]()
    var n = message.length if Int(message.data) != 0 else UInt(0)
    if n == WGPU_STRLEN:
        n = 0
        while src[unsafe_offset=Int(n)] != 0:
            n += 1
    var copy = null_opaque()
    if n > 0:
        var dst = raw_alloc[UInt8](Int(n))
        for i in range(Int(n)):
            dst[unsafe_offset=i] = src[unsafe_offset=i]
        copy = dst.unsafe_bitcast[NoneType]()
    userdata1.unsafe_bitcast[_PopErrorResult]()[] = _PopErrorResult(status, type, copy, n)


# Addresses for the `callback` field of each *CallbackInfo struct.
def request_adapter_callback() -> OpaquePointer[MutUntrackedOrigin]:
    return c_fn_ptr(_on_request_adapter)


def request_device_callback() -> OpaquePointer[MutUntrackedOrigin]:
    return c_fn_ptr(_on_request_device)


def buffer_map_callback() -> OpaquePointer[MutUntrackedOrigin]:
    return c_fn_ptr(_on_buffer_map)


def queue_work_done_callback() -> OpaquePointer[MutUntrackedOrigin]:
    return c_fn_ptr(_on_queue_work_done)


def pop_error_scope_callback() -> OpaquePointer[MutUntrackedOrigin]:
    return c_fn_ptr(_on_pop_error_scope)
