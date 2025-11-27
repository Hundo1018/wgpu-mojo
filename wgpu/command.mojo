"""
wgpu.command — CommandEncoder RAII wrapper.
"""

from std.memory import ArcPointer
from wgpu._ffi.lib import WGPULib
from wgpu._ffi.types import (
    OpaquePtr,
    WGPUCommandEncoderHandle, WGPUCommandBufferHandle,
    WGPUComputePassEncoderHandle, WGPURenderPassEncoderHandle,
    WGPUBufferHandle, WGPUTextureHandle, WGPUQuerySetHandle,
)
from wgpu._ffi.handles import CommandEncoderHandle, CommandBufferHandle
from wgpu._ffi.structs import (
    WGPUCommandBufferDescriptor,
    WGPUComputePassDescriptor,
    WGPURenderPassDescriptor,
    WGPURenderPassColorAttachment,
    WGPURenderPassDepthStencilAttachment,
    WGPUPassTimestampWrites,
    WGPUTextureViewDescriptor,
    WGPUTexelCopyBufferInfo,
    WGPUTexelCopyTextureInfo,
    WGPUExtent3D,
    WGPUColor,
    WGPUStringView,
    str_to_sv,
)
from wgpu.compute_pass import ComputePassEncoder
from wgpu.render_pass import RenderPassEncoder, FrameRenderPass
from wgpu.buffer import Buffer
from wgpu.query_set import QuerySet
from wgpu.texture import TextureView


struct CommandBuffer(Movable, Boolable):
    """RAII wrapper around a WGPUCommandBuffer.

    Returned by CommandEncoder.finish(). Consumed by Device.queue_submit().
    Automatically calls wgpuCommandBufferRelease on destruction.
    """

    var _lib:    ArcPointer[WGPULib]
    var _handle: WGPUCommandBufferHandle

    def __init__(out self, lib: ArcPointer[WGPULib], handle: WGPUCommandBufferHandle):
        self._lib    = lib
        self._handle = handle

    def __init__(out self, *, deinit take: Self):
        self._lib    = take._lib^
        self._handle = take._handle

    def __del__(deinit self):
        self._lib[].command_buffer_release(self._handle)

    def handle(self) -> CommandBufferHandle:
        return CommandBufferHandle(self._handle)

    def raw(self) -> WGPUCommandBufferHandle:
        """Return the raw opaque handle (for FFI)."""
        return self._handle

    def __bool__(self) -> Bool:
        return Bool(self._handle)


