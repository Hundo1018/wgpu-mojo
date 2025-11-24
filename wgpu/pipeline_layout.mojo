"""
wgpu.pipeline_layout — PipelineLayout RAII wrapper.
"""

from std.memory import ArcPointer
from wgpu._ffi.lib import WGPULib
from wgpu._ffi.types import OpaquePtr, WGPUPipelineLayoutHandle
from wgpu._ffi.structs import WGPUStringView, str_to_sv
from wgpu._ffi.handles import PipelineLayoutHandle


struct PipelineLayout(Movable):
    """RAII wrapper around a WGPUPipelineLayout."""

    var _lib:    ArcPointer[WGPULib]
    var _handle: WGPUPipelineLayoutHandle

    def __init__(out self, lib: ArcPointer[WGPULib], handle: WGPUPipelineLayoutHandle):
        self._lib    = lib
        self._handle = handle

    def __init__(out self, *, deinit take: Self):
        self._lib    = take._lib^
        self._handle = take._handle

    def __del__(deinit self):
        self._lib[].pipeline_layout_release(self._handle)

    def handle(self) -> PipelineLayoutHandle:
        return PipelineLayoutHandle(self._handle)

    def set_label(self, label: String):
        var sv = str_to_sv(label) if label.byte_length() > 0 else WGPUStringView.null_view()
        self._lib[].pipeline_layout_set_label(self._handle, sv)
