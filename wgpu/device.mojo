"""
wgpu.device — High-level Device + Queue RAII wrapper.
"""

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
from wgpu._ffi.structs import (
    WGPUStringView, WGPUExtent3D, WGPULimits, WGPUSupportedFeatures,
    wgpu_limits_default,
    WGPUBufferDescriptor,
    WGPUTextureDescriptor,
    WGPUSamplerDescriptor,
    WGPUShaderModuleDescriptor, WGPUShaderSourceWGSL, WGPUShaderSourceSPIRV,
    WGPUBindGroupDescriptor, WGPUBindGroupLayoutDescriptor,
    WGPUPipelineLayoutDescriptor,
    WGPUComputePipelineDescriptor, WGPURenderPipelineDescriptor,
    WGPUCommandEncoderDescriptor,
    WGPUQuerySetDescriptor,
    WGPUChainedStruct,
    str_to_sv,
)
from wgpu._ffi.types import WGPUSType


struct Device(Movable):
    """
    Owns a WGPUDevice + WGPUQueue.
    The Device borrows a shared reference to WGPULib (owned by Instance).
    To avoid ownership complexity, we store a separate WGPULib copy.
    """

    var _lib:      WGPULib
    var _instance: WGPUInstanceHandle
    var _handle:   WGPUDeviceHandle
    var _queue:    WGPUQueueHandle

    def __init__(
        out self,
        instance: WGPUInstanceHandle,
        handle: WGPUDeviceHandle,
        queue: WGPUQueueHandle,
    ) raises:
        self._lib      = WGPULib()
        self._instance = instance
        self._handle   = handle
        self._queue    = queue

    def __init__(out self, *, deinit take: Self):
        self._lib      = take._lib^
        self._instance = take._instance
        self._handle   = take._handle
        self._queue    = take._queue

    def __del__(deinit self):
        self._lib.queue_release(self._queue)
        self._lib.device_destroy(self._handle)
        self._lib.device_release(self._handle)

    # ------------------------------------------------------------------
    # Limits / features
    # ------------------------------------------------------------------

    def get_limits(self) -> WGPULimits:
        var limits_p = alloc[WGPULimits](1)
        limits_p[] = wgpu_limits_default()
        _ = self._lib.device_get_limits(self._handle, limits_p)
        var result = limits_p[]
        limits_p.free()
        return result

    def has_feature(self, feature: UInt32) -> Bool:
        return self._lib.device_has_feature(self._handle, feature) == WGPU_TRUE

    def poll(self, wait: Bool = True) -> Bool:
        return self._lib.device_poll(self._handle, wait) == WGPU_TRUE

    # ------------------------------------------------------------------
    # Resource creation helpers
    # ------------------------------------------------------------------

    def create_buffer(
        self,
        size: UInt64,
        usage: WGPUBufferUsage,
        mapped_at_creation: Bool = False,
        label: String = "",
    ) -> WGPUBufferHandle:
        var label_sv = str_to_sv(label) if len(label) > 0 else WGPUStringView.null_view()
        var mapped: UInt32 = 1 if mapped_at_creation else 0
        var desc_p = alloc[WGPUBufferDescriptor](1)
        desc_p[] = WGPUBufferDescriptor(
            OpaquePtr(),
            label_sv,
            usage.value,
            size,
            mapped,
        )
        var result = self._lib.device_create_buffer(self._handle, desc_p)
        desc_p.free()
        return result

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
    ) -> WGPUTextureHandle:
        var label_sv = str_to_sv(label) if len(label) > 0 else WGPUStringView.null_view()
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
        var result = self._lib.device_create_texture(self._handle, desc_p)
        desc_p.free()
        return result

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
    ) -> WGPUSamplerHandle:
        var label_sv = str_to_sv(label) if len(label) > 0 else WGPUStringView.null_view()
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
        var result = self._lib.device_create_sampler(self._handle, desc_p)
        desc_p.free()
        return result

    def create_shader_module_wgsl(
        self,
        code: String,
        label: String = "",
    ) -> WGPUShaderModuleHandle:
        var label_sv = str_to_sv(label) if len(label) > 0 else WGPUStringView.null_view()
        var code_sv  = str_to_sv(code)
        var chain_val = WGPUChainedStruct(OpaquePtr(), WGPUSType.ShaderSourceWGSL)
        var source_p = alloc[WGPUShaderSourceWGSL](1)
        source_p[] = WGPUShaderSourceWGSL(chain_val, code_sv)
        var desc_p = alloc[WGPUShaderModuleDescriptor](1)
        desc_p[] = WGPUShaderModuleDescriptor(
            source_p.bitcast[NoneType](),
            label_sv,
        )
        var result = self._lib.device_create_shader_module(self._handle, desc_p)
        source_p.free()
        desc_p.free()
        return result

    def create_shader_module_spirv(
        self,
        code: List[UInt32],
        label: String = "",
    ) -> WGPUShaderModuleHandle:
        var label_sv = str_to_sv(label) if len(label) > 0 else WGPUStringView.null_view()
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
        var result = self._lib.device_create_shader_module(self._handle, desc_p)
        source_p.free()
        desc_p.free()
        return result

    def create_bind_group_layout(
        self,
        desc: WGPUBindGroupLayoutDescriptor,
    ) -> WGPUBindGroupLayoutHandle:
        var desc_p = alloc[WGPUBindGroupLayoutDescriptor](1)
        desc_p[] = desc
        var result = self._lib.device_create_bind_group_layout(self._handle, desc_p)
        desc_p.free()
        return result

    def create_bind_group(
        self,
        desc: WGPUBindGroupDescriptor,
    ) -> WGPUBindGroupHandle:
        var desc_p = alloc[WGPUBindGroupDescriptor](1)
        desc_p[] = desc
        var result = self._lib.device_create_bind_group(self._handle, desc_p)
        desc_p.free()
        return result

    def create_pipeline_layout(
        self,
        bind_group_layouts: List[WGPUBindGroupLayoutHandle],
        label: String = "",
    ) -> WGPUPipelineLayoutHandle:
        var label_sv = str_to_sv(label) if len(label) > 0 else WGPUStringView.null_view()
        var layouts_ptr = rebind[UnsafePointer[WGPUBindGroupLayoutHandle, MutExternalOrigin]](bind_group_layouts.unsafe_ptr())
        var desc_p = alloc[WGPUPipelineLayoutDescriptor](1)
        desc_p[] = WGPUPipelineLayoutDescriptor(
            OpaquePtr(),
            label_sv,
            UInt(len(bind_group_layouts)),
            layouts_ptr,
            0,  # immediateDataRangeByteSize
        )
        var result = self._lib.device_create_pipeline_layout(self._handle, desc_p)
        desc_p.free()
        return result

    def create_compute_pipeline(
        self,
        desc: WGPUComputePipelineDescriptor,
    ) -> WGPUComputePipelineHandle:
        var desc_p = alloc[WGPUComputePipelineDescriptor](1)
        desc_p[] = desc
        var result = self._lib.device_create_compute_pipeline(self._handle, desc_p)
        desc_p.free()
        return result

    def create_render_pipeline(
        self,
        desc: WGPURenderPipelineDescriptor,
    ) -> WGPURenderPipelineHandle:
        var desc_p = alloc[WGPURenderPipelineDescriptor](1)
        desc_p[] = desc
        var result = self._lib.device_create_render_pipeline(self._handle, desc_p)
        desc_p.free()
        return result

    def create_command_encoder(self, label: String = "") -> WGPUCommandEncoderHandle:
        var label_sv = str_to_sv(label) if len(label) > 0 else WGPUStringView.null_view()
        var desc_p = alloc[WGPUCommandEncoderDescriptor](1)
        desc_p[] = WGPUCommandEncoderDescriptor(OpaquePtr(), label_sv)
        var result = self._lib.device_create_command_encoder(self._handle, desc_p)
        desc_p.free()
        return result

    def create_query_set(
        self,
        query_type: UInt32,
        count: UInt32,
        label: String = "",
    ) -> WGPUQuerySetHandle:
        var label_sv = str_to_sv(label) if len(label) > 0 else WGPUStringView.null_view()
        var desc_p = alloc[WGPUQuerySetDescriptor](1)
        desc_p[] = WGPUQuerySetDescriptor(
            OpaquePtr(), label_sv, query_type, count
        )
        var result = self._lib.device_create_query_set(self._handle, desc_p)
        desc_p.free()
        return result

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
        self._lib.queue_write_buffer(
            self._queue,
            buffer,
            offset,
            data.bitcast[NoneType](),
            byte_count,
        )

    def queue_submit(self, commands: List[WGPUCommandBufferHandle]):
        var arr = rebind[UnsafePointer[WGPUCommandBufferHandle, MutExternalOrigin]](commands.unsafe_ptr())
        self._lib.queue_submit(self._queue, UInt(len(commands)), arr)

    # ------------------------------------------------------------------
    # Raw handle access
    # ------------------------------------------------------------------

    def handle(self) -> WGPUDeviceHandle:
        return self._handle

    def queue(self) -> WGPUQueueHandle:
        return self._queue

    def instance(self) -> WGPUInstanceHandle:
        return self._instance
