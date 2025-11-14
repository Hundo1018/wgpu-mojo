"""
wgpu.device — High-level Device + Queue RAII wrapper.
"""

from std.memory import ArcPointer
from wgpu._ffi.lib import WGPULib
from wgpu._ffi.types import (
    OpaquePtr, WGPU_TRUE,
    WGPUDeviceHandle, WGPUQueueHandle, WGPUInstanceHandle,
    WGPUBufferHandle, WGPUTextureHandle, WGPUSamplerHandle,
    WGPUShaderModuleHandle, WGPUBindGroupHandle, WGPUBindGroupLayoutHandle,
    WGPUPipelineLayoutHandle, WGPUComputePipelineHandle, WGPURenderPipelineHandle,
    WGPUCommandEncoderHandle, WGPUCommandBufferHandle, WGPUQuerySetHandle,
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
    WGPUBindGroupDescriptor, WGPUBindGroupLayoutDescriptor,
    WGPUPipelineLayoutDescriptor,
    WGPUComputePipelineDescriptor, WGPURenderPipelineDescriptor,
    WGPUComputeState, WGPUConstantEntry,
    WGPUVertexState, WGPUFragmentState,
    WGPUPrimitiveState, WGPUMultisampleState,
    WGPUColorTargetState, WGPUBlendState,
    WGPUVertexBufferLayout, WGPUDepthStencilState,
    WGPUCommandEncoderDescriptor,
    WGPUQuerySetDescriptor,
    WGPUChainedStruct,
    str_to_sv,
)
from wgpu._ffi.types import WGPUSType
from wgpu.buffer import Buffer, _sizeof
from wgpu.texture import Texture, TextureView
from wgpu.sampler import Sampler
from wgpu.shader import ShaderModule
from wgpu.bind_group import BindGroup, BindGroupLayout
from wgpu.pipeline_layout import PipelineLayout
from wgpu.pipeline import ComputePipeline, RenderPipeline
from wgpu.command import CommandEncoder, CommandBuffer
from wgpu.query_set import QuerySet