@explicit_destroy("Must call finish() or abandon()")
struct CommandEncoder(Movable):
    """RAII wrapper around a WGPUCommandEncoder.

    This is a linear type: the compiler enforces that you call `finish()`
    (to produce a CommandBuffer) or `abandon()` (to release without finishing)
    before the encoder goes out of scope.  Forgetting to do so is a
    compile-time error, eliminating a class of silent resource leaks.
    """

    var _lib:    ArcPointer[WGPULib]
    var _handle: WGPUCommandEncoderHandle

    def __init__(out self, lib: ArcPointer[WGPULib], handle: WGPUCommandEncoderHandle):
        self._lib    = lib
        self._handle = handle

    def __init__(out self, *, deinit take: Self):
        self._lib    = take._lib^
        self._handle = take._handle

    def handle(self) -> CommandEncoderHandle:
        return CommandEncoderHandle(self._handle)

    # ------------------------------------------------------------------
    # Pass creation
    # ------------------------------------------------------------------

    def begin_compute_pass(
        self, label: String = ""
    ) -> ComputePassEncoder:
        var label_sv = str_to_sv(label) if label.byte_length() > 0 else WGPUStringView.null_view()
        var desc_p = alloc[WGPUComputePassDescriptor](1)
        desc_p[] = WGPUComputePassDescriptor(OpaquePtr(), label_sv, OpaquePtr())
        var result = self._lib[].command_encoder_begin_compute_pass(self._handle, desc_p)
        desc_p.free()
        return ComputePassEncoder(self._lib, result)

    def begin_render_pass(
        self, desc: UnsafePointer[WGPURenderPassDescriptor, MutExternalOrigin]
    ) -> RenderPassEncoder:
        var result = self._lib[].command_encoder_begin_render_pass(self._handle, desc)
        return RenderPassEncoder(self._lib, result)

    def begin_render_pass_clear(
        self,
        var view: TextureView,
        clear_color: WGPUColor,
        label: String = "",
    ) -> FrameRenderPass:
        """High-level render pass helper for a single color attachment clear.

        This keeps descriptor assembly internal so examples can remain idiomatic
        Mojo code (RAII + linear types) without manual alloc/free boilerplate.
        """
        var label_sv = str_to_sv(label) if label.byte_length() > 0 else WGPUStringView.null_view()

        var color_att_p = alloc[WGPURenderPassColorAttachment](1)
        color_att_p[0] = WGPURenderPassColorAttachment(
            OpaquePtr(),
            view.handle().raw,
            UInt32(0xFFFFFFFF),
            OpaquePtr(),
            UInt32(2),
            UInt32(1),
            clear_color,
        )

        var rp_desc_p = alloc[WGPURenderPassDescriptor](1)
        rp_desc_p[0] = WGPURenderPassDescriptor(
            OpaquePtr(),
            label_sv,
            UInt(1),
            color_att_p,
            UnsafePointer[WGPURenderPassDepthStencilAttachment, MutExternalOrigin](),
            OpaquePtr(),
            UnsafePointer[WGPUPassTimestampWrites, MutExternalOrigin](),
        )

        var result = self._lib[].command_encoder_begin_render_pass(self._handle, rp_desc_p)
        color_att_p.free()
        rp_desc_p.free()
        return FrameRenderPass(self._lib, result, view^)

    def begin_surface_clear_pass(
        self,
        surface_texture: WGPUTextureHandle,
        clear_color: WGPUColor,
        label: String = "",
    ) -> FrameRenderPass:
        """High-level helper for swapchain textures.

        Creates a default TextureView and returns a linear pass context that
        keeps the view alive until end()/abandon().
        """
        var view_h = self._lib[].texture_create_view(
            surface_texture,
            UnsafePointer[WGPUTextureViewDescriptor, MutExternalOrigin](),
        )
        var view = TextureView(self._lib, view_h)
        return self.begin_render_pass_clear(view^, clear_color, label)

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
        self._lib[].command_encoder_copy_buffer_to_buffer(
            self._handle, src, src_offset, dst, dst_offset, size
        )

    def copy_buffer_to_buffer(
        self,
        src: Buffer,
        src_offset: UInt64,
        dst: Buffer,
        dst_offset: UInt64,
        size: UInt64,
    ):
        """Wrapper-first overload — accepts RAII Buffer directly."""
        self._lib[].command_encoder_copy_buffer_to_buffer(
            self._handle, src.handle().raw, src_offset, dst.handle().raw, dst_offset, size
        )

    def copy_buffer_to_texture(
        self,
        src: UnsafePointer[WGPUTexelCopyBufferInfo, MutExternalOrigin],
        dst: UnsafePointer[WGPUTexelCopyTextureInfo, MutExternalOrigin],
        size: UnsafePointer[WGPUExtent3D, MutExternalOrigin],
    ):
        self._lib[].command_encoder_copy_buffer_to_texture(self._handle, src, dst, size)

    def copy_texture_to_buffer(
        self,
        src: UnsafePointer[WGPUTexelCopyTextureInfo, MutExternalOrigin],
        dst: UnsafePointer[WGPUTexelCopyBufferInfo, MutExternalOrigin],
        size: UnsafePointer[WGPUExtent3D, MutExternalOrigin],
    ):
        self._lib[].command_encoder_copy_texture_to_buffer(self._handle, src, dst, size)

    def copy_texture_to_texture(
        self,
        src: UnsafePointer[WGPUTexelCopyTextureInfo, MutExternalOrigin],
        dst: UnsafePointer[WGPUTexelCopyTextureInfo, MutExternalOrigin],
        size: UnsafePointer[WGPUExtent3D, MutExternalOrigin],
    ):
        self._lib[].command_encoder_copy_texture_to_texture(self._handle, src, dst, size)

    def clear_buffer(self, buffer: WGPUBufferHandle, offset: UInt64 = 0, size: UInt64 = 0):
        self._lib[].command_encoder_clear_buffer(self._handle, buffer, offset, size)

    def clear_buffer(self, buffer: Buffer, offset: UInt64 = 0, size: UInt64 = 0):
        """Wrapper-first overload — accepts RAII Buffer directly."""
        self._lib[].command_encoder_clear_buffer(self._handle, buffer.handle().raw, offset, size)

    def resolve_query_set(
        self,
        query_set: WGPUQuerySetHandle,
        first_query: UInt32,
        query_count: UInt32,
        destination: WGPUBufferHandle,
        destination_offset: UInt64,
    ):
        self._lib[].command_encoder_resolve_query_set(
            self._handle, query_set, first_query, query_count, destination, destination_offset
        )

    def resolve_query_set(
        self,
        query_set: QuerySet,
        first_query: UInt32,
        query_count: UInt32,
        destination: Buffer,
        destination_offset: UInt64,
    ):
        """Wrapper-first overload — accepts RAII QuerySet and Buffer directly."""
        self._lib[].command_encoder_resolve_query_set(
            self._handle, query_set.handle().raw, first_query, query_count,
            destination.handle().raw, destination_offset
        )

    def write_timestamp(self, query_set: WGPUQuerySetHandle, query_index: UInt32):
        self._lib[].command_encoder_write_timestamp(self._handle, query_set, query_index)

    def write_timestamp(self, query_set: QuerySet, query_index: UInt32):
        """Wrapper-first overload — accepts RAII QuerySet directly."""
        self._lib[].command_encoder_write_timestamp(self._handle, query_set.handle().raw, query_index)

    # ------------------------------------------------------------------
    # Debug groups
    # ------------------------------------------------------------------

    def push_debug_group(self, label: String):
        var sv = str_to_sv(label) if label.byte_length() > 0 else WGPUStringView.null_view()
        self._lib[].command_encoder_push_debug_group(self._handle, sv)

    def pop_debug_group(self):
        self._lib[].command_encoder_pop_debug_group(self._handle)

    def insert_debug_marker(self, label: String):
        var sv = str_to_sv(label) if label.byte_length() > 0 else WGPUStringView.null_view()
        self._lib[].command_encoder_insert_debug_marker(self._handle, sv)

    # ------------------------------------------------------------------
    # Label
    # ------------------------------------------------------------------

    def set_label(self, label: String):
        var sv = str_to_sv(label) if label.byte_length() > 0 else WGPUStringView.null_view()
        self._lib[].command_encoder_set_label(self._handle, sv)

    # ------------------------------------------------------------------
    # Finish
    # ------------------------------------------------------------------

    def finish(deinit self, label: String = "") -> CommandBuffer:
        """Finish encoding and return the recorded CommandBuffer.

        Consumes the encoder (linear-type obligation fulfilled).
        """
        var label_sv = str_to_sv(label) if label.byte_length() > 0 else WGPUStringView.null_view()
        var desc_p = alloc[WGPUCommandBufferDescriptor](1)
        desc_p[] = WGPUCommandBufferDescriptor(OpaquePtr(), label_sv)
        var result = self._lib[].command_encoder_finish(self._handle, desc_p)
        desc_p.free()
        # Release the encoder handle — no __del__ with @explicit_destroy.
        self._lib[].command_encoder_release(self._handle)
        return CommandBuffer(self._lib, result)

    def abandon(deinit self):
        """Release the encoder without finishing — for error-recovery paths."""
        self._lib[].command_encoder_release(self._handle)
