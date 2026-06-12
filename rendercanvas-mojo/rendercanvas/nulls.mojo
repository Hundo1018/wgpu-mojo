"""rendercanvas.nulls — shared null pointer helper for GLFW FFI."""


def null_opaque() -> OpaquePointer[MutExternalOrigin]:
    return OpaquePointer[MutExternalOrigin](unsafe_from_address=Int(0))
