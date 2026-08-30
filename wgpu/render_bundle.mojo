"""
wgpu.render_bundle — RenderBundle and RenderBundleEncoder RAII wrappers.

A RenderBundle is a pre-recorded sequence of draw commands that can be replayed
in any render pass via RenderPassEncoder.execute_bundles(). This avoids
re-issuing identical draw state on every frame.

Usage:
    # Record once
    var enc = device.create_render_bundle_encoder(formats, "my_bundle_enc")
    enc.set_pipeline(pipeline)
    enc.set_bind_group(0, bind_group)
    enc.draw(vertex_count)
    var bundle = enc^.finish("my_bundle")

    # Replay every frame inside a render pass
    rpass.execute_bundles(List[RenderBundle](bundle))
"""

from std.memory import ArcPointer
from wgpu._ffi.lib import WGPULib
from wgpu._ffi.nulls import null_opaque
from wgpu._ffi.types import (
    WGPURenderBundleHandle, WGPURenderBundleEncoderHandle,
    WGPURenderPipelineHandle, WGPUBindGroupHandle,
    WGPUBufferHandle, WGPUIndexFormat,
)
from wgpu._ffi.structs import (
    WGPUStringView, WGPURenderBundleDescriptor, str_to_sv,
)
from wgpu._ffi.handles import RenderBundleHandle, RenderBundleEncoderHandle
from wgpu._ffi.alloc_guard import AllocGuard
from wgpu.pipeline import RenderPipeline
from wgpu.bind_group import BindGroup
from wgpu.buffer import Buffer


struct RenderBundle(Movable, Boolable):
    """RAII wrapper around a WGPURenderBundle.

    Owns the recorded command sequence. Drop to release wgpu-native handle.
    """

    var _lib:    ArcPointer[WGPULib]
    var _handle: WGPURenderBundleHandle

    def __init__(out self, lib: ArcPointer[WGPULib], handle: WGPURenderBundleHandle):
        self._lib    = lib
        self._handle = handle

    def __init__(out self, *, deinit move: Self):
        self._lib    = move._lib^
        self._handle = move._handle

    def __del__(deinit self):
        self._lib[].render_bundle_release(self._handle)

    def handle(self) -> RenderBundleHandle:
        return RenderBundleHandle(self._handle)

    def __bool__(self) -> Bool:
        return Int(self._handle) != 0

