"""
wgpu.pipeline — ComputePipeline and RenderPipeline RAII wrappers.
"""

from wgpu._ffi.lib import WGPULib
from wgpu._ffi.types import (
    OpaquePtr,
    WGPUComputePipelineHandle, WGPURenderPipelineHandle,
    WGPUBindGroupLayoutHandle,
)
from wgpu._ffi.structs import WGPUStringView, str_to_sv


struct ComputePipeline(Movable):
    """RAII wrapper around a WGPUComputePipeline."""

    var _lib:    WGPULib
    var _handle: WGPUComputePipelineHandle

    def __init__(out self, var lib: WGPULib, handle: WGPUComputePipelineHandle):
        self._lib    = lib^
        self._handle = handle

    def __init__(out self, *, deinit take: Self):
        self._lib    = take._lib^
        self._handle = take._handle

    def __del__(deinit self):
        self._lib.compute_pipeline_release(self._handle)

    def handle(self) -> WGPUComputePipelineHandle:
        return self._handle

    def get_bind_group_layout(self, index: UInt32) -> WGPUBindGroupLayoutHandle:
        return self._lib.compute_pipeline_get_bind_group_layout(self._handle, index)

    def set_label(self, label: String):
        var sv = str_to_sv(label) if len(label) > 0 else WGPUStringView.null_view()
        self._lib.compute_pipeline_set_label(self._handle, sv)


struct RenderPipeline(Movable):
    """RAII wrapper around a WGPURenderPipeline."""

    var _lib:    WGPULib
    var _handle: WGPURenderPipelineHandle

    def __init__(out self, var lib: WGPULib, handle: WGPURenderPipelineHandle):
        self._lib    = lib^
        self._handle = handle

    def __init__(out self, *, deinit take: Self):
        self._lib    = take._lib^
        self._handle = take._handle

    def __del__(deinit self):
        self._lib.render_pipeline_release(self._handle)

    def handle(self) -> WGPURenderPipelineHandle:
        return self._handle

    def get_bind_group_layout(self, index: UInt32) -> WGPUBindGroupLayoutHandle:
        return self._lib.render_pipeline_get_bind_group_layout(self._handle, index)

    def set_label(self, label: String):
        var sv = str_to_sv(label) if len(label) > 0 else WGPUStringView.null_view()
        self._lib.render_pipeline_set_label(self._handle, sv)
