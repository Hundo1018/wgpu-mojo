"""
CommandEncoder RAII wrapper.
"""

from std.memory import ArcPointer
from wgpu._ffi.lib import WGPULib
from wgpu._backend.wgpu_native.alloc_guard import raw_alloc
from wgpu._ffi.nulls import null_opaque, null_ptr, null_any_ptr
from wgpu._ffi.types import (
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
    WGPUTexelCopyBufferLayout,
    WGPUTexelCopyBufferInfo,
    WGPUTexelCopyTextureInfo,
    WGPUExtent3D,
    WGPUOrigin3D,
    WGPUColor,
    WGPUStringView,
    str_to_sv,
)
from wgpu.compute_pass import ComputePassEncoder
from wgpu.render_pass import RenderPassEncoder, FrameRenderPass
from wgpu.buffer import Buffer
from wgpu.query_set import QuerySet
from wgpu.texture import Texture, TextureView


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

    def __init__(out self, *, deinit move: Self):
        self._lib    = move._lib^
        self._handle = move._handle

    def __deinit__(deinit self):
        self._lib[].command_buffer_release(self._handle)

    def clone(self) -> Self:
        """Share ownership of this GPU object via `wgpuCommandBufferAddRef`.

        A refcount bump, not a GPU-side copy: both wrappers refer to the same
        object and each releases on drop, so it survives until the last one
        goes away.
        """
        self._lib[].command_buffer_add_ref(self._handle)
        return Self(self._lib, self._handle)

    def handle(self) -> CommandBufferHandle:
        return CommandBufferHandle(self._handle)

    def raw(self) -> WGPUCommandBufferHandle:
        """Return the raw opaque handle (for FFI)."""
        return self._handle

    def __bool__(self) -> Bool:
        return Int(self._handle) != 0


