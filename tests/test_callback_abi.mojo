"""ABI pins for Mojo callbacks called from C: as call arguments, and stored
by address in a by-value CallbackInfo struct (how wgpu-native takes them)."""

from std.ffi import OwnedDLHandle
from std.testing import assert_equal, assert_true
from wgpu._backend.wgpu_native.callbacks import (
    _AdapterResult, _PopErrorResult,
    request_adapter_callback, pop_error_scope_callback,
)
from wgpu._backend.wgpu_native.nulls import null_opaque


@fieldwise_init
struct _CallbackInfo40(TrivialRegisterPassable):
    var next_in_chain: OpaquePointer[MutUntrackedOrigin]
    var mode: UInt32
    var callback: OpaquePointer[MutUntrackedOrigin]
    var userdata1: OpaquePointer[MutUntrackedOrigin]
    var userdata2: OpaquePointer[MutUntrackedOrigin]


def _addr[T: AnyType](p: Pointer[T, ...]) -> OpaquePointer[MutUntrackedOrigin]:
    return OpaquePointer[MutUntrackedOrigin](unsafe_from_address=Int(p))


def triple(x: Int64) -> Int64:
    return x * Int64(3)


def plus_two(x: Int64) -> Int64:
    return x + Int64(2)


# ---------------------------------------------------------------
# Extended probes: mimic wgpu adapter callback signature
# ---------------------------------------------------------------

# Matches the C AdapterResult struct layout
@fieldwise_init
struct _ProbeAdapterResult(TrivialRegisterPassable):
    var handle: UInt64
    var status: UInt32


# Probe A: callback with scalars only (StringView decomposed into ptr+len)
def mojo_scalar_adapter_cb(
    status: UInt32,
    adapter: OpaquePointer[MutUntrackedOrigin],
    msg_data: OpaquePointer[MutUntrackedOrigin],
    msg_len: UInt64,
    ud1: OpaquePointer[MutUntrackedOrigin],
    ud2: OpaquePointer[MutUntrackedOrigin],
):
    """Scalar-only callback: receive StringView as two separate args."""
    var result_p = rebind[Pointer[_ProbeAdapterResult, MutUntrackedOrigin]](ud1)
    result_p[] = _ProbeAdapterResult(UInt64(Int(adapter)), status)


# Probe B: callback with 16-byte struct by value (WGPUStringView equivalent)
@fieldwise_init
struct _StringView16(TrivialRegisterPassable):
    var data: OpaquePointer[MutUntrackedOrigin]
    var length: UInt64


def mojo_struct_adapter_cb(
    status: UInt32,
    adapter: OpaquePointer[MutUntrackedOrigin],
    msg: _StringView16,
    ud1: OpaquePointer[MutUntrackedOrigin],
    ud2: OpaquePointer[MutUntrackedOrigin],
):
    """Struct-by-value callback: receive 16-byte StringView as single param."""
    var result_p = rebind[Pointer[_ProbeAdapterResult, MutUntrackedOrigin]](ud1)
    result_p[] = _ProbeAdapterResult(UInt64(Int(adapter)), status)


def main() raises:
    var lib = OwnedDLHandle("ffi/lib/libmojo_callback_probe.so")

    # ------ Original scalar tests ------
    var a = lib.call["mojo_probe_invoke", Int64](triple, Int64(7))
    assert_equal(a, Int64(21))
    print("  PASS: callback triple")

    var b = lib.call["mojo_probe_invoke", Int64](plus_two, Int64(40))
    assert_equal(b, Int64(42))
    print("  PASS: callback plus_two")

    # ------ Extended: scalar-decomposed StringView ------
    var handle_s = lib.call["mojo_probe_scalar_result_handle", UInt64](mojo_scalar_adapter_cb)
    assert_equal(handle_s, UInt64(0xBEEF))
    print("  PASS: scalar callback handle =", hex(handle_s))

    var status_s = lib.call["mojo_probe_scalar_result_status", UInt32](mojo_scalar_adapter_cb)
    assert_equal(status_s, UInt32(42))
    print("  PASS: scalar callback status =", status_s)

    # ------ Extended: 16-byte struct by value ------
    var handle_v = lib.call["mojo_probe_adapter_result_handle", UInt64](mojo_struct_adapter_cb)
    assert_equal(handle_v, UInt64(0xBEEF))
    print("  PASS: struct-by-value callback handle =", hex(handle_v))

    var status_v = lib.call["mojo_probe_adapter_result_status", UInt32](mojo_struct_adapter_cb)
    assert_equal(status_v, UInt32(42))
    print("  PASS: struct-by-value callback status =", status_v)

    # ------ Stored callbacks: the shape wgpu-native uses ------
    # The production callbacks from callbacks.mojo, stored by address in a
    # 40-byte CallbackInfo passed BY VALUE, and called back with a 16-byte
    # string view by value. This used to need ffi/wgpu_callbacks.c.
    var adapter_res = _AdapterResult(null_opaque(), 0)
    lib.call["mojo_probe_dispatch_adapter_like"](
        _CallbackInfo40(
            null_opaque(), 1, request_adapter_callback(),
            _addr(Pointer(to=adapter_res)), null_opaque(),
        )
    )
    assert_equal(Int(adapter_res.adapter), 0xBEEF)
    assert_equal(adapter_res.status, UInt32(42))
    print("  PASS: stored callback via by-value CallbackInfo (adapter shape)")

    var pop_res = _PopErrorResult(0, 0, null_opaque(), 0)
    lib.call["mojo_probe_dispatch_pop_error_like"](
        _CallbackInfo40(
            null_opaque(), 1, pop_error_scope_callback(),
            _addr(Pointer(to=pop_res)), null_opaque(),
        )
    )
    assert_equal(pop_res.status, UInt32(1))
    assert_equal(pop_res.type, UInt32(2))
    var p = pop_res.message_data.unsafe_bitcast[UInt8]()
    var msg = String(StringSlice(unsafe_from_utf8=Span(unsafe_ptr=p, length=Int(pop_res.message_len))))
    p.unsafe_free()
    # The C side overwrote its buffer after the callback returned, so this
    # only holds if the callback copied the bytes (and kept the UTF-8 intact).
    assert_equal(msg, "validation: héllo")
    print("  PASS: pop-error callback copies its message before the view dies")
