"""
wgpu.query_set — QuerySet RAII wrapper.
"""

from std.memory import ArcPointer
from wgpu._ffi.lib import WGPULib
from wgpu._ffi.types import OpaquePtr, WGPUQuerySetHandle
from wgpu._ffi.structs import WGPUStringView, str_to_sv
from wgpu._ffi.handles import QuerySetHandle


struct QuerySet(Movable):
    """RAII wrapper around a WGPUQuerySet."""

    var _lib:    ArcPointer[WGPULib]
    var _handle: WGPUQuerySetHandle

    def __init__(out self, lib: ArcPointer[WGPULib], handle: WGPUQuerySetHandle):
        self._lib    = lib
        self._handle = handle

    def __init__(out self, *, deinit take: Self):
        self._lib    = take._lib^
        self._handle = take._handle

    def __del__(deinit self):
        # wgpuQuerySetDestroy in wgpu-native v29 calls query_set_drop() which
        # removes the resource from the registry immediately.  When Release
        # then decrements the Arc refcount to zero, WGPUQuerySetImpl::drop
        # fires and tries to drop the already-removed resource → double-free.
        # Buffer/Texture don't have this problem because their Destroy only
        # marks the resource invalid without removing it from the registry.
        # Fix: skip Destroy and let Release + Arc drop do the full cleanup.
        self._lib[].query_set_release(self._handle)

    def handle(self) -> QuerySetHandle:
        return QuerySetHandle(self._handle)

    def get_count(self) -> UInt32:
        return self._lib[].query_set_get_count(self._handle)

    def get_type(self) -> UInt32:
        return self._lib[].query_set_get_type(self._handle)

    def set_label(self, label: String):
        var sv = str_to_sv(label) if label.byte_length() > 0 else WGPUStringView.null_view()
        self._lib[].query_set_set_label(self._handle, sv)
