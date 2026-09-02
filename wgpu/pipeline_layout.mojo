"""
PipelineLayout RAII wrapper.
"""

from std.memory import ArcPointer
from wgpu._ffi.lib import WGPULib
from wgpu._ffi.types import WGPUPipelineLayoutHandle
from wgpu._ffi.structs import WGPUStringView, str_to_sv
from wgpu._ffi.handles import PipelineLayoutHandle


struct PipelineLayout(Movable, Boolable):
    """RAII wrapper around a WGPUPipelineLayout."""

    var _lib:    ArcPointer[WGPULib]
    var _handle: WGPUPipelineLayoutHandle

    def __init__(out self, lib: ArcPointer[WGPULib], handle: WGPUPipelineLayoutHandle):
        self._lib    = lib
        self._handle = handle

    def __init__(out self, *, deinit move: Self):
        self._lib    = move._lib^
        self._handle = move._handle

    def __deinit__(deinit self):
        self._lib[].pipeline_layout_release(self._handle)

    def clone(self) -> Self:
        """Share ownership of this GPU object via `wgpuPipelineLayoutAddRef`.

        A refcount bump, not a GPU-side copy: both wrappers refer to the same
        object and each releases on drop, so it survives until the last one
        goes away.
        """
        self._lib[].pipeline_layout_add_ref(self._handle)
        return Self(self._lib, self._handle)

    def handle(self) -> PipelineLayoutHandle:
        return PipelineLayoutHandle(self._handle)

    def __bool__(self) -> Bool:
        return Int(self._handle) != 0

