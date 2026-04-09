"""
wgpu._ffi.structs — C struct layouts mirroring webgpu.h for FFI.
All structs match the C ABI layout exactly (field order, types).
"""

from wgpu._ffi.types import (
    OpaquePtr, WGPUBool, WGPUFlags,
    WGPUAdapterHandle, WGPUBindGroupHandle, WGPUBindGroupLayoutHandle,
    WGPUBufferHandle, WGPUCommandBufferHandle, WGPUCommandEncoderHandle,
    WGPUComputePassEncoderHandle, WGPUComputePipelineHandle, WGPUDeviceHandle,
    WGPUExternalTextureHandle, WGPUInstanceHandle, WGPUPipelineLayoutHandle,
    WGPUQuerySetHandle, WGPUQueueHandle, WGPURenderBundleHandle,
    WGPURenderBundleEncoderHandle, WGPURenderPassEncoderHandle,
    WGPURenderPipelineHandle, WGPUSamplerHandle, WGPUShaderModuleHandle,
    WGPUSurfaceHandle, WGPUTextureHandle, WGPUTextureViewHandle,
    WGPUBufferUsage, WGPUColorWriteMask, WGPUMapMode, WGPUShaderStage, WGPUTextureUsage,
    WGPU_STRLEN, WGPUSType, WGPUCallbackMode,
)

# Convenience alias — used in many places for void* userdata
comptime VoidPtr = OpaquePtr

# Self-referencing chain pointer (opaque to avoid recursive struct issue)
comptime WGPUChainedStructPtr = OpaquePtr

# ---------------------------------------------------------------------------
# WGPUStringView — equivalent to { const char* data; size_t length; }
# Pass by value (16 bytes on 64-bit). length=WGPU_STRLEN means null-terminated.
# ---------------------------------------------------------------------------

@fieldwise_init
struct WGPUStringView(TrivialRegisterPassable):
    var data: UnsafePointer[NoneType, MutAnyOrigin]  # void* equivalent; bitcast to read chars
    var length: UInt  # size_t

    @staticmethod
    def null_view() -> WGPUStringView:
        return WGPUStringView(
            UnsafePointer[NoneType, MutAnyOrigin](),
            WGPU_STRLEN,
        )


def str_to_sv(s: String) -> WGPUStringView:
    """Borrow `s` as a WGPUStringView. `s` must outlive the view."""
    var bytes = s.as_bytes()
    var raw = bytes.unsafe_ptr().bitcast[NoneType]()
    # Erase lifetime tracking (unsafe: caller must keep `s` alive while view is in use)
    var ptr = rebind[UnsafePointer[NoneType, MutAnyOrigin]](raw)
    return WGPUStringView(ptr, UInt(len(bytes)))


# ---------------------------------------------------------------------------
# WGPUChainedStruct
# ---------------------------------------------------------------------------

@fieldwise_init
struct WGPUChainedStruct(TrivialRegisterPassable):
    var next: WGPUChainedStructPtr   # actually WGPUChainedStruct*
    var stype: UInt32


# ---------------------------------------------------------------------------
# WGPUFuture — opaque 64-bit future id
# ---------------------------------------------------------------------------

@fieldwise_init
struct WGPUFuture(TrivialRegisterPassable):
    var id: UInt64


# ---------------------------------------------------------------------------
# Callback info structs (10 total)
# ---------------------------------------------------------------------------

@fieldwise_init
struct WGPUBufferMapCallbackInfo:
    var next_in_chain: WGPUChainedStructPtr
    var mode: UInt32
    var callback: VoidPtr   # WGPUBufferMapCallback fn ptr
    var userdata1: VoidPtr
    var userdata2: VoidPtr


@fieldwise_init
struct WGPUCompilationInfoCallbackInfo:
    var next_in_chain: WGPUChainedStructPtr
    var mode: UInt32
    var callback: VoidPtr   # WGPUCompilationInfoCallback fn ptr
    var userdata1: VoidPtr
    var userdata2: VoidPtr


@fieldwise_init
struct WGPUCreateComputePipelineAsyncCallbackInfo:
    var next_in_chain: WGPUChainedStructPtr
    var mode: UInt32
    var callback: VoidPtr
    var userdata1: VoidPtr
    var userdata2: VoidPtr


