"""wgpu._backend.wgpu_native.nulls — shared null pointer helpers (Mojo pointers have no default constructor)."""


def null_opaque() -> OpaquePointer[MutUntrackedOrigin]:
    return OpaquePointer[MutUntrackedOrigin](unsafe_from_address=Int(0))


def null_ptr[T: AnyType]() -> Pointer[T, MutUntrackedOrigin]:
    return Pointer[T, MutUntrackedOrigin](unsafe_from_address=Int(0))


def null_any_ptr() -> Pointer[NoneType, MutUntrackedOrigin]:
    return Pointer[NoneType, MutUntrackedOrigin](unsafe_from_address=Int(0))
