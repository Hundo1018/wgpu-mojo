"""
wgpu.texture — Texture and TextureView RAII wrappers.
"""

from wgpu._ffi.lib import WGPULib
from wgpu._ffi.types import OpaquePtr, WGPUTextureHandle, WGPUTextureViewHandle
from wgpu._ffi.structs import WGPUTextureViewDescriptor, WGPUStringView, str_to_sv


struct TextureView(Movable):
    """RAII wrapper around a WGPUTextureView."""

    var _lib:    WGPULib
    var _handle: WGPUTextureViewHandle

    def __init__(out self, var lib: WGPULib, handle: WGPUTextureViewHandle):
        self._lib    = lib^
        self._handle = handle

    def __init__(out self, *, deinit take: Self):
        self._lib    = take._lib^
        self._handle = take._handle

    def __del__(deinit self):
        self._lib.texture_view_release(self._handle)

    def handle(self) -> WGPUTextureViewHandle:
        return self._handle


struct Texture(Movable):
    """RAII wrapper around a WGPUTexture."""

    var _lib:    WGPULib
    var _handle: WGPUTextureHandle

    def __init__(out self, var lib: WGPULib, handle: WGPUTextureHandle):
        self._lib    = lib^
        self._handle = handle

    def __init__(out self, *, deinit take: Self):
        self._lib    = take._lib^
        self._handle = take._handle

    def __del__(deinit self):
        self._lib.texture_destroy(self._handle)
        self._lib.texture_release(self._handle)

    def handle(self) -> WGPUTextureHandle:
        return self._handle

    def width(self) -> UInt32:
        return self._lib.texture_get_width(self._handle)

    def height(self) -> UInt32:
        return self._lib.texture_get_height(self._handle)

    def depth_or_array_layers(self) -> UInt32:
        return self._lib.texture_get_depth_or_array_layers(self._handle)

    def format(self) -> UInt32:
        return self._lib.texture_get_format(self._handle)

    def create_view_default(self) -> WGPUTextureViewHandle:
        return self._lib.texture_create_view(
            self._handle,
            UnsafePointer[WGPUTextureViewDescriptor, MutExternalOrigin](),
        )

    def create_view(
        self,
        desc: UnsafePointer[WGPUTextureViewDescriptor, MutExternalOrigin],
    ) -> WGPUTextureViewHandle:
        return self._lib.texture_create_view(self._handle, desc)