@fieldwise_init
struct WGPUCreateRenderPipelineAsyncCallbackInfo:
    var next_in_chain: WGPUChainedStructPtr
    var mode: UInt32
    var callback: VoidPtr
    var userdata1: VoidPtr
    var userdata2: VoidPtr


@fieldwise_init
struct WGPUDeviceLostCallbackInfo(TrivialRegisterPassable):
    var next_in_chain: WGPUChainedStructPtr
    var mode: UInt32
    var callback: VoidPtr   # WGPUDeviceLostCallback fn ptr
    var userdata1: VoidPtr
    var userdata2: VoidPtr


@fieldwise_init
struct WGPUPopErrorScopeCallbackInfo(TrivialRegisterPassable):
    var next_in_chain: WGPUChainedStructPtr
    var mode: UInt32
    var callback: VoidPtr
    var userdata1: VoidPtr
    var userdata2: VoidPtr


@fieldwise_init
struct WGPUQueueWorkDoneCallbackInfo(TrivialRegisterPassable):
    var next_in_chain: WGPUChainedStructPtr
    var mode: UInt32
    var callback: VoidPtr   # WGPUQueueWorkDoneCallback fn ptr
    var userdata1: VoidPtr
    var userdata2: VoidPtr


@fieldwise_init
struct WGPURequestAdapterCallbackInfo(TrivialRegisterPassable):
    var next_in_chain: WGPUChainedStructPtr
    var mode: UInt32
    var callback: VoidPtr   # WGPURequestAdapterCallback fn ptr
    var userdata1: VoidPtr
    var userdata2: VoidPtr


@fieldwise_init
struct WGPURequestDeviceCallbackInfo(TrivialRegisterPassable):
    var next_in_chain: WGPUChainedStructPtr
    var mode: UInt32
    var callback: VoidPtr   # WGPURequestDeviceCallback fn ptr
    var userdata1: VoidPtr
    var userdata2: VoidPtr


@fieldwise_init
struct WGPUUncapturedErrorCallbackInfo(TrivialRegisterPassable):
    var next_in_chain: WGPUChainedStructPtr
    var callback: VoidPtr   # WGPUUncapturedErrorCallback fn ptr
    var userdata1: VoidPtr
    var userdata2: VoidPtr


# ---------------------------------------------------------------------------
# Core data structs
# ---------------------------------------------------------------------------

@fieldwise_init
struct WGPUAdapterInfo(TrivialRegisterPassable):
    var next_in_chain: WGPUChainedStructPtr
    var vendor: WGPUStringView
    var architecture: WGPUStringView
    var device: WGPUStringView
    var description: WGPUStringView
    var backend_type: UInt32
    var adapter_type: UInt32
    var vendor_id: UInt32
    var device_id: UInt32
    var subgroup_min_size: UInt32
    var subgroup_max_size: UInt32


@fieldwise_init
struct WGPUBlendComponent(TrivialRegisterPassable):
    var operation: UInt32
    var src_factor: UInt32
    var dst_factor: UInt32


@fieldwise_init
struct WGPUBlendState(TrivialRegisterPassable):
    var color: WGPUBlendComponent
    var alpha: WGPUBlendComponent


@fieldwise_init
struct WGPUColor(TrivialRegisterPassable):
    var r: Float64
    var g: Float64
    var b: Float64
    var a: Float64


@fieldwise_init
struct WGPUExtent3D(TrivialRegisterPassable):
    var width: UInt32
    var height: UInt32
    var depth_or_array_layers: UInt32


@fieldwise_init
struct WGPUOrigin3D(TrivialRegisterPassable):
    var x: UInt32
    var y: UInt32
    var z: UInt32


@fieldwise_init
struct WGPUFutureWaitInfo:
    var future: WGPUFuture
    var completed: UInt32   # WGPUBool


