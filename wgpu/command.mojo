"""
wgpu.command — CommandEncoder RAII wrapper.
"""

from wgpu._ffi.lib import WGPULib
from wgpu._ffi.types import (
    OpaquePtr,
    WGPUCommandEncoderHandle, WGPUCommandBufferHandle,
    WGPUComputePassEncoderHandle, WGPURenderPassEncoderHandle,
    WGPUBufferHandle, WGPUTextureHandle, WGPUQuerySetHandle,
)
from wgpu._ffi.structs import (
    WGPUCommandBufferDescriptor,
    WGPUComputePassDescriptor,
    WGPURenderPassDescriptor,
    WGPUTexelCopyBufferInfo,
    WGPUTexelCopyTextureInfo,
    WGPUExtent3D,
    WGPUStringView,
    str_to_sv,
)


struct CommandEncoder(Movable):
    """RAII wrapper around a WGPUCommandEncoder."""

    var _lib:    WGPULib
    var _handle: WGPUCommandEncoderHandle

    def __init__(out self, var lib: WGPULib, handle: WGPUCommandEncoderHandle):
        self._lib    = lib^
        self._handle = handle

    def __init__(out self, *, deinit take: Self):
        self._lib    = take._lib^
        self._handle = take._handle

    def __del__(deinit self):
        self._lib.command_encoder_release(self._handle)

    def handle(self) -> WGPUCommandEncoderHandle:
        return self._handle

    # ------------------------------------------------------------------
    # Pass creation
    # ------------------------------------------------------------------

    def begin_compute_pass(
        self, label: String = ""
    ) -> WGPUComputePassEncoderHandle:
        var label_sv = str_to_sv(label) if len(label) > 0 else WGPUStringView.null_view()
        var desc_p = alloc[WGPUComputePassDescriptor](1)
        desc_p[] = WGPUComputePassDescriptor(OpaquePtr(), label_sv, OpaquePtr())
        var result = self._lib.command_encoder_begin_compute_pass(self._handle, desc_p)
        desc_p.free()
        return result

    def begin_render_pass(
        self, desc: UnsafePointer[WGPURenderPassDescriptor, MutExternalOrigin]
    ) -> WGPURenderPassEncoderHandle:
        return self._lib.command_encoder_begin_render_pass(self._handle, desc)

    # ------------------------------------------------------------------
    # Copy operations
    # ------------------------------------------------------------------

    def copy_buffer_to_buffer(
        self,
        src: WGPUBufferHandle,
        src_offset: UInt64,
        dst: WGPUBufferHandle,
        dst_offset: UInt64,
        size: UInt64,
    ):
        self._lib.command_encoder_copy_buffer_to_buffer(
            self._handle, src, src_offset, dst, dst_offset, size
        )

    def copy_buffer_to_texture(
        self,
        src: UnsafePointer[WGPUTexelCopyBufferInfo, MutExternalOrigin],
        dst: UnsafePointer[WGPUTexelCopyTextureInfo, MutExternalOrigin],
        size: UnsafePointer[WGPUExtent3D, MutExternalOrigin],
    ):
        self._lib.command_encoder_copy_buffer_to_texture(self._handle, src, dst, size)

    def copy_texture_to_buffer(
        self,
        src: UnsafePointer[WGPUTexelCopyTextureInfo, MutExternalOrigin],
        dst: UnsafePointer[WGPUTexelCopyBufferInfo, MutExternalOrigin],
        size: UnsafePointer[WGPUExtent3D, MutExternalOrigin],
    ):
        self._lib.command_encoder_copy_texture_to_buffer(self._handle, src, dst, size)

    def clear_buffer(self, buffer: WGPUBufferHandle, offset: UInt64 = 0, size: UInt64 = 0):
        self._lib.command_encoder_clear_buffer(self._handle, buffer, offset, size)

    def resolve_query_set(
        self,
        query_set: WGPUQuerySetHandle,
        first_query: UInt32,
        query_count: UInt32,
        destination: WGPUBufferHandle,
        destination_offset: UInt64,
    ):
        self._lib.command_encoder_resolve_query_set(
            self._handle, query_set, first_query, query_count, destination, destination_offset
        )

    # ------------------------------------------------------------------
    # Finish
    # ------------------------------------------------------------------

    def finish(self, label: String = "") -> WGPUCommandBufferHandle:
        var label_sv = str_to_sv(label) if len(label) > 0 else WGPUStringView.null_view()
        var desc_p = alloc[WGPUCommandBufferDescriptor](1)
        desc_p[] = WGPUCommandBufferDescriptor(OpaquePtr(), label_sv)
        var result = self._lib.command_encoder_finish(self._handle, desc_p)
        desc_p.free()
        return result
