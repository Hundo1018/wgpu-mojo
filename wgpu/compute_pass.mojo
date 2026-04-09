"""
wgpu.compute_pass — ComputePassEncoder RAII wrapper.
"""

from wgpu._ffi.lib import WGPULib
from wgpu._ffi.types import (
    OpaquePtr,
    WGPUComputePassEncoderHandle, WGPUComputePipelineHandle,
    WGPUBindGroupHandle, WGPUBufferHandle,
)


struct ComputePassEncoder(Movable):
    """RAII wrapper around a WGPUComputePassEncoder. `end()` must be called."""

    var _lib:    WGPULib
    var _handle: WGPUComputePassEncoderHandle

    def __init__(out self, var lib: WGPULib, handle: WGPUComputePassEncoderHandle):
        self._lib    = lib^
        self._handle = handle

    def __init__(out self, *, deinit take: Self):
        self._lib    = take._lib^
        self._handle = take._handle

    def __del__(deinit self):
        self._lib.compute_pass_release(self._handle)

    def set_pipeline(self, pipeline: WGPUComputePipelineHandle):
        self._lib.compute_pass_set_pipeline(self._handle, pipeline)

    def set_bind_group(self, index: UInt32, bind_group: WGPUBindGroupHandle):
        self._lib.compute_pass_set_bind_group(
            self._handle, index, bind_group, OpaquePtr(), UInt(0)
        )

    def set_bind_group_with_offsets(
        self,
        index: UInt32,
        bind_group: WGPUBindGroupHandle,
        offsets: List[UInt32],
    ):
        var ptr = offsets.unsafe_ptr().bitcast[NoneType]()
        self._lib.compute_pass_set_bind_group(
            self._handle, index, bind_group, ptr, UInt(len(offsets))
        )

    def dispatch_workgroups(self, x: UInt32, y: UInt32 = 1, z: UInt32 = 1):
        self._lib.compute_pass_dispatch_workgroups(self._handle, x, y, z)

    def dispatch_workgroups_indirect(
        self, indirect_buffer: WGPUBufferHandle, indirect_offset: UInt64
    ):
        self._lib.compute_pass_dispatch_workgroups_indirect(
            self._handle, indirect_buffer, indirect_offset
        )

    def end(self):
        self._lib.compute_pass_end(self._handle)

    def handle(self) -> WGPUComputePassEncoderHandle:
        return self._handle
