"""
wgpu.device — High-level Device + Queue RAII wrapper.
"""

from std.memory import ArcPointer
from wgpu._ffi.lib import WGPULib
from wgpu._ffi.nulls import null_opaque, null_ptr, null_any_ptr
from wgpu._ffi.types import (
    WGPU_TRUE,
    WGPUDeviceHandle, WGPUQueueHandle, WGPUInstanceHandle,
    WGPUBufferHandle, WGPUTextureHandle, WGPUSamplerHandle,
    WGPUShaderModuleHandle, WGPUBindGroupHandle, WGPUBindGroupLayoutHandle,
    WGPUPipelineLayoutHandle, WGPUComputePipelineHandle, WGPURenderPipelineHandle,
    WGPUCommandEncoderHandle, WGPUCommandBufferHandle, WGPUQuerySetHandle,
    WGPURenderBundleEncoderHandle,
    WGPUBufferUsage, WGPUTextureUsage, WGPUShaderStage,
)
from wgpu._ffi.handles import DeviceHandle, QueueHandle, InstanceHandle as InstanceHandleNewtype
from wgpu._ffi.structs import (
    WGPUStringView, WGPUExtent3D, WGPULimits, WGPUSupportedFeatures,
    wgpu_limits_default,
    WGPUBufferDescriptor,
    WGPUTextureDescriptor,
    WGPUTextureViewDescriptor,
    WGPUSamplerDescriptor,
    WGPUShaderModuleDescriptor, WGPUShaderSourceWGSL, WGPUShaderSourceSPIRV,
    WGPUShaderModuleDescriptorSpirV,
    WGPUBindGroupDescriptor, WGPUBindGroupLayoutDescriptor,
    WGPUBindGroupLayoutEntry, WGPUBindGroupEntry,
    WGPUPipelineLayoutDescriptor,
    WGPUComputePipelineDescriptor, WGPURenderPipelineDescriptor,
    WGPUComputeState, WGPUConstantEntry,
    WGPUVertexState, WGPUFragmentState,
    WGPUPrimitiveState, WGPUMultisampleState,
    WGPUColorTargetState, WGPUBlendState,
    WGPUVertexBufferLayout, WGPUDepthStencilState,
    WGPUCommandEncoderDescriptor,
    WGPUQuerySetDescriptor,
    WGPUExtent3D, WGPUTexelCopyBufferLayout, WGPUTexelCopyTextureInfo,
    WGPUOrigin3D,
    WGPUChainedStruct,
    WGPUPopErrorScopeCallbackInfo,
    str_to_sv,
)
from wgpu._ffi.types import WGPUCallbackMode, WGPUErrorFilter, WGPUErrorType
from wgpu._ffi.alloc_guard import AllocGuard
from wgpu._backend.wgpu_native.loader import (
    _PopErrorResult,
)
from wgpu._ffi.types import WGPUSType
from wgpu.buffer import Buffer, _sizeof
from wgpu.instance_owner import InstanceOwner
from wgpu.texture import Texture, TextureView
from wgpu.sampler import Sampler
from wgpu.shader import ShaderModule
from wgpu.bind_group import BindGroup, BindGroupLayout
from wgpu.pipeline_layout import PipelineLayout
from wgpu.pipeline import ComputePipeline, RenderPipeline
from wgpu.command import CommandEncoder, CommandBuffer
from wgpu.query_set import QuerySet
from wgpu.render_bundle import RenderBundle, RenderBundleEncoder
from wgpu._ffi.structs import WGPURenderBundleEncoderDescriptor


