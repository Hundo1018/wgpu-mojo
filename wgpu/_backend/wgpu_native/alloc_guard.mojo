"""wgpu._backend.wgpu_native.alloc_guard - scoped heap allocation helper for FFI structs."""


struct AllocGuard[T: AnyType](Movable):
    """Owns an `alloc[T](count)` allocation and frees it on scope exit."""

    var _ptr: Pointer[Self.T, MutUntrackedOrigin]
    var _is_live: Bool

    def __init__(out self, count: Int):
        self._ptr = alloc[Self.T](count)
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