@fieldwise_init
struct WGPULimits(TrivialRegisterPassable):
    var next_in_chain: WGPUChainedStructPtr
    var max_texture_dimension_1d: UInt32
    var max_texture_dimension_2d: UInt32
    var max_texture_dimension_3d: UInt32
    var max_texture_array_layers: UInt32
    var max_bind_groups: UInt32
    var max_bind_groups_plus_vertex_buffers: UInt32
    var max_bindings_per_bind_group: UInt32
    var max_dynamic_uniform_buffers_per_pipeline_layout: UInt32
    var max_dynamic_storage_buffers_per_pipeline_layout: UInt32
    var max_sampled_textures_per_shader_stage: UInt32
    var max_samplers_per_shader_stage: UInt32
    var max_storage_buffers_per_shader_stage: UInt32
    var max_storage_textures_per_shader_stage: UInt32
    var max_uniform_buffers_per_shader_stage: UInt32
    var max_uniform_buffer_binding_size: UInt64
    var max_storage_buffer_binding_size: UInt64
    var min_uniform_buffer_offset_alignment: UInt32
    var min_storage_buffer_offset_alignment: UInt32
    var max_vertex_buffers: UInt32
    var max_buffer_size: UInt64
    var max_vertex_attributes: UInt32
    var max_vertex_buffer_array_stride: UInt32
    var max_inter_stage_shader_variables: UInt32
    var max_color_attachments: UInt32
    var max_color_attachment_bytes_per_sample: UInt32
    var max_compute_workgroup_storage_size: UInt32
    var max_compute_invocations_per_workgroup: UInt32
    var max_compute_workgroup_size_x: UInt32
    var max_compute_workgroup_size_y: UInt32
    var max_compute_workgroup_size_z: UInt32
    var max_compute_workgroups_per_dimension: UInt32
    var max_immediate_size: UInt32


@fieldwise_init
struct WGPUBufferBindingLayout(TrivialRegisterPassable):
    var next_in_chain: WGPUChainedStructPtr
    var type: UInt32
    var has_dynamic_offset: UInt32   # WGPUBool
    var min_binding_size: UInt64


@fieldwise_init
struct WGPUSamplerBindingLayout(TrivialRegisterPassable):
    var next_in_chain: WGPUChainedStructPtr
    var type: UInt32


@fieldwise_init
struct WGPUTextureBindingLayout(TrivialRegisterPassable):
    var next_in_chain: WGPUChainedStructPtr
    var sample_type: UInt32
    var view_dimension: UInt32
    var multisampled: UInt32   # WGPUBool


@fieldwise_init
struct WGPUStorageTextureBindingLayout(TrivialRegisterPassable):
    var next_in_chain: WGPUChainedStructPtr
    var access: UInt32
    var format: UInt32
    var view_dimension: UInt32


@fieldwise_init
struct WGPUBindGroupLayoutEntry(TrivialRegisterPassable):
    var next_in_chain: WGPUChainedStructPtr
    var binding: UInt32
    var visibility: UInt64   # WGPUShaderStage flags
    var binding_array_size: UInt32
    var buffer: WGPUBufferBindingLayout
    var sampler: WGPUSamplerBindingLayout
    var texture: WGPUTextureBindingLayout
    var storage_texture: WGPUStorageTextureBindingLayout


@fieldwise_init
struct WGPUBindGroupLayoutDescriptor(TrivialRegisterPassable):
    var next_in_chain: WGPUChainedStructPtr
    var label: WGPUStringView
    var entry_count: UInt
    var entries: UnsafePointer[WGPUBindGroupLayoutEntry, MutExternalOrigin]


@fieldwise_init
struct WGPUBindGroupEntry(TrivialRegisterPassable):
    var next_in_chain: WGPUChainedStructPtr
    var binding: UInt32
    var buffer: WGPUBufferHandle
    var offset: UInt64
    var size: UInt64
    var sampler: WGPUSamplerHandle
    var texture_view: WGPUTextureViewHandle


@fieldwise_init
struct WGPUBindGroupDescriptor(TrivialRegisterPassable):
    var next_in_chain: WGPUChainedStructPtr
    var label: WGPUStringView
    var layout: WGPUBindGroupLayoutHandle
    var entry_count: UInt
    var entries: UnsafePointer[WGPUBindGroupEntry, MutExternalOrigin]


@fieldwise_init
struct WGPUBufferDescriptor(TrivialRegisterPassable):
    var next_in_chain: WGPUChainedStructPtr
    var label: WGPUStringView
    var usage: UInt64   # WGPUBufferUsage flags
    var size: UInt64
    var mapped_at_creation: UInt32   # WGPUBool


@fieldwise_init
struct WGPUCommandBufferDescriptor(TrivialRegisterPassable):
    var next_in_chain: WGPUChainedStructPtr
    var label: WGPUStringView