@explicit_destroy("Must call finish() or abandon()")
struct CommandEncoder(Movable, Deinitable where False):
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

    def __init__(out self, *, deinit move: Self):
        self._lib    = move._lib^
        self._handle = move._handle

    def handle(self) -> CommandEncoderHandle:
        return CommandEncoderHandle(self._handle)

    # ------------------------------------------------------------------
    # Pass creation
    # ------------------------------------------------------------------

    def begin_compute_pass(
        self, label: String = ""
    ) -> ComputePassEncoder:
        var label_sv = str_to_sv(label) if label.byte_length() > 0 else WGPUStringView.null_view()
        var desc_p = raw_alloc[WGPUComputePassDescriptor](1)
        desc_p[] = WGPUComputePassDescriptor(null_opaque(), label_sv, null_opaque())
        var result = self._lib[].command_encoder_begin_compute_pass(self._handle, desc_p)
        desc_p.unsafe_free()
        return ComputePassEncoder(self._lib, result)

    def begin_render_pass(
        self, desc: Pointer[WGPURenderPassDescriptor, MutUntrackedOrigin]
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

        var color_att_p = raw_alloc[WGPURenderPassColorAttachment](1)
        color_att_p[unsafe_offset=0] = WGPURenderPassColorAttachment(
            null_opaque(),
            view.handle().raw,
            UInt32(0xFFFFFFFF),
            null_opaque(),
            UInt32(2),
            UInt32(1),
            clear_color,
        )

        var rp_desc_p = raw_alloc[WGPURenderPassDescriptor](1)
        rp_desc_p[unsafe_offset=0] = WGPURenderPassDescriptor(
            null_opaque(),
            label_sv,
            UInt(1),
            color_att_p,
            null_ptr[WGPURenderPassDepthStencilAttachment](),
            null_opaque(),
            null_ptr[WGPUPassTimestampWrites](),
        )

        var result = self._lib[].command_encoder_begin_render_pass(self._handle, rp_desc_p)
        color_att_p.unsafe_free()
        rp_desc_p.unsafe_free()
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
            null_ptr[WGPUTextureViewDescriptor](),
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
        src: Pointer[WGPUTexelCopyBufferInfo, MutUntrackedOrigin],
        dst: Pointer[WGPUTexelCopyTextureInfo, MutUntrackedOrigin],
        size: Pointer[WGPUExtent3D, MutUntrackedOrigin],
    ):
        self._lib[].command_encoder_copy_buffer_to_texture(self._handle, src, dst, size)

    def copy_texture_to_buffer(
        self,
        src: Pointer[WGPUTexelCopyTextureInfo, MutUntrackedOrigin],
        dst: Pointer[WGPUTexelCopyBufferInfo, MutUntrackedOrigin],
        size: Pointer[WGPUExtent3D, MutUntrackedOrigin],
    ):
        self._lib[].command_encoder_copy_texture_to_buffer(self._handle, src, dst, size)

    def copy_buffer_to_texture(
        self,
        src: Buffer,
        src_offset: UInt64,
        bytes_per_row: UInt32,
        rows_per_image: UInt32,
        dst: Texture,
        width: UInt32,
        height: UInt32,
        depth_or_array_layers: UInt32 = 1,
        mip_level: UInt32 = 0,
        origin: WGPUOrigin3D = WGPUOrigin3D(UInt32(0), UInt32(0), UInt32(0)),
        aspect: UInt32 = 0,
    ):
        var src_p = raw_alloc[WGPUTexelCopyBufferInfo](1)
        src_p[unsafe_offset=0] = WGPUTexelCopyBufferInfo(
            WGPUTexelCopyBufferLayout(src_offset, bytes_per_row, rows_per_image),
            src.handle().raw,
        )
        var dst_p = raw_alloc[WGPUTexelCopyTextureInfo](1)
        dst_p[unsafe_offset=0] = WGPUTexelCopyTextureInfo(
            dst.handle().raw,
            mip_level,
            origin,
            aspect,
        )
        var size_p = raw_alloc[WGPUExtent3D](1)
        size_p[unsafe_offset=0] = WGPUExtent3D(width, height, depth_or_array_layers)
        self._lib[].command_encoder_copy_buffer_to_texture(self._handle, src_p, dst_p, size_p)
        src_p.unsafe_free()
        dst_p.unsafe_free()
        size_p.unsafe_free()

    def copy_texture_to_buffer(
        self,
        src: Texture,
        dst: Buffer,
        dst_offset: UInt64,
        bytes_per_row: UInt32,
        rows_per_image: UInt32,
        width: UInt32,
        height: UInt32,
        depth_or_array_layers: UInt32 = 1,
        mip_level: UInt32 = 0,
        origin: WGPUOrigin3D = WGPUOrigin3D(UInt32(0), UInt32(0), UInt32(0)),
        aspect: UInt32 = 0,
    ):
        var src_p = raw_alloc[WGPUTexelCopyTextureInfo](1)
        src_p[unsafe_offset=0] = WGPUTexelCopyTextureInfo(
            src.handle().raw,
            mip_level,
            origin,
            aspect,
        )
        var dst_p = raw_alloc[WGPUTexelCopyBufferInfo](1)
        dst_p[unsafe_offset=0] = WGPUTexelCopyBufferInfo(
            WGPUTexelCopyBufferLayout(dst_offset, bytes_per_row, rows_per_image),
            dst.handle().raw,
        )
        var size_p = raw_alloc[WGPUExtent3D](1)
        size_p[unsafe_offset=0] = WGPUExtent3D(width, height, depth_or_array_layers)
        self._lib[].command_encoder_copy_texture_to_buffer(self._handle, src_p, dst_p, size_p)
        src_p.unsafe_free()
        dst_p.unsafe_free()
        size_p.unsafe_free()

    def copy_texture_to_texture(
        self,
        src: Pointer[WGPUTexelCopyTextureInfo, MutUntrackedOrigin],
        dst: Pointer[WGPUTexelCopyTextureInfo, MutUntrackedOrigin],
        size: Pointer[WGPUExtent3D, MutUntrackedOrigin],
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

    # ------------------------------------------------------------------
    # Finish
    # ------------------------------------------------------------------

    def finish(deinit self, label: String = "") -> CommandBuffer:
        """Finish encoding and return the recorded CommandBuffer.

        Consumes the encoder (linear-type obligation fulfilled).
        """
        var label_sv = str_to_sv(label) if label.byte_length() > 0 else WGPUStringView.null_view()
        var desc_p = raw_alloc[WGPUCommandBufferDescriptor](1)
        desc_p[] = WGPUCommandBufferDescriptor(null_opaque(), label_sv)
        var result = self._lib[].command_encoder_finish(self._handle, desc_p)
        desc_p.unsafe_free()
        # Release the encoder handle — no __del__ with @explicit_destroy.
        self._lib[].command_encoder_release(self._handle)
        return CommandBuffer(self._lib, result)

    def abandon(deinit self):
        """Release the encoder without finishing — for error-recovery paths."""
        self._lib[].command_encoder_release(self._handle)
