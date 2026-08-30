"""rendercanvas.nulls — shared null pointer helper for GLFW FFI."""


def null_opaque() -> OpaquePointer[MutUntrackedOrigin]:
    return OpaquePointer[MutUntrackedOrigin](unsafe_from_address=Int(0))