@fieldwise_init
struct WGPUCommandEncoderDescriptor(TrivialRegisterPassable):
    var next_in_chain: WGPUChainedStructPtr
    var label: WGPUStringView


@fieldwise_init
struct WGPUCompilationMessage:
    var next_in_chain: WGPUChainedStructPtr
    var message: WGPUStringView
    var type: UInt32
    var line_num: UInt64
    var line_pos: UInt64
    var offset: UInt64
    var length: UInt64


@fieldwise_init
struct WGPUCompilationInfo:
    var next_in_chain: WGPUChainedStructPtr
    var message_count: UInt
    var messages: UnsafePointer[WGPUCompilationMessage, MutExternalOrigin]


@fieldwise_init
struct WGPUConstantEntry(TrivialRegisterPassable):
    var next_in_chain: WGPUChainedStructPtr
    var key: WGPUStringView
    var value: Float64


@fieldwise_init
struct WGPUComputePassDescriptor(TrivialRegisterPassable):
    var next_in_chain: WGPUChainedStructPtr
    var label: WGPUStringView
    var timestamp_writes: UnsafePointer[NoneType, MutExternalOrigin]  # optional


@fieldwise_init
struct WGPUComputeState(TrivialRegisterPassable):
    var next_in_chain: WGPUChainedStructPtr
    var module: WGPUShaderModuleHandle
    var entry_point: WGPUStringView
    var constant_count: UInt
    var constants: UnsafePointer[WGPUConstantEntry, MutExternalOrigin]


@fieldwise_init
struct WGPUComputePipelineDescriptor(TrivialRegisterPassable):
    var next_in_chain: WGPUChainedStructPtr
    var label: WGPUStringView
    var layout: WGPUPipelineLayoutHandle   # nullable
    var compute: WGPUComputeState


@fieldwise_init
struct WGPUQueueDescriptor(TrivialRegisterPassable):
    var next_in_chain: WGPUChainedStructPtr
    var label: WGPUStringView


@fieldwise_init
struct WGPUDeviceDescriptor:
    var next_in_chain: WGPUChainedStructPtr
    var label: WGPUStringView
    var required_feature_count: UInt
    var required_features: UnsafePointer[UInt32, MutExternalOrigin]
    var required_limits: UnsafePointer[WGPULimits, MutExternalOrigin]  # nullable
    var default_queue: WGPUQueueDescriptor
    var device_lost_callback_info: WGPUDeviceLostCallbackInfo
    var uncaptured_error_callback_info: WGPUUncapturedErrorCallbackInfo


@fieldwise_init
struct WGPUInstanceDescriptor:
    var next_in_chain: WGPUChainedStructPtr
    var required_feature_count: UInt
    var required_features: UnsafePointer[UInt32, MutExternalOrigin]
    var required_limits: UnsafePointer[NoneType, MutExternalOrigin]  # nullable WGPUInstanceLimits*


@fieldwise_init
struct WGPUMultisampleState(TrivialRegisterPassable):
    var next_in_chain: WGPUChainedStructPtr
    var count: UInt32
    var mask: UInt32
    var alpha_to_coverage_enabled: UInt32   # WGPUBool


@fieldwise_init
struct WGPUPassTimestampWrites(TrivialRegisterPassable):
    var next_in_chain: WGPUChainedStructPtr
    var query_set: WGPUQuerySetHandle
    var beginning_of_pass_write_index: UInt32
    var end_of_pass_write_index: UInt32


@fieldwise_init
struct WGPUPipelineLayoutDescriptor:
    var next_in_chain: WGPUChainedStructPtr
    var label: WGPUStringView
    var bind_group_layout_count: UInt
    var bind_group_layouts: UnsafePointer[WGPUBindGroupLayoutHandle, MutExternalOrigin]
    var immediate_size: UInt32


@fieldwise_init
struct WGPUPrimitiveState(TrivialRegisterPassable):
    var next_in_chain: WGPUChainedStructPtr
    var topology: UInt32
    var strip_index_format: UInt32
    var front_face: UInt32
    var cull_mode: UInt32
    var unclipped_depth: UInt32   # WGPUBool


@fieldwise_init
struct WGPUQuerySetDescriptor:
    var next_in_chain: WGPUChainedStructPtr
    var label: WGPUStringView
    var type: UInt32
    var count: UInt32