struct Device(Movable):
    """
    Owns a WGPUDevice + WGPUQueue.
    Holds an ArcPointer clone of WGPULib for shared library access.
    """

    var _lib:      ArcPointer[WGPULib]
    var _instance: WGPUInstanceHandle
    var _handle:   WGPUDeviceHandle
    var _queue:    WGPUQueueHandle

    def __init__(
        out self,
        lib: ArcPointer[WGPULib],
        instance: WGPUInstanceHandle,
        handle: WGPUDeviceHandle,
        queue: WGPUQueueHandle,
    ):
        self._lib      = lib
        self._instance = instance
        self._handle   = handle
        self._queue    = queue

    def __init__(out self, *, deinit take: Self):
        self._lib      = take._lib^
        self._instance = take._instance
        self._handle   = take._handle
        self._queue    = take._queue

    def __del__(deinit self):
        self._lib[].queue_release(self._queue)
        self._lib[].device_release(self._handle)

    # ------------------------------------------------------------------
    # Limits / features
    # ------------------------------------------------------------------

    def get_limits(self) -> WGPULimits:
        var limits_p = alloc[WGPULimits](1)
        limits_p[] = wgpu_limits_default()
        _ = self._lib[].device_get_limits(self._handle, limits_p)
        var result = limits_p[]
        limits_p.free()
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
            OpaquePtr(),
            label_sv,
            usage.value,
            size,
            mapped,
        )
        var result = self._lib[].device_create_buffer(self._handle, desc_p)
        desc_p.free()
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
            OpaquePtr(),
            label_sv,
            usage.value,
            dimension,
            size,
            format,
            mip_level_count,
            sample_count,
            UInt(0),
            UnsafePointer[UInt32, MutExternalOrigin](),
        )
        var result = self._lib[].device_create_texture(self._handle, desc_p)
        desc_p.free()
        return Texture(self._lib, result)

    def create_texture_view(self, texture: WGPUTextureHandle) -> TextureView:
        """Create a TextureView from a raw texture handle (e.g. surface frame)."""
        var result = self._lib[].texture_create_view(
            texture,
            UnsafePointer[WGPUTextureViewDescriptor, MutExternalOrigin](),
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
            OpaquePtr(),
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
        desc_p.free()
        return Sampler(self._lib, result)

    def create_shader_module_wgsl(
        self,
        code: String,
        label: String = "",
    ) raises -> ShaderModule:
        var label_sv = str_to_sv(label) if label.byte_length() > 0 else WGPUStringView.null_view()
        var code_sv  = str_to_sv(code)
        var chain_val = WGPUChainedStruct(OpaquePtr(), WGPUSType.ShaderSourceWGSL)
        var source_p = alloc[WGPUShaderSourceWGSL](1)
        source_p[] = WGPUShaderSourceWGSL(chain_val, code_sv)
        var desc_p = alloc[WGPUShaderModuleDescriptor](1)
        desc_p[] = WGPUShaderModuleDescriptor(
            source_p.bitcast[NoneType](),
            label_sv,
        )
        var result = self._lib[].device_create_shader_module(self._handle, desc_p)
        source_p.free()
        desc_p.free()
        return ShaderModule(self._lib, result)

    def create_shader_module_spirv(
        self,
        code: List[UInt32],
        label: String = "",
    ) raises -> ShaderModule:
        var label_sv = str_to_sv(label) if label.byte_length() > 0 else WGPUStringView.null_view()
        var code_ptr = rebind[UnsafePointer[UInt32, MutExternalOrigin]](code.unsafe_ptr())
        var chain_val = WGPUChainedStruct(OpaquePtr(), WGPUSType.ShaderSourceSPIRV)
        var source_p = alloc[WGPUShaderSourceSPIRV](1)
        source_p[] = WGPUShaderSourceSPIRV(
            chain_val,
            UInt32(len(code)),
            code_ptr,
        )
        var desc_p = alloc[WGPUShaderModuleDescriptor](1)
        desc_p[] = WGPUShaderModuleDescriptor(
            source_p.bitcast[NoneType](),
            label_sv,
        )
        var result = self._lib[].device_create_shader_module(self._handle, desc_p)
        source_p.free()
        desc_p.free()
        return ShaderModule(self._lib, result)

    def create_bind_group_layout(
        self,
        desc: WGPUBindGroupLayoutDescriptor,
    ) raises -> BindGroupLayout:
        var desc_p = alloc[WGPUBindGroupLayoutDescriptor](1)
        desc_p[] = desc
        var result = self._lib[].device_create_bind_group_layout(self._handle, desc_p)
        desc_p.free()
        return BindGroupLayout(self._lib, result)

    def create_bind_group(
        self,
        desc: WGPUBindGroupDescriptor,
    ) raises -> BindGroup:
        var desc_p = alloc[WGPUBindGroupDescriptor](1)
        desc_p[] = desc
        var result = self._lib[].device_create_bind_group(self._handle, desc_p)
        desc_p.free()
        return BindGroup(self._lib, result)

    def create_pipeline_layout(
        self,
        bind_group_layouts: List[WGPUBindGroupLayoutHandle],
        label: String = "",
    ) raises -> PipelineLayout:
        var label_sv = str_to_sv(label) if label.byte_length() > 0 else WGPUStringView.null_view()
        var layouts_ptr = rebind[UnsafePointer[WGPUBindGroupLayoutHandle, MutExternalOrigin]](bind_group_layouts.unsafe_ptr())
        var desc_p = alloc[WGPUPipelineLayoutDescriptor](1)
        desc_p[] = WGPUPipelineLayoutDescriptor(
            OpaquePtr(),
            label_sv,
            UInt(len(bind_group_layouts)),
            layouts_ptr,
            0,  # immediateDataRangeByteSize
        )
        var result = self._lib[].device_create_pipeline_layout(self._handle, desc_p)
        desc_p.free()
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
        desc_p.free()
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
            OpaquePtr(),
            shader.handle().raw,
            entry_sv,
            UInt(0),
            UnsafePointer[WGPUConstantEntry, MutExternalOrigin](),
        )
        var desc = WGPUComputePipelineDescriptor(
            OpaquePtr(), label_sv, layout.handle().raw, cs,
        )
        return self.create_compute_pipeline(desc)

    def create_render_pipeline(
        self,
        desc: WGPURenderPipelineDescriptor,
    ) raises -> RenderPipeline:
        var desc_p = alloc[WGPURenderPipelineDescriptor](1)
        desc_p[] = desc
        var result = self._lib[].device_create_render_pipeline(self._handle, desc_p)
        desc_p.free()
        return RenderPipeline(self._lib, result)

    def create_render_pipeline(
        self,
        shader: ShaderModule,
        vs_entry_point: String,
        fs_entry_point: String,
        color_format: UInt32,
        layout: PipelineLayout,
        primitive_topology: UInt32 = 3,  # TriangleList
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
            primitive_topology: Primitive topology (default 3 = TriangleList).
            label: Optional label.
        """
        var label_sv = str_to_sv(label) if label.byte_length() > 0 else WGPUStringView.null_view()
        var vs_sv = str_to_sv(vs_entry_point)
        var fs_sv = str_to_sv(fs_entry_point)

        var vertex_state = WGPUVertexState(
            OpaquePtr(), shader.handle().raw, vs_sv,
            UInt(0), UnsafePointer[WGPUConstantEntry, MutExternalOrigin](),
            UInt(0), UnsafePointer[WGPUVertexBufferLayout, MutExternalOrigin](),
        )
        var target_p = alloc[WGPUColorTargetState](1)
        target_p[0] = WGPUColorTargetState(
            OpaquePtr(), color_format,
            UnsafePointer[WGPUBlendState, MutExternalOrigin](),
            UInt64(0xF),  # ColorWriteMask.All
        )
        var fragment_p = alloc[WGPUFragmentState](1)
        fragment_p[0] = WGPUFragmentState(
            OpaquePtr(), shader.handle().raw, fs_sv,
            UInt(0), UnsafePointer[WGPUConstantEntry, MutExternalOrigin](),
            UInt(1), target_p,
        )
        var primitive = WGPUPrimitiveState(
            OpaquePtr(), primitive_topology, UInt32(0), UInt32(1), UInt32(0), UInt32(0),
        )
        var multisample = WGPUMultisampleState(
            OpaquePtr(), UInt32(1), UInt32(0xFFFFFFFF), UInt32(0),
        )
        var desc = WGPURenderPipelineDescriptor(
            OpaquePtr(), label_sv, layout.handle().raw,
            vertex_state, primitive,
            UnsafePointer[WGPUDepthStencilState, MutExternalOrigin](),
            multisample, fragment_p,
        )
        var result = self.create_render_pipeline(desc)
        target_p.free()
        fragment_p.free()
        return result^

    def create_command_encoder(self, label: String = "") raises -> CommandEncoder:
        var label_sv = str_to_sv(label) if label.byte_length() > 0 else WGPUStringView.null_view()
        var desc_p = alloc[WGPUCommandEncoderDescriptor](1)
        desc_p[] = WGPUCommandEncoderDescriptor(OpaquePtr(), label_sv)
        var result = self._lib[].device_create_command_encoder(self._handle, desc_p)
        desc_p.free()
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
            OpaquePtr(), label_sv, query_type, count
        )
        var result = self._lib[].device_create_query_set(self._handle, desc_p)
        desc_p.free()
        return QuerySet(self._lib, result)

    # ------------------------------------------------------------------
    # Queue write helpers
    # ------------------------------------------------------------------

    def queue_write_buffer[
        T: AnyType
    ](
        self,
        buffer: WGPUBufferHandle,
        offset: UInt64,
        data: UnsafePointer[T, MutExternalOrigin],
        byte_count: UInt,
    ):
        self._lib[].queue_write_buffer(
            self._queue,
            buffer,
            offset,
            data.bitcast[NoneType](),
            byte_count,
        )

    def queue_write_buffer[
        T: AnyType
    ](
        self,
        buffer: Buffer,
        offset: UInt64,
        data: UnsafePointer[T, MutExternalOrigin],
        byte_count: UInt,
    ):
        """Wrapper-first overload — accepts RAII Buffer directly."""
        self._lib[].queue_write_buffer(
            self._queue,
            buffer.handle().raw,
            offset,
            data.bitcast[NoneType](),
            byte_count,
        )

    def queue_submit(self, commands: List[WGPUCommandBufferHandle]):
        var arr = rebind[UnsafePointer[WGPUCommandBufferHandle, MutExternalOrigin]](commands.unsafe_ptr())
        self._lib[].queue_submit(self._queue, UInt(len(commands)), arr)

    def queue_submit(self, cmd: CommandBuffer):
        """Submit a single CommandBuffer (RAII wrapper).

        Borrowing `cmd` keeps it alive for the FFI call. After submit
        returns, the CommandBuffer destructor calls wgpuCommandBufferRelease.
        """
        var handle = cmd.raw()
        var handle_p = alloc[WGPUCommandBufferHandle](1)
        handle_p[] = handle
        var arr = rebind[UnsafePointer[WGPUCommandBufferHandle, MutExternalOrigin]](handle_p)
        self._lib[].queue_submit(self._queue, UInt(1), arr)
        handle_p.free()

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
        var ptr = rebind[UnsafePointer[T, MutExternalOrigin]](data.unsafe_ptr())
        self._lib[].queue_write_buffer(
            self._queue,
            buffer.handle().raw,
            offset,
            ptr.bitcast[NoneType](),
            byte_count,
        )

    # ------------------------------------------------------------------
    # Labels
    # ------------------------------------------------------------------

    def set_label(self, label: String):
        var sv = str_to_sv(label) if label.byte_length() > 0 else WGPUStringView.null_view()
        self._lib[].device_set_label(self._handle, sv)

    def queue_set_label(self, label: String):
        var sv = str_to_sv(label) if label.byte_length() > 0 else WGPUStringView.null_view()
        self._lib[].queue_set_label(self._queue, sv)

    # ------------------------------------------------------------------
    # Raw handle access
    # ------------------------------------------------------------------

    def handle(self) -> DeviceHandle:
        return DeviceHandle(self._handle)

    def queue(self) -> QueueHandle:
        return QueueHandle(self._queue)

    def instance(self) -> InstanceHandleNewtype:
        return InstanceHandleNewtype(self._instance)
