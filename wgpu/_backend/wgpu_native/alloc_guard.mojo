"""wgpu._backend.wgpu_native.alloc_guard - scoped heap allocation helper for FFI structs."""

from std.memory import alloc, Layout


struct AllocGuard[T: AnyType](Movable):
    """Owns an `alloc[T](count)` allocation and frees it on scope exit."""

    var _ptr: Pointer[Self.T, MutUntrackedOrigin]
    var _is_live: Bool

    def __init__(out self, count: Int):
        # `alloc(Layout[T](count=n))` yields an `Allocation`, which is a linear
        # type the FFI layer cannot pass: its pointer carries the allocation's
        # own origin and will not convert to MutUntrackedOrigin, which every
        # loader signature uses. `unsafe_leak()` hands over the raw pointer and
        # the responsibility for freeing it — which is exactly what this guard
        # exists to hold. Keeping that bridge here means no other file has to
        # touch the Layout API.
        var allocation = alloc(Layout[Self.T](count=count))
        self._ptr = allocation^.unsafe_leak()
        self._is_live = True

    def __init__(out self, *, deinit move: Self):
        self._ptr = move._ptr
        self._is_live = move._is_live

    def __deinit__(deinit self):
        if self._is_live:
            self._ptr.unsafe_free()

    def __enter__(mut self) -> Pointer[Self.T, MutUntrackedOrigin]:
        return self._ptr

    def __exit__(mut self):
        if self._is_live:
            self._ptr.unsafe_free()
            self._ptr = Pointer[Self.T, MutUntrackedOrigin].unsafe_dangling()
            self._is_live = False

    def ptr(self) -> Pointer[Self.T, MutUntrackedOrigin]:
        return self._ptr


def raw_alloc[T: AnyType](count: Int) -> Pointer[T, MutUntrackedOrigin]:
    """`alloc[T](count)`'s replacement: heap storage the caller must free.

    The bare `alloc[T](count)` is deprecated in favour of
    `alloc(Layout[T](count=n))`, but that returns an `Allocation` — a linear
    type whose pointer carries the allocation's own origin and will not convert
    to the MutUntrackedOrigin every loader signature uses. `unsafe_leak()`
    hands over the raw pointer and the duty to free it.

    Ownership is therefore unchanged from the old `alloc`: the caller still
    calls `unsafe_free()`. Where a scope-bound lifetime is wanted, use
    `AllocGuard` instead — it frees for you.
    """
    var allocation = alloc(Layout[T](count=count))
    return allocation^.unsafe_leak()