@fieldwise_init
struct WGPURequestAdapterOptions:
    var next_in_chain: WGPUChainedStructPtr
    var feature_level: UInt32
    var power_preference: UInt32
    var force_fallback_adapter: UInt32   # WGPUBool
    var backend_type: UInt32
    var compatible_surface: WGPUSurfaceHandle   # nullable


@fieldwise_init
struct WGPURenderPassColorAttachment:
    var next_in_chain: WGPUChainedStructPtr
    var view: WGPUTextureViewHandle   # nullable
    var depth_slice: UInt32
    var resolve_target: WGPUTextureViewHandle   # nullable
    var load_op: UInt32
    var store_op: UInt32
    var clear_value: WGPUColor


@fieldwise_init
struct WGPURenderPassDepthStencilAttachment:
    var next_in_chain: WGPUChainedStructPtr
    var view: WGPUTextureViewHandle
    var depth_load_op: UInt32
    var depth_store_op: UInt32
    var depth_clear_value: Float32
    var depth_read_only: UInt32   # WGPUBool
    var stencil_load_op: UInt32
    var stencil_store_op: UInt32
    var stencil_clear_value: UInt32
    var stencil_read_only: UInt32   # WGPUBool


@fieldwise_init
struct WGPURenderPassDescriptor:
    var next_in_chain: WGPUChainedStructPtr
    var label: WGPUStringView
    var color_attachment_count: UInt
    var color_attachments: UnsafePointer[WGPURenderPassColorAttachment, MutExternalOrigin]
    var depth_stencil_attachment: UnsafePointer[WGPURenderPassDepthStencilAttachment, MutExternalOrigin]  # nullable
    var occlusion_query_set: WGPUQuerySetHandle   # nullable
    var timestamp_writes: UnsafePointer[WGPUPassTimestampWrites, MutExternalOrigin]  # nullable


@fieldwise_init
struct WGPURenderBundleDescriptor:
    var next_in_chain: WGPUChainedStructPtr
    var label: WGPUStringView


@fieldwise_init
struct WGPURenderBundleEncoderDescriptor:
    var next_in_chain: WGPUChainedStructPtr
    var label: WGPUStringView
    var color_format_count: UInt
    var color_formats: UnsafePointer[UInt32, MutExternalOrigin]
    var depth_stencil_format: UInt32
    var sample_count: UInt32
    var depth_read_only: UInt32   # WGPUBool
    var stencil_read_only: UInt32   # WGPUBool


@fieldwise_init
struct WGPUSamplerDescriptor:
    var next_in_chain: WGPUChainedStructPtr
    var label: WGPUStringView
    var address_mode_u: UInt32
    var address_mode_v: UInt32
    var address_mode_w: UInt32
    var mag_filter: UInt32
    var min_filter: UInt32
    var mipmap_filter: UInt32
    var lod_min_clamp: Float32
    var lod_max_clamp: Float32
    var compare: UInt32
    var max_anisotropy: UInt16


@fieldwise_init
struct WGPUShaderModuleDescriptor:
    var next_in_chain: WGPUChainedStructPtr
    var label: WGPUStringView


@fieldwise_init
struct WGPUShaderSourceWGSL:
    var chain: WGPUChainedStruct
    var code: WGPUStringView


@fieldwise_init
struct WGPUShaderSourceSPIRV:
    var chain: WGPUChainedStruct
    var code_size: UInt32
    var code: UnsafePointer[UInt32, MutExternalOrigin]


@fieldwise_init
struct WGPUStencilFaceState(TrivialRegisterPassable):
    var compare: UInt32
    var fail_op: UInt32
    var depth_fail_op: UInt32
    var pass_op: UInt32


@fieldwise_init
struct WGPUDepthStencilState:
    var next_in_chain: WGPUChainedStructPtr
    var format: UInt32
    var depth_write_enabled: UInt32   # WGPUOptionalBool
    var depth_compare: UInt32
    var stencil_front: WGPUStencilFaceState
    var stencil_back: WGPUStencilFaceState
    var stencil_read_mask: UInt32
    var stencil_write_mask: UInt32
    var depth_bias: Int32
    var depth_bias_slope_scale: Float32
    var depth_bias_clamp: Float32


