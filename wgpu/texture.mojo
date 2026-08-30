"""
wgpu.texture — Texture and TextureView RAII wrappers.
"""

from std.memory import ArcPointer
from wgpu._ffi.lib import WGPULib
from wgpu._ffi.nulls import null_opaque, null_ptr, null_any_ptr
from wgpu._ffi.types import WGPUTextureHandle, WGPUTextureViewHandle
from wgpu._ffi.structs import WGPUTextureViewDescriptor, WGPUStringView, str_to_sv
from wgpu._ffi.handles import TextureHandle, TextureViewHandle


struct TextureView(Movable, Boolable):
    """RAII wrapper around a WGPUTextureView."""

    var _lib:    ArcPointer[WGPULib]
    var _handle: WGPUTextureViewHandle

    def __init__(out self, lib: ArcPointer[WGPULib], handle: WGPUTextureViewHandle):
        self._lib    = lib
        self._handle = handle

    def __init__(out self, *, deinit move: Self):
        self._lib    = move._lib^
        self._handle = move._handle

    def __del__(deinit self):
        self._lib[].texture_view_release(self._handle)

    def handle(self) -> TextureViewHandle:
        return TextureViewHandle(self._handle)

    def __bool__(self) -> Bool:
        return Int(self._handle) != 0

struct Texture(Movable, Boolable):
    """RAII wrapper around a WGPUTexture."""

    var _lib:    ArcPointer[WGPULib]
    var _handle: WGPUTextureHandle

    def __init__(out self, lib: ArcPointer[WGPULib], handle: WGPUTextureHandle):
        self._lib    = lib
        self._handle = handle

    def __init__(out self, *, deinit move: Self):
        self._lib    = move._lib^
        self._handle = move._handle

    def __del__(deinit self):
        self._lib[].texture_release(self._handle)

    def handle(self) -> TextureHandle:
        return TextureHandle(self._handle)

    def __bool__(self) -> Bool:
        return Int(self._handle) != 0

    def width(self) -> UInt32:
        return self._lib[].texture_get_width(self._handle)

    def height(self) -> UInt32:
        return self._lib[].texture_get_height(self._handle)

    def depth_or_array_layers(self) -> UInt32:
        return self._lib[].texture_get_depth_or_array_layers(self._handle)

    def format(self) -> UInt32:
        return self._lib[].texture_get_format(self._handle)

    def dimension(self) -> UInt32:
        return self._lib[].texture_get_dimension(self._handle)

    def mip_level_count(self) -> UInt32:
        return self._lib[].texture_get_mip_level_count(self._handle)

    def sample_count(self) -> UInt32:
        return self._lib[].texture_get_sample_count(self._handle)

    def create_view_default(self) raises -> TextureView:
        var h = self._lib[].texture_create_view(
            self._handle,
            null_ptr[WGPUTextureViewDescriptor](),
        )
        return TextureView(self._lib, h)

    def create_view(
        self,
        desc: UnsafePointer[WGPUTextureViewDescriptor, MutUntrackedOrigin],
    ) raises -> TextureView:
        var h = self._lib[].texture_create_view(self._handle, desc)
        return TextureView(self._lib, h)

