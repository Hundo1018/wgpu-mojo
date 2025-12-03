"""
wgpu.render_pass — RenderPassEncoder RAII wrapper.
"""

from std.memory import ArcPointer
from wgpu._ffi.lib import WGPULib
from wgpu._ffi.types import (
    OpaquePtr,
    WGPURenderPassEncoderHandle, WGPURenderPipelineHandle,
    WGPUBindGroupHandle, WGPUBufferHandle, WGPURenderBundleHandle,
    WGPUQuerySetHandle,
)
from wgpu._ffi.structs import WGPUStringView, WGPUColor, str_to_sv
from wgpu._ffi.handles import RenderPassEncoderHandle
from wgpu.pipeline import RenderPipeline
from wgpu.bind_group import BindGroup
from wgpu.buffer import Buffer
from wgpu.query_set import QuerySet
from wgpu.texture import TextureView


@explicit_destroy("Must call end() or abandon()")
struct FrameRenderPass(Movable):
    """High-level linear render pass that retains the frame TextureView.

    This wrapper keeps the underlying TextureView alive for the full pass
    lifetime, so callers do not need manual `_ = view^` pins.
    """

    var _lib:    ArcPointer[WGPULib]
    var _handle: WGPURenderPassEncoderHandle
    var _view:   TextureView

    def __init__(
        out self,
        lib: ArcPointer[WGPULib],
        handle: WGPURenderPassEncoderHandle,
        var view: TextureView,
    ):
        self._lib    = lib
        self._handle = handle
        self._view   = view^

    def __init__(out self, *, deinit take: Self):
        self._lib    = take._lib^
        self._handle = take._handle
        self._view   = take._view^

    def set_pipeline(self, pipeline: WGPURenderPipelineHandle):
        self._lib[].render_pass_set_pipeline(self._handle, pipeline)

    def set_pipeline(self, pipeline: RenderPipeline):
        self._lib[].render_pass_set_pipeline(self._handle, pipeline.handle().raw)

    def draw(
        self,
        vertex_count: UInt32,
        instance_count: UInt32 = 1,
        first_vertex: UInt32 = 0,
        first_instance: UInt32 = 0,
    ):
        self._lib[].render_pass_draw(
            self._handle, vertex_count, instance_count, first_vertex, first_instance
        )

    def end(deinit self):
        self._lib[].render_pass_end(self._handle)
        self._lib[].render_pass_release(self._handle)

    def abandon(deinit self):
        self._lib[].render_pass_release(self._handle)


