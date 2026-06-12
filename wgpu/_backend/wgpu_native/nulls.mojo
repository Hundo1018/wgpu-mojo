"""wgpu._backend.wgpu_native.nulls — shared null pointer helpers for current Mojo nightly."""


def null_opaque() -> OpaquePointer[MutUntrackedOrigin]:
    return OpaquePointer[MutUntrackedOrigin](unsafe_from_address=Int(0))


def null_ptr[T: AnyType]() -> UnsafePointer[T, MutUntrackedOrigin]:
    return UnsafePointer[T, MutUntrackedOrigin](unsafe_from_address=Int(0))


def null_any_ptr() -> UnsafePointer[NoneType, MutAnyOrigin]:
    return UnsafePointer[NoneType, MutAnyOrigin](unsafe_from_address=Int(0))
