"""
wgpu.query_set — QuerySet RAII wrapper.
"""

from wgpu._ffi.lib import WGPULib
from wgpu._ffi.types import OpaquePtr, WGPUQuerySetHandle
from wgpu._ffi.structs import WGPUStringView, str_to_sv


struct QuerySet(Movable):
    """RAII wrapper around a WGPUQuerySet."""

    var _lib:    WGPULib
    var _handle: WGPUQuerySetHandle

    def __init__(out self, var lib: WGPULib, handle: WGPUQuerySetHandle):
        self._lib    = lib^
        self._handle = handle

    def __init__(out self, *, deinit take: Self):
        self._lib    = take._lib^
        self._handle = take._handle

    def __del__(deinit self):
        self._lib.query_set_destroy(self._handle)
        self._lib.query_set_release(self._handle)

    def handle(self) -> WGPUQuerySetHandle:
        return self._handle

    def get_count(self) -> UInt32:
        return self._lib.query_set_get_count(self._handle)

    def get_type(self) -> UInt32:
        return self._lib.query_set_get_type(self._handle)

    def set_label(self, label: String):
        var sv = str_to_sv(label) if len(label) > 0 else WGPUStringView.null_view()
        self._lib.query_set_set_label(self._handle, sv)