@explicit_destroy("Must call end() or abandon()")
struct RenderPassEncoder(Movable):
    """RAII wrapper around a WGPURenderPassEncoder.

    Linear type: the compiler enforces that `end()` or `abandon()` is
    called before the encoder leaves scope.
    """

    var _lib:    ArcPointer[WGPULib]
    var _handle: WGPURenderPassEncoderHandle

    def __init__(out self, lib: ArcPointer[WGPULib], handle: WGPURenderPassEncoderHandle):
        self._lib    = lib
        self._handle = handle

    def __init__(out self, *, deinit take: Self):
        self._lib    = take._lib^
        self._handle = take._handle

    def set_pipeline(self, pipeline: WGPURenderPipelineHandle):
        self._lib[].render_pass_set_pipeline(self._handle, pipeline)

    def set_pipeline(self, pipeline: RenderPipeline):
        """Wrapper-first overload — accepts RAII RenderPipeline directly."""
        self._lib[].render_pass_set_pipeline(self._handle, pipeline.handle().raw)

    def set_bind_group(self, index: UInt32, bind_group: WGPUBindGroupHandle):
        self._lib[].render_pass_set_bind_group(
            self._handle, index, bind_group, UInt(0), OpaquePtr()
        )

    def set_bind_group(self, index: UInt32, bind_group: BindGroup):
        """Wrapper-first overload — accepts RAII BindGroup directly."""
        self._lib[].render_pass_set_bind_group(
            self._handle, index, bind_group.handle().raw, UInt(0), OpaquePtr()
        )

    def set_bind_group_with_offsets(
        self,
        index: UInt32,
        bind_group: WGPUBindGroupHandle,
        offsets: List[UInt32],
    ):
        var ptr = OpaquePtr(unsafe_from_address=Int(offsets.unsafe_ptr()))
        self._lib[].render_pass_set_bind_group(
            self._handle, index, bind_group, UInt(len(offsets)), ptr
        )

    def set_vertex_buffer(
        self,
        slot: UInt32,
        buffer: WGPUBufferHandle,
        offset: UInt64 = 0,
        size: UInt64 = 0,
    ):
        self._lib[].render_pass_set_vertex_buffer(self._handle, slot, buffer, offset, size)

    def set_vertex_buffer(
        self,
        slot: UInt32,
        buffer: Buffer,
        offset: UInt64 = 0,
        size: UInt64 = 0,
    ):
        """Wrapper-first overload — accepts RAII Buffer directly."""
        self._lib[].render_pass_set_vertex_buffer(self._handle, slot, buffer.handle().raw, offset, size)

    def set_index_buffer(
        self,
        buffer: WGPUBufferHandle,
        format: UInt32,
        offset: UInt64 = 0,
        size: UInt64 = 0,
    ):
        self._lib[].render_pass_set_index_buffer(self._handle, buffer, format, offset, size)

    def set_index_buffer(
        self,
        buffer: Buffer,
        format: UInt32,
        offset: UInt64 = 0,
        size: UInt64 = 0,
    ):
        """Wrapper-first overload — accepts RAII Buffer directly."""
        self._lib[].render_pass_set_index_buffer(self._handle, buffer.handle().raw, format, offset, size)

    def draw(
        self,
        vertex_count: UInt32,
        instance_count: UInt32 = 1,
        first_vertex: UInt32 = 0,
        first_instance: UInt32 = 0,
    ):
        self._lib[].render_pass_draw(
            self._handle, vertex_count, instance_count, first_vertex, first_instance
        )

    def draw_indexed(
        self,
        index_count: UInt32,
        instance_count: UInt32 = 1,
        first_index: UInt32 = 0,
        base_vertex: Int32 = 0,
        first_instance: UInt32 = 0,
    ):
        self._lib[].render_pass_draw_indexed(
            self._handle, index_count, instance_count, first_index, base_vertex, first_instance
        )

    def draw_indirect(self, buffer: WGPUBufferHandle, offset: UInt64):
        self._lib[].render_pass_draw_indirect(self._handle, buffer, offset)

    def draw_indirect(self, buffer: Buffer, offset: UInt64):
        """Wrapper-first overload — accepts RAII Buffer directly."""
        self._lib[].render_pass_draw_indirect(self._handle, buffer.handle().raw, offset)

    def draw_indexed_indirect(self, buffer: WGPUBufferHandle, offset: UInt64):
        self._lib[].render_pass_draw_indexed_indirect(self._handle, buffer, offset)

    def draw_indexed_indirect(self, buffer: Buffer, offset: UInt64):
        """Wrapper-first overload — accepts RAII Buffer directly."""
        self._lib[].render_pass_draw_indexed_indirect(self._handle, buffer.handle().raw, offset)

    def set_viewport(
        self,
        x: Float32, y: Float32,
        width: Float32, height: Float32,
        min_depth: Float32 = 0.0,
        max_depth: Float32 = 1.0,
    ):
        self._lib[].render_pass_set_viewport(
            self._handle, x, y, width, height, min_depth, max_depth
        )

    def set_scissor_rect(self, x: UInt32, y: UInt32, width: UInt32, height: UInt32):
        self._lib[].render_pass_set_scissor_rect(self._handle, x, y, width, height)

    def set_blend_constant(self, color: UnsafePointer[WGPUColor, MutExternalOrigin]):
        self._lib[].render_pass_set_blend_constant(self._handle, color.bitcast[NoneType]())

    def set_stencil_reference(self, reference: UInt32):
        self._lib[].render_pass_set_stencil_reference(self._handle, reference)

    def begin_occlusion_query(self, query_index: UInt32):
        self._lib[].render_pass_begin_occlusion_query(self._handle, query_index)

    def end_occlusion_query(self):
        self._lib[].render_pass_end_occlusion_query(self._handle)

    def execute_bundles(self, bundles: List[WGPURenderBundleHandle]):
        var ptr = rebind[UnsafePointer[WGPURenderBundleHandle, MutExternalOrigin]](bundles.unsafe_ptr())
        self._lib[].render_pass_execute_bundles(self._handle, UInt(len(bundles)), ptr)

    # ------------------------------------------------------------------
    # Debug groups
    # ------------------------------------------------------------------

    def push_debug_group(self, label: String):
        var sv = str_to_sv(label) if label.byte_length() > 0 else WGPUStringView.null_view()
        self._lib[].render_pass_push_debug_group(self._handle, sv)

    def pop_debug_group(self):
        self._lib[].render_pass_pop_debug_group(self._handle)

    def insert_debug_marker(self, label: String):
        var sv = str_to_sv(label) if label.byte_length() > 0 else WGPUStringView.null_view()
        self._lib[].render_pass_insert_debug_marker(self._handle, sv)

    # ------------------------------------------------------------------
    # Label
    # ------------------------------------------------------------------

    def set_label(self, label: String):
        var sv = str_to_sv(label) if label.byte_length() > 0 else WGPUStringView.null_view()
        self._lib[].render_pass_set_label(self._handle, sv)

    def end(deinit self):
        """End the render pass and release the encoder (linear-type obligation)."""
        self._lib[].render_pass_end(self._handle)
        self._lib[].render_pass_release(self._handle)

    def abandon(deinit self):
        """Release without ending — for error-recovery paths."""
        self._lib[].render_pass_release(self._handle)

    def handle(self) -> RenderPassEncoderHandle:
        return RenderPassEncoderHandle(self._handle)

    # ------------------------------------------------------------------
    # wgpu-native extensions
    # ------------------------------------------------------------------

    def set_push_constants(
        self, stages: UInt64, offset: UInt32, size_bytes: UInt32, data: OpaquePtr
    ):
        self._lib[].render_pass_set_push_constants(
            self._handle, stages, offset, size_bytes, data
        )

    def multi_draw_indirect(
        self, buffer: WGPUBufferHandle, offset: UInt64, count: UInt32
    ):
        self._lib[].render_pass_multi_draw_indirect(self._handle, buffer, offset, count)

    def multi_draw_indirect(
        self, buffer: Buffer, offset: UInt64, count: UInt32
    ):
        """Wrapper-first overload — accepts RAII Buffer directly."""
        self._lib[].render_pass_multi_draw_indirect(self._handle, buffer.handle().raw, offset, count)

    def multi_draw_indexed_indirect(
        self, buffer: WGPUBufferHandle, offset: UInt64, count: UInt32
    ):
        self._lib[].render_pass_multi_draw_indexed_indirect(
            self._handle, buffer, offset, count
        )

    def multi_draw_indexed_indirect(
        self, buffer: Buffer, offset: UInt64, count: UInt32
    ):
        """Wrapper-first overload — accepts RAII Buffer directly."""
        self._lib[].render_pass_multi_draw_indexed_indirect(
            self._handle, buffer.handle().raw, offset, count
        )

    def multi_draw_indirect_count(
        self,
        buffer: WGPUBufferHandle,
        offset: UInt64,
        count_buffer: WGPUBufferHandle,
        count_buffer_offset: UInt64,
        max_count: UInt32,
    ):
        self._lib[].render_pass_multi_draw_indirect_count(
            self._handle, buffer, offset, count_buffer, count_buffer_offset, max_count
        )

    def multi_draw_indirect_count(
        self,
        buffer: Buffer,
        offset: UInt64,
        count_buffer: Buffer,
        count_buffer_offset: UInt64,
        max_count: UInt32,
    ):
        """Wrapper-first overload — accepts RAII Buffers directly."""
        self._lib[].render_pass_multi_draw_indirect_count(
            self._handle, buffer.handle().raw, offset,
            count_buffer.handle().raw, count_buffer_offset, max_count
        )

    def multi_draw_indexed_indirect_count(
        self,
        buffer: WGPUBufferHandle,
        offset: UInt64,
        count_buffer: WGPUBufferHandle,
        count_buffer_offset: UInt64,
        max_count: UInt32,
    ):
        self._lib[].render_pass_multi_draw_indexed_indirect_count(
            self._handle, buffer, offset, count_buffer, count_buffer_offset, max_count
        )

    def multi_draw_indexed_indirect_count(
        self,
        buffer: Buffer,
        offset: UInt64,
        count_buffer: Buffer,
        count_buffer_offset: UInt64,
        max_count: UInt32,
    ):
        """Wrapper-first overload — accepts RAII Buffers directly."""
        self._lib[].render_pass_multi_draw_indexed_indirect_count(
            self._handle, buffer.handle().raw, offset,
            count_buffer.handle().raw, count_buffer_offset, max_count
        )

    def begin_pipeline_statistics_query(
        self, query_set: WGPUQuerySetHandle, query_index: UInt32
    ):
        self._lib[].render_pass_begin_pipeline_statistics_query(
            self._handle, query_set, query_index
        )

    def begin_pipeline_statistics_query(
        self, query_set: QuerySet, query_index: UInt32
    ):
        """Wrapper-first overload — accepts RAII QuerySet directly."""
        self._lib[].render_pass_begin_pipeline_statistics_query(
            self._handle, query_set.handle().raw, query_index
        )

    def end_pipeline_statistics_query(self):
        self._lib[].render_pass_end_pipeline_statistics_query(self._handle)

    def write_timestamp(self, query_set: WGPUQuerySetHandle, query_index: UInt32):
        self._lib[].render_pass_write_timestamp(self._handle, query_set, query_index)

    def write_timestamp(self, query_set: QuerySet, query_index: UInt32):
        """Wrapper-first overload — accepts RAII QuerySet directly."""
        self._lib[].render_pass_write_timestamp(self._handle, query_set.handle().raw, query_index)
