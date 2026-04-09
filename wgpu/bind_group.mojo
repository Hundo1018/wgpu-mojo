"""
wgpu.bind_group — BindGroupLayout and BindGroup RAII wrappers.
"""

from wgpu._ffi.lib import WGPULib
from wgpu._ffi.types import (
    OpaquePtr,
    WGPUBindGroupHandle, WGPUBindGroupLayoutHandle,
)
from wgpu._ffi.structs import WGPUStringView, str_to_sv


struct BindGroupLayout(Movable):
    """RAII wrapper around a WGPUBindGroupLayout."""

    var _lib:    WGPULib
    var _handle: WGPUBindGroupLayoutHandle

    def __init__(out self, var lib: WGPULib, handle: WGPUBindGroupLayoutHandle):
        self._lib    = lib^
        self._handle = handle

    def __init__(out self, *, deinit take: Self):
        self._lib    = take._lib^
        self._handle = take._handle

    def __del__(deinit self):
        self._lib.bind_group_layout_release(self._handle)

    def handle(self) -> WGPUBindGroupLayoutHandle:
        return self._handle

    def set_label(self, label: String):
        var sv = str_to_sv(label) if len(label) > 0 else WGPUStringView.null_view()
        self._lib.bind_group_layout_set_label(self._handle, sv)


struct BindGroup(Movable):
    """RAII wrapper around a WGPUBindGroup."""

    var _lib:    WGPULib
    var _handle: WGPUBindGroupHandle

    def __init__(out self, var lib: WGPULib, handle: WGPUBindGroupHandle):
        self._lib    = lib^
        self._handle = handle

    def __init__(out self, *, deinit take: Self):
        self._lib    = take._lib^
        self._handle = take._handle

    def __del__(deinit self):
        self._lib.bind_group_release(self._handle)

    def handle(self) -> WGPUBindGroupHandle:
        return self._handle

    def set_label(self, label: String):
        var sv = str_to_sv(label) if len(label) > 0 else WGPUStringView.null_view()
        self._lib.bind_group_set_label(self._handle, sv)
