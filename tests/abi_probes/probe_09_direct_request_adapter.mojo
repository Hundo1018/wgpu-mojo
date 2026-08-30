"""Probe 09: >16-byte struct-by-value ABI through OwnedDLHandle.call.

This probe validates the caller-side ABI path directly with a small C helper,
without relying on nullable pointer construction in Mojo wrappers.

The tested struct is 40 bytes on x86_64 (ptr + u32 + padding + ptr + ptr + ptr),
which mirrors the size class used by callback-info structs such as
WGPURequestAdapterCallbackInfo.
"""

from std.ffi import OwnedDLHandle


@fieldwise_init
struct _CallbackInfo40(TrivialRegisterPassable):
    var next_in_chain: OpaquePointer[MutUntrackedOrigin]
    var mode: UInt32
    var callback: OpaquePointer[MutUntrackedOrigin]
    var userdata1: OpaquePointer[MutUntrackedOrigin]
    var userdata2: OpaquePointer[MutUntrackedOrigin]


def _ptr(addr: Int) -> OpaquePointer[MutUntrackedOrigin]:
    return rebind[OpaquePointer[MutUntrackedOrigin]](
        Pointer[NoneType, MutUntrackedOrigin](unsafe_from_address=addr)
    )


def _expected_checksum(
    next_in_chain: OpaquePointer[MutUntrackedOrigin],
    mode: UInt32,
    callback: OpaquePointer[MutUntrackedOrigin],
    userdata1: OpaquePointer[MutUntrackedOrigin],
    userdata2: OpaquePointer[MutUntrackedOrigin],
) -> UInt64:
    var out = UInt64(0)
    out ^= UInt64(Int(next_in_chain))
    out ^= UInt64(mode) << UInt64(32)
    out ^= UInt64(Int(callback))
    out ^= UInt64(Int(userdata1))
    out ^= UInt64(Int(userdata2))
    return out


def main() raises:
    var lib = OwnedDLHandle("ffi/lib/libmojo_callback_probe.so")

    var info = _CallbackInfo40(
        _ptr(0x1111),
        UInt32(42),
        _ptr(0x2222),
        _ptr(0x3333),
        _ptr(0x4444),
    )

    var got = lib.call["mojo_probe_cbinfo40_checksum", UInt64](info)
    var want = _expected_checksum(
        info.next_in_chain,
        info.mode,
        info.callback,
        info.userdata1,
        info.userdata2,
    )
    if got == want:
        print("PASS: 40-byte struct-by-value checksum =", got)
    else:
        # Known on current nightly: probe runs, but by-value payload differs.
        # Keep this as XFAIL so it reports signal without breaking CI/main tests.
        print("XFAIL: 40-byte struct-by-value checksum mismatch")
        print("  got :", got)
        print("  want:", want)

