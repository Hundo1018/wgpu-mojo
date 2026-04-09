"""
wgpu.render_pass — RenderPassEncoder RAII wrapper.
"""

from wgpu._ffi.lib import WGPULib
from wgpu._ffi.types import (
    OpaquePtr,
    WGPURenderPassEncoderHandle, WGPURenderPipelineHandle,
    WGPUBindGroupHandle, WGPUBufferHandle, WGPURenderBundleHandle,
)
from wgpu._ffi.structs import WGPUStringView, WGPUColor, str_to_sv


struct RenderPassEncoder(Movable):
    """RAII wrapper around a WGPURenderPassEncoder. `end()` must be called."""

    var _lib:    WGPULib
    var _handle: WGPURenderPassEncoderHandle

    def __init__(out self, var lib: WGPULib, handle: WGPURenderPassEncoderHandle):
        self._lib    = lib^
        self._handle = handle

    def __init__(out self, *, deinit take: Self):
        self._lib    = take._lib^
        self._handle = take._handle

    def __del__(deinit self):
        self._lib.render_pass_release(self._handle)

    def set_pipeline(self, pipeline: WGPURenderPipelineHandle):
        self._lib.render_pass_set_pipeline(self._handle, pipeline)

    def set_bind_group(self, index: UInt32, bind_group: WGPUBindGroupHandle):
        self._lib.render_pass_set_bind_group(
            self._handle, index, bind_group, UInt(0), OpaquePtr()
        )

    def set_bind_group_with_offsets(
        self,
        index: UInt32,
        bind_group: WGPUBindGroupHandle,
        offsets: List[UInt32],
    ):
        var ptr = OpaquePtr(unsafe_from_address=Int(offsets.unsafe_ptr()))
        self._lib.render_pass_set_bind_group(
            self._handle, index, bind_group, UInt(len(offsets)), ptr
        )

    def set_vertex_buffer(
        self,
        slot: UInt32,
        buffer: WGPUBufferHandle,
        offset: UInt64 = 0,
        size: UInt64 = 0,
    ):
        self._lib.render_pass_set_vertex_buffer(self._handle, slot, buffer, offset, size)

    def set_index_buffer(
        self,
        buffer: WGPUBufferHandle,
        format: UInt32,
        offset: UInt64 = 0,
        size: UInt64 = 0,
    ):
        self._lib.render_pass_set_index_buffer(self._handle, buffer, format, offset, size)

    def draw(
        self,
        vertex_count: UInt32,
        instance_count: UInt32 = 1,
        first_vertex: UInt32 = 0,
        first_instance: UInt32 = 0,
    ):
        self._lib.render_pass_draw(
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
        self._lib.render_pass_draw_indexed(
            self._handle, index_count, instance_count, first_index, base_vertex, first_instance
        )

    def draw_indirect(self, buffer: WGPUBufferHandle, offset: UInt64):
        self._lib.render_pass_draw_indirect(self._handle, buffer, offset)

    def draw_indexed_indirect(self, buffer: WGPUBufferHandle, offset: UInt64):
        self._lib.render_pass_draw_indexed_indirect(self._handle, buffer, offset)

    def set_viewport(
        self,
        x: Float32, y: Float32,
        width: Float32, height: Float32,
        min_depth: Float32 = 0.0,
        max_depth: Float32 = 1.0,
    ):
        self._lib.render_pass_set_viewport(
            self._handle, x, y, width, height, min_depth, max_depth
        )

    def set_scissor_rect(self, x: UInt32, y: UInt32, width: UInt32, height: UInt32):
        self._lib.render_pass_set_scissor_rect(self._handle, x, y, width, height)

    def set_blend_constant(self, color: UnsafePointer[WGPUColor, MutExternalOrigin]):
        self._lib.render_pass_set_blend_constant(self._handle, color.bitcast[NoneType]())

    def set_stencil_reference(self, reference: UInt32):
        self._lib.render_pass_set_stencil_reference(self._handle, reference)

    def begin_occlusion_query(self, query_index: UInt32):
        self._lib.render_pass_begin_occlusion_query(self._handle, query_index)

    def end_occlusion_query(self):
        self._lib.render_pass_end_occlusion_query(self._handle)

    def execute_bundles(self, bundles: List[WGPURenderBundleHandle]):
        var ptr = rebind[UnsafePointer[WGPURenderBundleHandle, MutExternalOrigin]](bundles.unsafe_ptr())
        self._lib.render_pass_execute_bundles(self._handle, UInt(len(bundles)), ptr)

    # ------------------------------------------------------------------
    # Debug groups
    # ------------------------------------------------------------------

    def push_debug_group(self, label: String):
        var sv = str_to_sv(label) if len(label) > 0 else WGPUStringView.null_view()
        self._lib.render_pass_push_debug_group(self._handle, sv)

    def pop_debug_group(self):
        self._lib.render_pass_pop_debug_group(self._handle)

    def insert_debug_marker(self, label: String):
        var sv = str_to_sv(label) if len(label) > 0 else WGPUStringView.null_view()
        self._lib.render_pass_insert_debug_marker(self._handle, sv)

    # ------------------------------------------------------------------
    # Label
    # ------------------------------------------------------------------

    def set_label(self, label: String):
        var sv = str_to_sv(label) if len(label) > 0 else WGPUStringView.null_view()
        self._lib.render_pass_set_label(self._handle, sv)

    def end(self):
        self._lib.render_pass_end(self._handle)

    def handle(self) -> WGPURenderPassEncoderHandle:
        return self._handle