@fieldwise_init
struct WGPUSurfaceDescriptor:
    var next_in_chain: WGPUChainedStructPtr
    var label: WGPUStringView


@fieldwise_init
struct WGPUSurfaceCapabilities:
    var next_in_chain: WGPUChainedStructPtr
    var usages: UInt64   # WGPUTextureUsage
    var format_count: UInt
    var formats: UnsafePointer[UInt32, MutExternalOrigin]
    var present_mode_count: UInt
    var present_modes: UnsafePointer[UInt32, MutExternalOrigin]
    var alpha_mode_count: UInt
    var alpha_modes: UnsafePointer[UInt32, MutExternalOrigin]


@fieldwise_init
struct WGPUSurfaceConfiguration:
    var next_in_chain: WGPUChainedStructPtr
    var device: WGPUDeviceHandle
    var format: UInt32
    var usage: UInt64   # WGPUTextureUsage
    var width: UInt32
    var height: UInt32
    var view_format_count: UInt
    var view_formats: UnsafePointer[UInt32, MutExternalOrigin]
    var alpha_mode: UInt32
    var present_mode: UInt32


@fieldwise_init
struct WGPUSurfaceTexture:
    var next_in_chain: WGPUChainedStructPtr
    var texture: WGPUTextureHandle
    var status: UInt32


@fieldwise_init
struct WGPUTexelCopyBufferLayout(TrivialRegisterPassable):
    var offset: UInt64
    var bytes_per_row: UInt32
    var rows_per_image: UInt32


@fieldwise_init
struct WGPUTexelCopyBufferInfo:
    var layout: WGPUTexelCopyBufferLayout
    var buffer: WGPUBufferHandle


@fieldwise_init
struct WGPUTexelCopyTextureInfo:
    var texture: WGPUTextureHandle
    var mip_level: UInt32
    var origin: WGPUOrigin3D
    var aspect: UInt32


@fieldwise_init
struct WGPUTextureDescriptor:
    var next_in_chain: WGPUChainedStructPtr
    var label: WGPUStringView
    var usage: UInt64   # WGPUTextureUsage
    var dimension: UInt32
    var size: WGPUExtent3D
    var format: UInt32
    var mip_level_count: UInt32
    var sample_count: UInt32
    var view_format_count: UInt
    var view_formats: UnsafePointer[UInt32, MutExternalOrigin]


@fieldwise_init
struct WGPUTextureViewDescriptor:
    var next_in_chain: WGPUChainedStructPtr
    var label: WGPUStringView
    var format: UInt32
    var dimension: UInt32
    var base_mip_level: UInt32
    var mip_level_count: UInt32
    var base_array_layer: UInt32
    var array_layer_count: UInt32
    var aspect: UInt32
    var usage: UInt64   # WGPUTextureUsage


@fieldwise_init
struct WGPUVertexAttribute:
    var next_in_chain: WGPUChainedStructPtr
    var format: UInt32
    var offset: UInt64
    var shader_location: UInt32


@fieldwise_init
struct WGPUVertexBufferLayout:
    var next_in_chain: WGPUChainedStructPtr
    var step_mode: UInt32
    var array_stride: UInt64
    var attribute_count: UInt
    var attributes: UnsafePointer[WGPUVertexAttribute, MutExternalOrigin]


@fieldwise_init
struct WGPUColorTargetState:
    var next_in_chain: WGPUChainedStructPtr
    var format: UInt32
    var blend: UnsafePointer[WGPUBlendState, MutExternalOrigin]   # nullable
    var write_mask: UInt64   # WGPUColorWriteMask


@fieldwise_init
struct WGPUVertexState(TrivialRegisterPassable):
    var next_in_chain: WGPUChainedStructPtr
    var module: WGPUShaderModuleHandle
    var entry_point: WGPUStringView
    var constant_count: UInt
    var constants: UnsafePointer[WGPUConstantEntry, MutExternalOrigin]
    var buffer_count: UInt
    var buffers: UnsafePointer[WGPUVertexBufferLayout, MutExternalOrigin]


@fieldwise_init
struct WGPUFragmentState(TrivialRegisterPassable):
    var next_in_chain: WGPUChainedStructPtr
    var module: WGPUShaderModuleHandle
    var entry_point: WGPUStringView
    var constant_count: UInt
    var constants: UnsafePointer[WGPUConstantEntry, MutExternalOrigin]
    var target_count: UInt
    var targets: UnsafePointer[WGPUColorTargetState, MutExternalOrigin]