struct Device(Movable, Boolable):
    """
    Owns a WGPUDevice + WGPUQueue.
    Holds an ArcPointer clone of WGPULib for shared library access.
    """

    var _owner: ArcPointer[InstanceOwner]
    var _lib: ArcPointer[WGPULib]
    var _instance: WGPUInstanceHandle
    var _handle: WGPUDeviceHandle
    var _queue: WGPUQueueHandle

    def __init__(
        out self,
        owner: ArcPointer[InstanceOwner],
        lib: ArcPointer[WGPULib],
        instance: WGPUInstanceHandle,
        handle: WGPUDeviceHandle,
        queue: WGPUQueueHandle,
    ):
        self._owner = owner
        self._lib = lib
        self._instance = instance
        self._handle = handle
        self._queue = queue

    def __init__(out self, *, deinit move: Self):
        self._owner = move._owner^
        self._lib = move._lib^
        self._instance = move._instance
        self._handle = move._handle
        self._queue = move._queue

    def __deinit__(deinit self):
        self._lib[].queue_release(self._queue)
        self._lib[].device_release(self._handle)

    def __bool__(self) -> Bool:
        return Int(self._handle) != 0

    # ------------------------------------------------------------------
    # Limits / features
    # ------------------------------------------------------------------

    def get_limits(self) -> WGPULimits:
        var limits_p = alloc[WGPULimits](1)
        limits_p[] = wgpu_limits_default()
        _ = self._lib[].device_get_limits(self._handle, limits_p)
        var result = limits_p[]
        limits_p.unsafe_free()
        return result

    def has_feature(self, feature: UInt32) -> Bool:
        return self._lib[].device_has_feature(self._handle, feature) == WGPU_TRUE

    def poll(self, wait: Bool = True) -> Bool:
        return self._lib[].device_poll(self._handle, wait) == WGPU_TRUE

    # ------------------------------------------------------------------
    # Resource creation helpers
    # ------------------------------------------------------------------

    def create_buffer(
        self,
        size: UInt64,
        usage: WGPUBufferUsage,
        mapped_at_creation: Bool = False,
        label: String = "",
    ) raises -> Buffer:
        var label_sv = str_to_sv(label) if label.byte_length() > 0 else WGPUStringView.null_view()
        var mapped: UInt32 = UInt32(1) if mapped_at_creation else UInt32(0)
        var desc_p = alloc[WGPUBufferDescriptor](1)
        desc_p[] = WGPUBufferDescriptor(
            null_opaque(),
            label_sv,
            usage.value,
            size,
            mapped,
        )
        var result = self._lib[].device_create_buffer(self._handle, desc_p)
        desc_p.unsafe_free()
        return Buffer(self._lib, self._instance, self._handle, result, size, usage)

    def create_texture(
        self,
        width: UInt32,
        height: UInt32,
        depth_or_layers: UInt32,
        format: UInt32,
        usage: WGPUTextureUsage,
        dimension: UInt32 = 2,  # WGPUTextureDimension_2D
        mip_level_count: UInt32 = 1,
        sample_count: UInt32 = 1,
        label: String = "",
    ) raises -> Texture:
        var label_sv = str_to_sv(label) if label.byte_length() > 0 else WGPUStringView.null_view()
        var size = WGPUExtent3D(width, height, depth_or_layers)
        var desc_p = alloc[WGPUTextureDescriptor](1)
        desc_p[] = WGPUTextureDescriptor(
            null_opaque(),
            label_sv,
            usage.value,
            dimension,
            size,
            format,
            mip_level_count,
            sample_count,
            UInt(0),
            null_ptr[UInt32](),
        )
        var result = self._lib[].device_create_texture(self._handle, desc_p)
        desc_p.unsafe_free()
        return Texture(self._lib, result)

    def create_texture_view(self, texture: WGPUTextureHandle) -> TextureView:
        """Create a TextureView from a raw texture handle (e.g. surface frame)."""
        var result = self._lib[].texture_create_view(
            texture,
            null_ptr[WGPUTextureViewDescriptor](),
        )
        return TextureView(self._lib, result)

    def create_texture_view(self, texture: Texture) -> TextureView:
        """Wrapper-first overload — accepts RAII Texture directly."""
        return self.create_texture_view(texture.handle().raw)

    def create_sampler(
        self,
        address_mode_u: UInt32 = 1,  # ClampToEdge
        address_mode_v: UInt32 = 1,
        address_mode_w: UInt32 = 1,
        mag_filter: UInt32 = 1,      # Linear
        min_filter: UInt32 = 1,
        mipmap_filter: UInt32 = 0,   # Nearest
        lod_min_clamp: Float32 = 0.0,
        lod_max_clamp: Float32 = 32.0,
        compare: UInt32 = 0,         # Undefined
        max_anisotropy: UInt16 = 1,
        label: String = "",
    ) raises -> Sampler:
        var label_sv = str_to_sv(label) if label.byte_length() > 0 else WGPUStringView.null_view()
        var desc_p = alloc[WGPUSamplerDescriptor](1)
        desc_p[] = WGPUSamplerDescriptor(
            null_opaque(),
            label_sv,
            address_mode_u,
            address_mode_v,
            address_mode_w,
            mag_filter,
            min_filter,
            mipmap_filter,
            lod_min_clamp,
            lod_max_clamp,
            compare,
            max_anisotropy,
        )
        var result = self._lib[].device_create_sampler(self._handle, desc_p)
        desc_p.unsafe_free()
        return Sampler(self._lib, result)

    def create_shader_module_wgsl(
        self,
        code: String,
        label: String = "",
    ) raises -> ShaderModule:
        var label_sv = str_to_sv(label) if label.byte_length() > 0 else WGPUStringView.null_view()
        var code_sv  = str_to_sv(code)
        var chain_val = WGPUChainedStruct(null_opaque(), WGPUSType.ShaderSourceWGSL)
        var source_p = alloc[WGPUShaderSourceWGSL](1)
        source_p[] = WGPUShaderSourceWGSL(chain_val, code_sv)
        var desc_p = alloc[WGPUShaderModuleDescriptor](1)
        desc_p[] = WGPUShaderModuleDescriptor(
            source_p.unsafe_bitcast[NoneType](),
            label_sv,
        )
        var result = self._lib[].device_create_shader_module(self._handle, desc_p)
        source_p.unsafe_free()
        desc_p.unsafe_free()
        return ShaderModule(self._lib, result, self._instance)

    def create_shader_module_spirv(
        self,
        code: List[UInt32],
        label: String = "",
    ) raises -> ShaderModule:
        var label_sv = str_to_sv(label) if label.byte_length() > 0 else WGPUStringView.null_view()
        var code_ptr = rebind[Pointer[UInt32, MutUntrackedOrigin]](code.unsafe_ptr())
        var chain_val = WGPUChainedStruct(null_opaque(), WGPUSType.ShaderSourceSPIRV)
        var source_p = alloc[WGPUShaderSourceSPIRV](1)
        source_p[] = WGPUShaderSourceSPIRV(
            chain_val,
            UInt32(len(code)),
            code_ptr,
        )
        var desc_p = alloc[WGPUShaderModuleDescriptor](1)
        desc_p[] = WGPUShaderModuleDescriptor(
            source_p.unsafe_bitcast[NoneType](),
            label_sv,
        )
        var result = self._lib[].device_create_shader_module(self._handle, desc_p)
        source_p.unsafe_free()
        desc_p.unsafe_free()
        return ShaderModule(self._lib, result, self._instance)

    def start_graphics_debugger_capture(self) -> Bool:
        """Begin a RenderDoc-style capture. False when no debugger is attached."""
        return self._lib[].device_start_graphics_debugger_capture(self._handle) == WGPU_TRUE

    def stop_graphics_debugger_capture(self):
        """End a capture started with `start_graphics_debugger_capture()`."""
        self._lib[].device_stop_graphics_debugger_capture(self._handle)

    def native_metal_device(self) -> OpaquePointer[MutUntrackedOrigin]:
        """Underlying `MTLDevice`, or null on non-Metal backends."""
        return self._lib[].device_get_native_metal_device(self._handle)

    def native_metal_command_queue(self) -> OpaquePointer[MutUntrackedOrigin]:
        """Underlying `MTLCommandQueue`, or null on non-Metal backends."""
        return self._lib[].queue_get_native_metal_command_queue(self._queue)

    def create_bind_group_layout(
        self,
        desc: WGPUBindGroupLayoutDescriptor,
    ) raises -> BindGroupLayout:
        var desc_p = alloc[WGPUBindGroupLayoutDescriptor](1)
        desc_p[] = desc
        var result = self._lib[].device_create_bind_group_layout(self._handle, desc_p)
        desc_p.unsafe_free()
        return BindGroupLayout(self._lib, result)

    def create_bind_group_layout(
        self,
        entries: List[WGPUBindGroupLayoutEntry],
        label: String = "",
    ) raises -> BindGroupLayout:
        """High-level BindGroupLayout creation from entry structs."""
        var label_sv = str_to_sv(label) if label.byte_length() > 0 else WGPUStringView.null_view()
        var entries_ptr = null_ptr[WGPUBindGroupLayoutEntry]()
        if len(entries) > 0:
            entries_ptr = rebind[Pointer[WGPUBindGroupLayoutEntry, MutUntrackedOrigin]](entries.unsafe_ptr())
        var desc = WGPUBindGroupLayoutDescriptor(
            null_opaque(),
            label_sv,
            UInt(len(entries)),
            entries_ptr,
        )
        return self.create_bind_group_layout(desc)

    def create_bind_group(
        self,
        desc: WGPUBindGroupDescriptor,
    ) raises -> BindGroup:
        var desc_p = alloc[WGPUBindGroupDescriptor](1)
        desc_p[] = desc
        var result = self._lib[].device_create_bind_group(self._handle, desc_p)
        desc_p.unsafe_free()
        return BindGroup(self._lib, result)

    def create_bind_group(
        self,
        layout: BindGroupLayout,
        entries: List[WGPUBindGroupEntry],
        label: String = "",
    ) raises -> BindGroup:
        """High-level BindGroup creation from entry structs.
        
        This method owns the entries allocation, keeping it alive
        until after the FFI call completes. This prevents Mojo's
        last-use drop semantics from invalidating handles in the entries.
        """
        var label_sv = str_to_sv(label) if label.byte_length() > 0 else WGPUStringView.null_view()
        var entries_len = len(entries)
        
        # Allocate and copy entries into our own buffer
        var entries_ptr = alloc[WGPUBindGroupEntry](entries_len) if entries_len > 0 else null_ptr[WGPUBindGroupEntry]()
        if entries_len > 0:
            for i in range(entries_len):
                entries_ptr[unsafe_offset=i] = entries[i]
        
        # Build descriptor with our allocated entries
        var desc = WGPUBindGroupDescriptor(
            null_opaque(),
            label_sv,
            layout.handle().raw,
            UInt(entries_len),
            entries_ptr,
        )
        
        # Allocate descriptor and call FFI
        var desc_p = alloc[WGPUBindGroupDescriptor](1)
        desc_p[] = desc
        var result = self._lib[].device_create_bind_group(self._handle, desc_p)
        desc_p.unsafe_free()
        
        # Free the entries we allocated
        if entries_len > 0:
            entries_ptr.unsafe_free()
        
        return BindGroup(self._lib, result)

    def create_pipeline_layout(
        self,
        bind_group_layouts: List[WGPUBindGroupLayoutHandle],
        label: String = "",
    ) raises -> PipelineLayout:
        var label_sv = str_to_sv(label) if label.byte_length() > 0 else WGPUStringView.null_view()
        var layouts_ptr = rebind[Pointer[WGPUBindGroupLayoutHandle, MutUntrackedOrigin]](bind_group_layouts.unsafe_ptr())
        var desc_p = alloc[WGPUPipelineLayoutDescriptor](1)
        desc_p[] = WGPUPipelineLayoutDescriptor(
            null_opaque(),
            label_sv,
            UInt(len(bind_group_layouts)),
            layouts_ptr,
            0,  # immediateDataRangeByteSize
        )
        var result = self._lib[].device_create_pipeline_layout(self._handle, desc_p)
        desc_p.unsafe_free()
        return PipelineLayout(self._lib, result)

    def create_pipeline_layout(
        self,
        bgl: BindGroupLayout,
        label: String = "",
    ) raises -> PipelineLayout:
        """Single-BGL convenience overload.

        Borrowing `bgl` keeps the BindGroupLayout alive for the FFI call,
        eliminating the need for a manual `_ = bgl^` pin.
        """
        var handles: List[WGPUBindGroupLayoutHandle] = [bgl.handle().raw]
        return self.create_pipeline_layout(handles, label)

    def create_compute_pipeline(
        self,
        desc: WGPUComputePipelineDescriptor,
    ) raises -> ComputePipeline:
        var desc_p = alloc[WGPUComputePipelineDescriptor](1)
        desc_p[] = desc
        var result = self._lib[].device_create_compute_pipeline(self._handle, desc_p)
        desc_p.unsafe_free()
        return ComputePipeline(self._lib, result)

    def create_compute_pipeline(
        self,
        shader: ShaderModule,
        entry_point: String,
        layout: PipelineLayout,
        label: String = "",
    ) raises -> ComputePipeline:
        """High-level compute pipeline creation.

        Borrowing `shader` and `layout` keeps them alive for the FFI call,
        eliminating the need for manual `_ = shader^` / `_ = layout^` pins.
        """
        var label_sv = str_to_sv(label) if label.byte_length() > 0 else WGPUStringView.null_view()
        var entry_sv = str_to_sv(entry_point)
        var cs = WGPUComputeState(
            null_opaque(),
            shader.handle().raw,
            entry_sv,
            UInt(0),
            null_ptr[WGPUConstantEntry](),
        )
        var desc = WGPUComputePipelineDescriptor(
            null_opaque(), label_sv, layout.handle().raw, cs,
        )
        return self.create_compute_pipeline(desc)

    def create_render_pipeline(
        self,
        var desc: WGPURenderPipelineDescriptor,
    ) raises -> RenderPipeline:
        var desc_p = alloc[WGPURenderPipelineDescriptor](1)
        desc_p[] = desc^
        var result = self._lib[].device_create_render_pipeline(self._handle, desc_p)
        desc_p.unsafe_free()
        return RenderPipeline(self._lib, result)

    def create_render_pipeline(
        self,
        shader: ShaderModule,
        vs_entry_point: String,
        fs_entry_point: String,
        color_format: UInt32,
        layout: PipelineLayout,
        primitive_topology: UInt32 = 4,  # TriangleList (4); LineStrip=3, TriangleStrip=5
        label: String = "",
    ) raises -> RenderPipeline:
        """High-level render pipeline creation for the common case.

        Builds vertex/fragment state, one color target, default primitive
        and multisample settings. Borrowing `shader` and `layout` keeps
        them alive for the FFI call.

        Args:
            shader: Compiled shader module with both VS and FS entry points.
            vs_entry_point: Vertex shader entry point name.
            fs_entry_point: Fragment shader entry point name.
            color_format: WGPUTextureFormat for the single color target.
            layout: Pipeline layout.
            primitive_topology: Primitive topology (default 4 = TriangleList).
            label: Optional label.
        """
        var label_sv = str_to_sv(label) if label.byte_length() > 0 else WGPUStringView.null_view()
        var vs_sv = str_to_sv(vs_entry_point)
        var fs_sv = str_to_sv(fs_entry_point)

        var vertex_state = WGPUVertexState(
            null_opaque(), shader.handle().raw, vs_sv,
            UInt(0), null_ptr[WGPUConstantEntry](),
            UInt(0), null_ptr[WGPUVertexBufferLayout](),
        )
        var target_p = alloc[WGPUColorTargetState](1)
        target_p[unsafe_offset=0] = WGPUColorTargetState(
            null_opaque(), color_format,
            null_ptr[WGPUBlendState](),
            UInt64(0xF),  # ColorWriteMask.All
        )
        var fragment_p = alloc[WGPUFragmentState](1)
        fragment_p[unsafe_offset=0] = WGPUFragmentState(
            null_opaque(), shader.handle().raw, fs_sv,
            UInt(0), null_ptr[WGPUConstantEntry](),
            UInt(1), target_p,
        )
        var primitive = WGPUPrimitiveState(
            null_opaque(), primitive_topology, UInt32(0), UInt32(1), UInt32(0), UInt32(0),
        )
        var multisample = WGPUMultisampleState(
            null_opaque(), UInt32(1), UInt32(0xFFFFFFFF), UInt32(0),
        )
        var desc = WGPURenderPipelineDescriptor(
            null_opaque(), label_sv, layout.handle().raw,
            vertex_state, primitive,
            null_ptr[WGPUDepthStencilState](),
            multisample, fragment_p,
        )
        var result = self.create_render_pipeline(desc^)
        target_p.unsafe_free()
        fragment_p.unsafe_free()
        return result^

    def create_command_encoder(self, label: String = "") raises -> CommandEncoder:
        var label_sv = str_to_sv(label) if label.byte_length() > 0 else WGPUStringView.null_view()
        var desc_p = alloc[WGPUCommandEncoderDescriptor](1)
        desc_p[] = WGPUCommandEncoderDescriptor(null_opaque(), label_sv)
        var result = self._lib[].device_create_command_encoder(self._handle, desc_p)
        desc_p.unsafe_free()
        return CommandEncoder(self._lib, result)

    def create_query_set(
        self,
        query_type: UInt32,
        count: UInt32,
        label: String = "",
    ) raises -> QuerySet:
        var label_sv = str_to_sv(label) if label.byte_length() > 0 else WGPUStringView.null_view()
        var desc_p = alloc[WGPUQuerySetDescriptor](1)
        desc_p[] = WGPUQuerySetDescriptor(
            null_opaque(), label_sv, query_type, count
        )
        var result = self._lib[].device_create_query_set(self._handle, desc_p)
        desc_p.unsafe_free()
        return QuerySet(self._lib, result)

    def create_render_bundle_encoder(
        self,
        color_formats: List[UInt32],
        label: String = "",
        depth_stencil_format: UInt32 = 0,
        sample_count: UInt32 = 1,
        depth_read_only: Bool = False,
        stencil_read_only: Bool = False,
    ) raises -> RenderBundleEncoder:
        """Create a RenderBundleEncoder that records commands for later replay.

        color_formats: list of WGPUTextureFormat values for each color attachment.
        depth_stencil_format: WGPUTextureFormat for depth/stencil (0 = none).
        """
        var label_sv = str_to_sv(label) if label.byte_length() > 0 else WGPUStringView.null_view()
        var fmt_ptr = rebind[Pointer[UInt32, MutUntrackedOrigin]](color_formats.unsafe_ptr())
        var desc_p = alloc[WGPURenderBundleEncoderDescriptor](1)
        desc_p[] = WGPURenderBundleEncoderDescriptor(
            null_opaque(),
            label_sv,
            UInt(len(color_formats)),
            fmt_ptr,
            depth_stencil_format,
            sample_count,
            UInt32(1) if depth_read_only else UInt32(0),
            UInt32(1) if stencil_read_only else UInt32(0),
        )
        var result = self._lib[].device_create_render_bundle_encoder(self._handle, desc_p)
        desc_p.unsafe_free()
        return RenderBundleEncoder(self._lib, result)

    # ------------------------------------------------------------------
    # Queue write helpers
    # ------------------------------------------------------------------

    def queue_submit(self, commands: List[WGPUCommandBufferHandle]):
        var arr = rebind[Pointer[WGPUCommandBufferHandle, MutUntrackedOrigin]](commands.unsafe_ptr())
        self._lib[].queue_submit(self._queue, UInt(len(commands)), arr)

    def queue_submit(self, cmd: CommandBuffer):
        """Submit a single CommandBuffer (RAII wrapper).

        Borrowing `cmd` keeps it alive for the FFI call. After submit
        returns, the CommandBuffer destructor calls wgpuCommandBufferRelease.
        """
        var handle = cmd.raw()
        var handle_p = alloc[WGPUCommandBufferHandle](1)
        handle_p[] = handle
        var arr = rebind[Pointer[WGPUCommandBufferHandle, MutUntrackedOrigin]](handle_p)
        self._lib[].queue_submit(self._queue, UInt(1), arr)
        handle_p.unsafe_free()

    def queue_timestamp_period(self) -> Float32:
        """Return nanoseconds per GPU timestamp tick (requires TimestampQuery feature)."""
        return self._lib[].queue_get_timestamp_period(self._queue)

    def queue_write_data[
        T: Copyable & Movable
    ](
        self,
        buffer: Buffer,
        offset: UInt64,
        data: List[T],
    ):
        """Write List data to a buffer.

        Borrowing both `buffer` and `data` keeps them alive for the FFI call,
        eliminating manual `_ = data^` / `_ = buffer^` pins.
        """
        var byte_count = UInt(len(data)) * UInt(_sizeof[T]())
        var ptr = rebind[Pointer[T, MutUntrackedOrigin]](data.unsafe_ptr())
        self._lib[].queue_write_buffer(
            self._queue,
            buffer.handle().raw,
            offset,
            ptr.unsafe_bitcast[NoneType](),
            byte_count,
        )

    def queue_write_texture(
        self,
        texture: Texture,
        mip_level: UInt32,
        origin: WGPUOrigin3D,
        aspect: UInt32,
        data: List[UInt8],
        bytes_per_row: UInt32,
        rows_per_image: UInt32,
        width: UInt32,
        height: UInt32,
        depth_or_array_layers: UInt32,
    ):
        var layout_p = alloc[WGPUTexelCopyBufferLayout](1)
        layout_p[0] = WGPUTexelCopyBufferLayout(
            UInt64(0),
            bytes_per_row,
            rows_per_image,
        )

        var dst_p = alloc[WGPUTexelCopyTextureInfo](1)
        dst_p[0] = WGPUTexelCopyTextureInfo(
            texture.handle().raw,
            mip_level,
            origin,
            aspect,
        )

        var size_p = alloc[WGPUExtent3D](1)
        size_p[0] = WGPUExtent3D(width, height, depth_or_array_layers)

        var data_ptr = OpaquePointer[MutUntrackedOrigin](unsafe_from_address=Int(data.unsafe_ptr()))
        var dst_ptr = OpaquePointer[MutUntrackedOrigin](unsafe_from_address=Int(dst_p))
        var layout_ptr = OpaquePointer[MutUntrackedOrigin](unsafe_from_address=Int(layout_p))
        var size_ptr = OpaquePointer[MutUntrackedOrigin](unsafe_from_address=Int(size_p))
        self._lib[].queue_write_texture(
            self._queue,
            dst_ptr,
            data_ptr,
            UInt(len(data)),
            layout_ptr,
            size_ptr,
        )

        layout_p.unsafe_free()
        dst_p.unsafe_free()
        size_p.unsafe_free()

    # ------------------------------------------------------------------
    # Error scope
    # ------------------------------------------------------------------

    def push_error_scope(self, filter: UInt32 = WGPUErrorFilter.Validation):
        """Push an error scope onto the device's error scope stack.

        Errors matching `filter` that occur between push and pop are captured.
        Pop with pop_error_scope() to retrieve the first captured error.
        Common filters: WGPUErrorFilter.Validation, OutOfMemory, Internal.
        """
        self._lib[].device_push_error_scope(self._handle, filter)

    def pop_error_scope(self) raises -> String:
        """Pop the top error scope and return the error message (if any).

        Returns an empty string when no error was captured since the last push.
        Raises if the pop fails (e.g. scope stack is empty or device is lost).
        """
        with AllocGuard[_PopErrorResult](1) as result:
            result[] = _PopErrorResult(UInt32(0), UInt32(0), null_opaque(), UInt(0))
            with AllocGuard[WGPUPopErrorScopeCallbackInfo](1) as cb_info_p:
                cb_info_p[] = WGPUPopErrorScopeCallbackInfo(
                    null_opaque(),
                    WGPUCallbackMode.AllowSpontaneous,
                    self._lib[]._pop_error_cb_ptr,
                    result.unsafe_bitcast[NoneType](),
                    null_opaque(),
                )
                self._lib[].device_pop_error_scope(self._handle, cb_info_p)
            self._lib[].instance_process_events(self._instance)

            var status = result[].status
            var err_type = result[].type
            if status != UInt32(1):  # WGPUPopErrorScopeStatus.Success == 1
                raise Error("pop_error_scope failed, status=" + String(status))
            if err_type == WGPUErrorType.NoError:
                return String("")
            var p = Pointer(result[].message_data).unsafe_bitcast[UInt8]()
            var n = result[].message_len
            var out = String()
            var i = UInt(0)
            while i < n and p[unsafe_offset=Int(i)] != 0:
                out += chr(Int(p[unsafe_offset=Int(i)]))
                i += 1
            return out

    # ------------------------------------------------------------------
    # Labels
    # ------------------------------------------------------------------

    # ------------------------------------------------------------------
    # Raw handle access
    # ------------------------------------------------------------------

    def lib(self) -> ArcPointer[WGPULib]:
        return self._lib

    def handle(self) -> DeviceHandle:
        return DeviceHandle(self._handle)

    def queue(self) -> QueueHandle:
        return QueueHandle(self._queue)

    def instance(self) -> InstanceHandleNewtype:
        return InstanceHandleNewtype(self._instance)
