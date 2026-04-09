"""
wgpu.pipeline_layout — PipelineLayout RAII wrapper.
"""

from wgpu._ffi.lib import WGPULib
from wgpu._ffi.types import OpaquePtr, WGPUPipelineLayoutHandle


struct PipelineLayout(Movable):
    """RAII wrapper around a WGPUPipelineLayout."""

    var _lib:    WGPULib
    var _handle: WGPUPipelineLayoutHandle

    def __init__(out self, var lib: WGPULib, handle: WGPUPipelineLayoutHandle):
        self._lib    = lib^
        self._handle = handle

    def __init__(out self, *, deinit take: Self):
        self._lib    = take._lib^
        self._handle = take._handle

    def __del__(deinit self):
        self._lib.pipeline_layout_release(self._handle)

    def handle(self) -> WGPUPipelineLayoutHandle:
        return self._handle
