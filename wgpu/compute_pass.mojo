"""
wgpu.compute_pass — ComputePassEncoder RAII wrapper.
"""

from wgpu._ffi.lib import WGPULib
from wgpu._ffi.types import (
    OpaquePtr,
    WGPUComputePassEncoderHandle, WGPUComputePipelineHandle,
    WGPUBindGroupHandle, WGPUBufferHandle, WGPUQuerySetHandle,
)
from wgpu._ffi.structs import WGPUStringView, str_to_sv


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
        var ptr = OpaquePtr(unsafe_from_address=Int(offsets.unsafe_ptr()))
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

    # ------------------------------------------------------------------
    # Debug groups
    # ------------------------------------------------------------------

    def push_debug_group(self, label: String):
        var sv = str_to_sv(label) if len(label) > 0 else WGPUStringView.null_view()
        self._lib.compute_pass_push_debug_group(self._handle, sv)

    def pop_debug_group(self):
        self._lib.compute_pass_pop_debug_group(self._handle)

    def insert_debug_marker(self, label: String):
        var sv = str_to_sv(label) if len(label) > 0 else WGPUStringView.null_view()
        self._lib.compute_pass_insert_debug_marker(self._handle, sv)

    # ------------------------------------------------------------------
    # Label
    # ------------------------------------------------------------------

    def set_label(self, label: String):
        var sv = str_to_sv(label) if len(label) > 0 else WGPUStringView.null_view()
        self._lib.compute_pass_set_label(self._handle, sv)

    # ------------------------------------------------------------------
    # wgpu-native extensions
    # ------------------------------------------------------------------

    def set_push_constants(self, offset: UInt32, size_bytes: UInt32, data: OpaquePtr):
        self._lib.compute_pass_set_push_constants(self._handle, offset, size_bytes, data)

    def begin_pipeline_statistics_query(self, query_set: WGPUQuerySetHandle, query_index: UInt32):
        self._lib.compute_pass_begin_pipeline_statistics_query(self._handle, query_set, query_index)

    def end_pipeline_statistics_query(self):
        self._lib.compute_pass_end_pipeline_statistics_query(self._handle)

    def write_timestamp(self, query_set: WGPUQuerySetHandle, query_index: UInt32):
        self._lib.compute_pass_write_timestamp(self._handle, query_set, query_index)