@explicit_destroy("Must call finish() or abandon()")
struct RenderBundleEncoder(Movable, ImplicitlyDeletable where False):
    """Records draw commands into a RenderBundle.

    Linear type: the compiler enforces that finish() or abandon() is called
    before the encoder leaves scope.
    """

    var _lib:    ArcPointer[WGPULib]
    var _handle: WGPURenderBundleEncoderHandle

    def __init__(
        out self,
        lib: ArcPointer[WGPULib],
        handle: WGPURenderBundleEncoderHandle,
    ):
        self._lib    = lib
        self._handle = handle

    def __init__(out self, *, deinit move: Self):
        self._lib    = move._lib^
        self._handle = move._handle

    # ------------------------------------------------------------------
    # Linear-type disposal
    # ------------------------------------------------------------------

    def finish(deinit self, label: String = "") raises -> RenderBundle:
        """Finish recording and return a RenderBundle (linear-type obligation)."""
        var label_sv = str_to_sv(label) if label.byte_length() > 0 else WGPUStringView.null_view()
        with AllocGuard[WGPURenderBundleDescriptor](1) as desc_p:
            desc_p[] = WGPURenderBundleDescriptor(null_opaque(), label_sv)
            var result = self._lib[].render_bundle_encoder_finish(self._handle, desc_p)
            self._lib[].render_bundle_encoder_release(self._handle)
            return RenderBundle(self._lib, result)

    def abandon(deinit self):
        """Release without finishing — for error-recovery paths."""
        self._lib[].render_bundle_encoder_release(self._handle)

    # ------------------------------------------------------------------
    # Draw state
    # ------------------------------------------------------------------

    def set_pipeline(self, pipeline: WGPURenderPipelineHandle):
        self._lib[].render_bundle_encoder_set_pipeline(self._handle, pipeline)

    def set_pipeline(self, pipeline: RenderPipeline):
        self._lib[].render_bundle_encoder_set_pipeline(self._handle, pipeline.handle().raw)

    def set_bind_group(self, index: UInt32, bind_group: WGPUBindGroupHandle):
        self._lib[].render_bundle_encoder_set_bind_group(
            self._handle, index, bind_group, UInt(0), null_opaque()
        )

    def set_bind_group(self, index: UInt32, bind_group: BindGroup):
        self._lib[].render_bundle_encoder_set_bind_group(
            self._handle, index, bind_group.handle().raw, UInt(0), null_opaque()
        )

    def set_vertex_buffer(
        self,
        slot: UInt32,
        buffer: WGPUBufferHandle,
        offset: UInt64 = 0,
        size: UInt64 = UInt64.MAX,
    ):
        self._lib[].render_bundle_encoder_set_vertex_buffer(
            self._handle, slot, buffer, offset, size
        )

    def set_vertex_buffer(
        self,
        slot: UInt32,
        buffer: Buffer,
        offset: UInt64 = 0,
        size: UInt64 = UInt64.MAX,
    ):
        self._lib[].render_bundle_encoder_set_vertex_buffer(
            self._handle, slot, buffer.handle().raw, offset, size
        )

    def set_index_buffer(
        self,
        buffer: WGPUBufferHandle,
        format: UInt32,
        offset: UInt64 = 0,
        size: UInt64 = UInt64.MAX,
    ):
        self._lib[].render_bundle_encoder_set_index_buffer(
            self._handle, buffer, format, offset, size
        )

    def set_index_buffer(
        self,
        buffer: Buffer,
        format: UInt32,
        offset: UInt64 = 0,
        size: UInt64 = UInt64.MAX,
    ):
        self._lib[].render_bundle_encoder_set_index_buffer(
            self._handle, buffer.handle().raw, format, offset, size
        )

    # ------------------------------------------------------------------
    # Draw calls
    # ------------------------------------------------------------------

    def draw(
        self,
        vertex_count: UInt32,
        instance_count: UInt32 = 1,
        first_vertex: UInt32 = 0,
        first_instance: UInt32 = 0,
    ):
        self._lib[].render_bundle_encoder_draw(
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
        self._lib[].render_bundle_encoder_draw_indexed(
            self._handle, index_count, instance_count, first_index, base_vertex, first_instance
        )

    def draw_indirect(self, buffer: WGPUBufferHandle, offset: UInt64):
        self._lib[].render_bundle_encoder_draw_indirect(self._handle, buffer, offset)

    def draw_indirect(self, buffer: Buffer, offset: UInt64):
        self._lib[].render_bundle_encoder_draw_indirect(
            self._handle, buffer.handle().raw, offset
        )

    def draw_indexed_indirect(self, buffer: WGPUBufferHandle, offset: UInt64):
        self._lib[].render_bundle_encoder_draw_indexed_indirect(
            self._handle, buffer, offset
        )

    def draw_indexed_indirect(self, buffer: Buffer, offset: UInt64):
        self._lib[].render_bundle_encoder_draw_indexed_indirect(
            self._handle, buffer.handle().raw, offset
        )

    # ------------------------------------------------------------------
    # Debug groups
    # ------------------------------------------------------------------

    def push_debug_group(self, label: String):
        var sv = str_to_sv(label) if label.byte_length() > 0 else WGPUStringView.null_view()
        self._lib[].render_bundle_encoder_push_debug_group(self._handle, sv)

    def pop_debug_group(self):
        self._lib[].render_bundle_encoder_pop_debug_group(self._handle)

    def insert_debug_marker(self, label: String):
        var sv = str_to_sv(label) if label.byte_length() > 0 else WGPUStringView.null_view()
        self._lib[].render_bundle_encoder_insert_debug_marker(self._handle, sv)

    # ------------------------------------------------------------------
    # Labels / push constants
    # ------------------------------------------------------------------

    def set_immediates(
        self, offset: UInt32, size_bytes: UInt32, data: OpaquePointer[MutUntrackedOrigin]
    ):
        """Write push-constant data (requires PushConstants feature)."""
        self._lib[].render_bundle_encoder_set_immediates(
            self._handle, offset, size_bytes, data
        )

    # ------------------------------------------------------------------
    # Handle access
    # ------------------------------------------------------------------

    def handle(self) -> RenderBundleEncoderHandle:
        return RenderBundleEncoderHandle(self._handle)
