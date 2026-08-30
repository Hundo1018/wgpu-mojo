"""
wgpu.pipeline — ComputePipeline and RenderPipeline RAII wrappers.
"""

from std.memory import ArcPointer
from wgpu._ffi.lib import WGPULib
from wgpu._ffi.types import (
    WGPUComputePipelineHandle, WGPURenderPipelineHandle,
)
from wgpu._ffi.structs import WGPUStringView, str_to_sv
from wgpu._ffi.handles import ComputePipelineHandle, RenderPipelineHandle
from wgpu.bind_group import BindGroupLayout


struct ComputePipeline(Movable, Boolable):
    """RAII wrapper around a WGPUComputePipeline."""

    var _lib:    ArcPointer[WGPULib]
    var _handle: WGPUComputePipelineHandle

    def __init__(out self, lib: ArcPointer[WGPULib], handle: WGPUComputePipelineHandle):
        self._lib    = lib
        self._handle = handle

    def __init__(out self, *, deinit move: Self):
        self._lib    = move._lib^
        self._handle = move._handle

    def __del__(deinit self):
        self._lib[].compute_pipeline_release(self._handle)

    def clone(self) -> Self:
        """Share ownership of this GPU object via `wgpuComputePipelineAddRef`.

        A refcount bump, not a GPU-side copy: both wrappers refer to the same
        object and each releases on drop, so it survives until the last one
        goes away.
        """
        self._lib[].compute_pipeline_add_ref(self._handle)
        return Self(self._lib, self._handle)

    def handle(self) -> ComputePipelineHandle:
        return ComputePipelineHandle(self._handle)

    def __bool__(self) -> Bool:
        return Int(self._handle) != 0

    def get_bind_group_layout(self, index: UInt32) -> BindGroupLayout:
        var h = self._lib[].compute_pipeline_get_bind_group_layout(self._handle, index)
        return BindGroupLayout(self._lib, h)

struct RenderPipeline(Movable, Boolable):
    """RAII wrapper around a WGPURenderPipeline."""

    var _lib:    ArcPointer[WGPULib]
    var _handle: WGPURenderPipelineHandle

    def __init__(out self, lib: ArcPointer[WGPULib], handle: WGPURenderPipelineHandle):
        self._lib    = lib
        self._handle = handle

    def __init__(out self, *, deinit move: Self):
        self._lib    = move._lib^
        self._handle = move._handle

    def __del__(deinit self):
        self._lib[].render_pipeline_release(self._handle)

    def clone(self) -> Self:
        """Share ownership of this GPU object via `wgpuRenderPipelineAddRef`.

        A refcount bump, not a GPU-side copy: both wrappers refer to the same
        object and each releases on drop, so it survives until the last one
        goes away.
        """
        self._lib[].render_pipeline_add_ref(self._handle)
        return Self(self._lib, self._handle)

    def handle(self) -> RenderPipelineHandle:
        return RenderPipelineHandle(self._handle)

    def __bool__(self) -> Bool:
        return Int(self._handle) != 0

    def get_bind_group_layout(self, index: UInt32) -> BindGroupLayout:
        var h = self._lib[].render_pipeline_get_bind_group_layout(self._handle, index)
        return BindGroupLayout(self._lib, h)