@fieldwise_init
struct WGPURenderPipelineDescriptor(TrivialRegisterPassable):
    var next_in_chain: WGPUChainedStructPtr
    var label: WGPUStringView
    var layout: WGPUPipelineLayoutHandle   # nullable
    var vertex: WGPUVertexState
    var primitive: WGPUPrimitiveState
    var depth_stencil: UnsafePointer[WGPUDepthStencilState, MutExternalOrigin]  # nullable
    var multisample: WGPUMultisampleState
    var fragment: UnsafePointer[WGPUFragmentState, MutExternalOrigin]   # nullable


@fieldwise_init
struct WGPUSupportedFeatures:
    var feature_count: UInt
    var features: UnsafePointer[UInt32, MutExternalOrigin]


# ---------------------------------------------------------------------------
# Surface source structs for platform window integration (Linux/Wayland)
# ---------------------------------------------------------------------------

@fieldwise_init
struct WGPUSurfaceSourceWaylandSurface(TrivialRegisterPassable):
    var chain: WGPUChainedStruct
    var display: VoidPtr
    var surface: VoidPtr


@fieldwise_init
struct WGPUSurfaceSourceXlibWindow(TrivialRegisterPassable):
    var chain: WGPUChainedStruct
    var display: VoidPtr
    var window: UInt64


@fieldwise_init
struct WGPUSurfaceSourceXCBWindow(TrivialRegisterPassable):
    var chain: WGPUChainedStruct
    var connection: VoidPtr
    var window: UInt32


# ---------------------------------------------------------------------------
# Helper — default (query-ready) WGPULimits
# ---------------------------------------------------------------------------

def wgpu_limits_default() -> WGPULimits:
    """Return a WGPULimits struct with all fields set to UNDEFINED sentinel values.
    Suitable as an output buffer for wgpuDeviceGetLimits / wgpuAdapterGetLimits."""
    from wgpu._ffi.types import WGPU_LIMIT_U32_UNDEFINED, WGPU_LIMIT_U64_UNDEFINED
    var u32_max: UInt32 = WGPU_LIMIT_U32_UNDEFINED
    var u64_max: UInt64 = WGPU_LIMIT_U64_UNDEFINED
    return WGPULimits(
        OpaquePtr(),    # next_in_chain
        u32_max,        # max_texture_dimension_1d
        u32_max,        # max_texture_dimension_2d
        u32_max,        # max_texture_dimension_3d
        u32_max,        # max_texture_array_layers
        u32_max,        # max_bind_groups
        u32_max,        # max_bind_groups_plus_vertex_buffers
        u32_max,        # max_bindings_per_bind_group
        u32_max,        # max_dynamic_uniform_buffers_per_pipeline_layout
        u32_max,        # max_dynamic_storage_buffers_per_pipeline_layout
        u32_max,        # max_sampled_textures_per_shader_stage
        u32_max,        # max_samplers_per_shader_stage
        u32_max,        # max_storage_buffers_per_shader_stage
        u32_max,        # max_storage_textures_per_shader_stage
        u32_max,        # max_uniform_buffers_per_shader_stage
        u64_max,        # max_uniform_buffer_binding_size
        u64_max,        # max_storage_buffer_binding_size
        u32_max,        # min_uniform_buffer_offset_alignment
        u32_max,        # min_storage_buffer_offset_alignment
        u32_max,        # max_vertex_buffers
        u64_max,        # max_buffer_size
        u32_max,        # max_vertex_attributes
        u32_max,        # max_vertex_buffer_array_stride
        u32_max,        # max_inter_stage_shader_variables
        u32_max,        # max_color_attachments
        u32_max,        # max_color_attachment_bytes_per_sample
        u32_max,        # max_compute_workgroup_storage_size
        u32_max,        # max_compute_invocations_per_workgroup
        u32_max,        # max_compute_workgroup_size_x
        u32_max,        # max_compute_workgroup_size_y
        u32_max,        # max_compute_workgroup_size_z
        u32_max,        # max_compute_workgroups_per_dimension
        u32_max,        # max_immediate_size
    )
