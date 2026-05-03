"""wgpu._ffi.alloc_guard - scoped heap allocation helper for FFI structs."""


struct AllocGuard[T: AnyType](Movable):
    """Owns an `alloc[T](count)` allocation and frees it on scope exit."""

    var _ptr: UnsafePointer[Self.T, MutExternalOrigin]
    var _is_live: Bool

    def __init__(out self, count: Int):
        self._ptr = alloc[Self.T](count)
        self._is_live = True

    def __init__(out self, *, deinit take: Self):
        self._ptr = take._ptr
        self._is_live = take._is_live

    def __del__(deinit self):
        if self._is_live:
            self._ptr.free()

    def __enter__(mut self) -> UnsafePointer[Self.T, MutExternalOrigin]:
        return self._ptr

    def __exit__(mut self):
        if self._is_live:
            self._ptr.free()
            self._ptr = UnsafePointer[Self.T, MutExternalOrigin].unsafe_dangling()
            self._is_live = False

    def ptr(self) -> UnsafePointer[Self.T, MutExternalOrigin]:
        return self._ptr
