"""Phase 4 ABI probe: pass Mojo def callback into C and invoke it."""

from std.ffi import OwnedDLHandle
from std.testing import assert_equal, assert_true
from wgpu._ffi.types import OpaquePtr


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
    adapter: OpaquePtr,
    msg_data: OpaquePtr,
    msg_len: UInt64,
    ud1: OpaquePtr,
    ud2: OpaquePtr,
):
    """Scalar-only callback: receive StringView as two separate args."""
    var result_p = rebind[UnsafePointer[_ProbeAdapterResult, MutExternalOrigin]](ud1)
    result_p[] = _ProbeAdapterResult(UInt64(Int(adapter)), status)


# Probe B: callback with 16-byte struct by value (WGPUStringView equivalent)
@fieldwise_init
struct _StringView16(TrivialRegisterPassable):
    var data: OpaquePtr
    var length: UInt64


def mojo_struct_adapter_cb(
    status: UInt32,
    adapter: OpaquePtr,
    msg: _StringView16,
    ud1: OpaquePtr,
    ud2: OpaquePtr,
):
    """Struct-by-value callback: receive 16-byte StringView as single param."""
    var result_p = rebind[UnsafePointer[_ProbeAdapterResult, MutExternalOrigin]](ud1)
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

    # NOTE: Extracting a Mojo def as OpaquePtr for storage in C structs
    # does NOT work. Mojo def functions are kgen.generator internally, not
    # plain function pointers. rebind[OpaquePtr](fn) fails.
    # This means wgpu callbacks (which require storing a function pointer in
    # WGPURequestAdapterCallbackInfo) must remain as C implementations.
    # DLHandle.call handles the conversion implicitly when passing functions
    # as arguments, but we cannot extract the raw pointer ourselves.
    print("  NOTE: raw fn_ptr extraction not possible (def = kgen.generator)")
    print("  Conclusion: C callback bridge must stay for stored fn-ptr callbacks")
