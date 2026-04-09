"""
wgpu._ffi.lib — Dynamic library loader and raw function dispatcher.

Loads libwgpu_native.so and libwgpu_mojo_cb.so at runtime and exposes
every webgpu.h + wgpu.h function as a method call.
"""

from std.ffi import OwnedDLHandle
from wgpu._ffi.types import (
    OpaquePtr,
    WGPUAdapterHandle, WGPUBindGroupHandle, WGPUBindGroupLayoutHandle,
    WGPUBufferHandle, WGPUCommandBufferHandle, WGPUCommandEncoderHandle,
    WGPUComputePassEncoderHandle, WGPUComputePipelineHandle, WGPUDeviceHandle,
    WGPUInstanceHandle, WGPUPipelineLayoutHandle,
    WGPUQuerySetHandle, WGPUQueueHandle, WGPURenderBundleHandle,
    WGPURenderBundleEncoderHandle, WGPURenderPassEncoderHandle,
    WGPURenderPipelineHandle, WGPUSamplerHandle, WGPUShaderModuleHandle,
    WGPUSurfaceHandle, WGPUTextureHandle, WGPUTextureViewHandle,
    WGPUBufferUsage, WGPUMapMode, WGPU_TRUE, WGPU_FALSE,
    WGPURequestAdapterStatus, WGPURequestDeviceStatus, WGPUMapAsyncStatus,
    WGPUCallbackMode,
)
from wgpu._ffi.structs import (
    WGPUStringView, WGPUFuture, WGPUFutureWaitInfo, str_to_sv,
    WGPUAdapterInfo,
    WGPUBufferDescriptor, WGPUBufferMapCallbackInfo,
    WGPUCommandBufferDescriptor, WGPUCommandEncoderDescriptor,
    WGPUComputePassDescriptor, WGPUComputePipelineDescriptor,
    WGPUDeviceDescriptor, WGPUDeviceLostCallbackInfo, WGPUUncapturedErrorCallbackInfo,
    WGPUInstanceDescriptor,
    WGPUBindGroupDescriptor, WGPUBindGroupLayoutDescriptor,
    WGPUPassTimestampWrites, WGPUPipelineLayoutDescriptor,
    WGPUQuerySetDescriptor, WGPURenderBundleDescriptor,
    WGPURenderBundleEncoderDescriptor,
    WGPURenderPassDescriptor, WGPURenderPipelineDescriptor,
    WGPURequestAdapterCallbackInfo, WGPURequestDeviceCallbackInfo,
    WGPURequestAdapterOptions,
    WGPUSamplerDescriptor, WGPUShaderModuleDescriptor,
    WGPUSurfaceDescriptor, WGPUSurfaceCapabilities, WGPUSurfaceConfiguration,
    WGPUSurfaceTexture,
    WGPUTexelCopyBufferInfo, WGPUTexelCopyTextureInfo,
    WGPUTextureDescriptor, WGPUTextureViewDescriptor,
    WGPULimits, WGPUSupportedFeatures,
    WGPUQueueWorkDoneCallbackInfo,
    WGPUExtent3D,
)

# ---------------------------------------------------------------------------
# Callback result structs (must match C layout in wgpu_callbacks.c)
# ---------------------------------------------------------------------------

@fieldwise_init
struct _AdapterResult(TrivialRegisterPassable):
    var adapter: WGPUAdapterHandle
    var status: UInt32


@fieldwise_init
struct _DeviceResult(TrivialRegisterPassable):
    var device: WGPUDeviceHandle
    var status: UInt32


@fieldwise_init
struct _MapResult(TrivialRegisterPassable):
    var status: UInt32


@fieldwise_init
struct _WorkDoneResult(TrivialRegisterPassable):
    var status: UInt32


# ---------------------------------------------------------------------------
# Path constants — relative to cwd (typically project root)
# ---------------------------------------------------------------------------

comptime _WGPU_LIB_PATH  = "ffi/lib/libwgpu_native.so"
comptime _CB_LIB_PATH    = "ffi/lib/libwgpu_mojo_cb.so"


# ---------------------------------------------------------------------------
# WGPULib — owns two DLHandles and dispatches all WGPU function calls
# ---------------------------------------------------------------------------

struct WGPULib(Movable):
    """Loaded wgpu-native shared library + callback helpers."""

    var _wgpu: OwnedDLHandle
    var _cb:   OwnedDLHandle

    # Cached callback function pointers (void*)
    var _adapter_cb_ptr: OpaquePtr
    var _device_cb_ptr: OpaquePtr
    var _map_cb_ptr: OpaquePtr
    var _done_cb_ptr: OpaquePtr

    def __init__(out self) raises:
        self._wgpu = OwnedDLHandle(_WGPU_LIB_PATH)
        self._cb   = OwnedDLHandle(_CB_LIB_PATH)
        self._adapter_cb_ptr = self._cb.call["wgpu_mojo_get_adapter_callback", OpaquePtr]()
        self._device_cb_ptr  = self._cb.call["wgpu_mojo_get_device_callback",  OpaquePtr]()
        self._map_cb_ptr     = self._cb.call["wgpu_mojo_get_buffer_map_callback", OpaquePtr]()
        self._done_cb_ptr    = self._cb.call["wgpu_mojo_get_queue_done_callback", OpaquePtr]()

    def __init__(out self, *, deinit take: Self):
        self._wgpu = take._wgpu^
        self._cb   = take._cb^
        self._adapter_cb_ptr = take._adapter_cb_ptr
        self._device_cb_ptr  = take._device_cb_ptr
        self._map_cb_ptr     = take._map_cb_ptr
        self._done_cb_ptr    = take._done_cb_ptr

    # ------------------------------------------------------------------
    # Global functions
    # ------------------------------------------------------------------

    def get_version(self) -> UInt32:
        return self._wgpu.call["wgpuGetVersion", UInt32]()

    def create_instance(self, desc: UnsafePointer[WGPUInstanceDescriptor, MutExternalOrigin]) -> WGPUInstanceHandle:
        return self._wgpu.call["wgpuCreateInstance", WGPUInstanceHandle](desc)

    # ------------------------------------------------------------------
    # Instance methods
    # ------------------------------------------------------------------

    def instance_enumerate_adapters(
        self,
        instance: WGPUInstanceHandle,
        options: OpaquePtr,
        adapters: UnsafePointer[WGPUAdapterHandle, MutExternalOrigin],
    ) -> UInt:
        return self._wgpu.call["wgpuInstanceEnumerateAdapters", UInt](
            instance, options, adapters
        )

    def instance_request_adapter_sync(
        self,
        instance: WGPUInstanceHandle,
        options: UnsafePointer[WGPURequestAdapterOptions, MutExternalOrigin],
    ) raises -> _AdapterResult:
        """Synchronously request an adapter via WGPUCallbackMode_WaitAnyOnly."""
        var result = alloc[_AdapterResult](1)
        result[] = _AdapterResult(WGPUAdapterHandle(), 0)

        var cb_info = WGPURequestAdapterCallbackInfo(
            OpaquePtr(),
            WGPUCallbackMode.WaitAnyOnly,
            self._adapter_cb_ptr,
            result.bitcast[NoneType](),
            OpaquePtr(),
        )
        var future = self._wgpu.call["wgpuInstanceRequestAdapter", WGPUFuture](
            instance, options, cb_info
        )
        var wait_info_p = alloc[WGPUFutureWaitInfo](1)
        wait_info_p[] = WGPUFutureWaitInfo(future, WGPU_FALSE)
        _ = self._wgpu.call["wgpuInstanceWaitAny", UInt32](
            instance,
            UInt(1),
            wait_info_p.bitcast[NoneType](),
            UInt64.MAX,
        )
        var adapter = result[].adapter
        var status  = result[].status
        result.free()
        wait_info_p.free()
        return _AdapterResult(adapter, status)

    def instance_process_events(self, instance: WGPUInstanceHandle):
        self._wgpu.call["wgpuInstanceProcessEvents"](instance)

    def instance_wait_any(
        self,
        instance: WGPUInstanceHandle,
        count: UInt,
        waits: UnsafePointer[WGPUFutureWaitInfo, MutExternalOrigin],
        timeout_ns: UInt64,
    ) -> UInt32:
        return self._wgpu.call["wgpuInstanceWaitAny", UInt32](
            instance, count, waits, timeout_ns
        )

    def instance_create_surface(
        self,
        instance: WGPUInstanceHandle,
        desc: UnsafePointer[WGPUSurfaceDescriptor, MutExternalOrigin],
    ) -> WGPUSurfaceHandle:
        return self._wgpu.call["wgpuInstanceCreateSurface", WGPUSurfaceHandle](
            instance, desc
        )

    def instance_release(self, instance: WGPUInstanceHandle):
        self._wgpu.call["wgpuInstanceRelease"](instance)

    def instance_add_ref(self, instance: WGPUInstanceHandle):
        self._wgpu.call["wgpuInstanceAddRef"](instance)

    # ------------------------------------------------------------------
    # Adapter methods
    # ------------------------------------------------------------------

    def adapter_request_device_sync(
        self,
        instance: WGPUInstanceHandle,
        adapter: WGPUAdapterHandle,
        desc: UnsafePointer[WGPUDeviceDescriptor, MutExternalOrigin],
    ) raises -> _DeviceResult:
        """Synchronously request a device via WGPUCallbackMode_WaitAnyOnly."""
        var result = alloc[_DeviceResult](1)
        result[] = _DeviceResult(WGPUDeviceHandle(), 0)

        var cb_info = WGPURequestDeviceCallbackInfo(
            OpaquePtr(),
            WGPUCallbackMode.WaitAnyOnly,
            self._device_cb_ptr,
            result.bitcast[NoneType](),
            OpaquePtr(),
        )
        var future = self._wgpu.call["wgpuAdapterRequestDevice", WGPUFuture](
            adapter, desc, cb_info
        )
        var wait_info_p = alloc[WGPUFutureWaitInfo](1)
        wait_info_p[] = WGPUFutureWaitInfo(future, WGPU_FALSE)
        _ = self._wgpu.call["wgpuInstanceWaitAny", UInt32](
            instance,
            UInt(1),
            wait_info_p.bitcast[NoneType](),
            UInt64.MAX,
        )
        var device = result[].device
        var status = result[].status
        result.free()
        wait_info_p.free()
        return _DeviceResult(device, status)

    def adapter_get_info(
        self,
        adapter: WGPUAdapterHandle,
        info: UnsafePointer[WGPUAdapterInfo, MutExternalOrigin],
    ) -> UInt32:
        return self._wgpu.call["wgpuAdapterGetInfo", UInt32](adapter, info)

    def adapter_get_limits(
        self,
        adapter: WGPUAdapterHandle,
        limits: UnsafePointer[WGPULimits, MutExternalOrigin],
    ) -> UInt32:
        return self._wgpu.call["wgpuAdapterGetLimits", UInt32](adapter, limits)

    def adapter_get_features(
        self,
        adapter: WGPUAdapterHandle,
        features: UnsafePointer[WGPUSupportedFeatures, MutExternalOrigin],
    ):
        self._wgpu.call["wgpuAdapterGetFeatures"](adapter, features)

    def adapter_has_feature(self, adapter: WGPUAdapterHandle, feature: UInt32) -> UInt32:
        return self._wgpu.call["wgpuAdapterHasFeature", UInt32](adapter, feature)

    def adapter_info_free_members(self, info: WGPUAdapterInfo):
        self._wgpu.call["wgpuAdapterInfoFreeMembers"](info)

    def adapter_release(self, adapter: WGPUAdapterHandle):
        self._wgpu.call["wgpuAdapterRelease"](adapter)

    def adapter_add_ref(self, adapter: WGPUAdapterHandle):
        self._wgpu.call["wgpuAdapterAddRef"](adapter)

    # ------------------------------------------------------------------
    # Device methods
    # ------------------------------------------------------------------

    def device_create_buffer(
        self,
        device: WGPUDeviceHandle,
        desc: UnsafePointer[WGPUBufferDescriptor, MutExternalOrigin],
    ) -> WGPUBufferHandle:
        return self._wgpu.call["wgpuDeviceCreateBuffer", WGPUBufferHandle](device, desc)

    def device_create_command_encoder(
        self,
        device: WGPUDeviceHandle,
        desc: UnsafePointer[WGPUCommandEncoderDescriptor, MutExternalOrigin],
    ) -> WGPUCommandEncoderHandle:
        return self._wgpu.call["wgpuDeviceCreateCommandEncoder", WGPUCommandEncoderHandle](
            device, desc
        )

    def device_create_compute_pipeline(
        self,
        device: WGPUDeviceHandle,
        desc: UnsafePointer[WGPUComputePipelineDescriptor, MutExternalOrigin],
    ) -> WGPUComputePipelineHandle:
        return self._wgpu.call["wgpuDeviceCreateComputePipeline", WGPUComputePipelineHandle](
            device, desc
        )

    def device_create_render_pipeline(
        self,
        device: WGPUDeviceHandle,
        desc: UnsafePointer[WGPURenderPipelineDescriptor, MutExternalOrigin],
    ) -> WGPURenderPipelineHandle:
        return self._wgpu.call["wgpuDeviceCreateRenderPipeline", WGPURenderPipelineHandle](
            device, desc
        )

    def device_create_shader_module(
        self,
        device: WGPUDeviceHandle,
        desc: UnsafePointer[WGPUShaderModuleDescriptor, MutExternalOrigin],
    ) -> WGPUShaderModuleHandle:
        return self._wgpu.call["wgpuDeviceCreateShaderModule", WGPUShaderModuleHandle](
            device, desc
        )

    def device_create_bind_group(
        self,
        device: WGPUDeviceHandle,
        desc: UnsafePointer[WGPUBindGroupDescriptor, MutExternalOrigin],
    ) -> WGPUBindGroupHandle:
        return self._wgpu.call["wgpuDeviceCreateBindGroup", WGPUBindGroupHandle](device, desc)

    def device_create_bind_group_layout(
        self,
        device: WGPUDeviceHandle,
        desc: UnsafePointer[WGPUBindGroupLayoutDescriptor, MutExternalOrigin],
    ) -> WGPUBindGroupLayoutHandle:
        return self._wgpu.call["wgpuDeviceCreateBindGroupLayout", WGPUBindGroupLayoutHandle](
            device, desc
        )

    def device_create_pipeline_layout(
        self,
        device: WGPUDeviceHandle,
        desc: UnsafePointer[WGPUPipelineLayoutDescriptor, MutExternalOrigin],
    ) -> WGPUPipelineLayoutHandle:
        return self._wgpu.call["wgpuDeviceCreatePipelineLayout", WGPUPipelineLayoutHandle](
            device, desc
        )

    def device_create_sampler(
        self,
        device: WGPUDeviceHandle,
        desc: UnsafePointer[WGPUSamplerDescriptor, MutExternalOrigin],
    ) -> WGPUSamplerHandle:
        return self._wgpu.call["wgpuDeviceCreateSampler", WGPUSamplerHandle](device, desc)

    def device_create_texture(
        self,
        device: WGPUDeviceHandle,
        desc: UnsafePointer[WGPUTextureDescriptor, MutExternalOrigin],
    ) -> WGPUTextureHandle:
        return self._wgpu.call["wgpuDeviceCreateTexture", WGPUTextureHandle](device, desc)

    def device_create_query_set(
        self,
        device: WGPUDeviceHandle,
        desc: UnsafePointer[WGPUQuerySetDescriptor, MutExternalOrigin],
    ) -> WGPUQuerySetHandle:
        return self._wgpu.call["wgpuDeviceCreateQuerySet", WGPUQuerySetHandle](device, desc)

    def device_get_queue(self, device: WGPUDeviceHandle) -> WGPUQueueHandle:
        return self._wgpu.call["wgpuDeviceGetQueue", WGPUQueueHandle](device)

    def device_get_limits(
        self,
        device: WGPUDeviceHandle,
        limits: UnsafePointer[WGPULimits, MutExternalOrigin],
    ) -> UInt32:
        return self._wgpu.call["wgpuDeviceGetLimits", UInt32](device, limits)

    def device_has_feature(self, device: WGPUDeviceHandle, feature: UInt32) -> UInt32:
        return self._wgpu.call["wgpuDeviceHasFeature", UInt32](device, feature)

    def device_poll(self, device: WGPUDeviceHandle, wait: UInt32) -> UInt32:
        return self._wgpu.call["wgpuDevicePoll", UInt32](device, wait, OpaquePtr())

    def device_push_error_scope(self, device: WGPUDeviceHandle, filter: UInt32):
        self._wgpu.call["wgpuDevicePushErrorScope"](device, filter)

    def device_destroy(self, device: WGPUDeviceHandle):
        self._wgpu.call["wgpuDeviceDestroy"](device)

    def device_release(self, device: WGPUDeviceHandle):
        self._wgpu.call["wgpuDeviceRelease"](device)

    def device_add_ref(self, device: WGPUDeviceHandle):
        self._wgpu.call["wgpuDeviceAddRef"](device)

    # ------------------------------------------------------------------
    # Buffer methods
    # ------------------------------------------------------------------

    def buffer_map_async(
        self,
        instance: WGPUInstanceHandle,
        device: WGPUDeviceHandle,
        buffer: WGPUBufferHandle,
        mode: UInt64,
        offset: UInt,
        size: UInt,
    ) raises -> UInt32:
        """Map a buffer and block until mapping is complete. Returns status."""
        var result = alloc[_MapResult](1)
        result[] = _MapResult(0)

        var cb_info = WGPUBufferMapCallbackInfo(
            OpaquePtr(),
            WGPUCallbackMode.WaitAnyOnly,
            self._map_cb_ptr,
            result.bitcast[NoneType](),
            OpaquePtr(),
        )
        var future = self._wgpu.call["wgpuBufferMapAsync", WGPUFuture](
            buffer, mode, offset, size, cb_info
        )
        var wait_info_p = alloc[WGPUFutureWaitInfo](1)
        wait_info_p[] = WGPUFutureWaitInfo(future, WGPU_FALSE)
        _ = self._wgpu.call["wgpuInstanceWaitAny", UInt32](
            instance,
            UInt(1),
            wait_info_p.bitcast[NoneType](),
            UInt64.MAX,
        )
        var status = result[].status
        result.free()
        wait_info_p.free()
        return status

    def buffer_get_mapped_range(
        self,
        buffer: WGPUBufferHandle,
        offset: UInt,
        size: UInt,
    ) -> OpaquePtr:
        return self._wgpu.call["wgpuBufferGetMappedRange", OpaquePtr](buffer, offset, size)

    def buffer_get_const_mapped_range(
        self,
        buffer: WGPUBufferHandle,
        offset: UInt,
        size: UInt,
    ) -> OpaquePtr:
        return self._wgpu.call["wgpuBufferGetConstMappedRange", OpaquePtr](buffer, offset, size)

    def buffer_unmap(self, buffer: WGPUBufferHandle):
        self._wgpu.call["wgpuBufferUnmap"](buffer)

    def buffer_get_size(self, buffer: WGPUBufferHandle) -> UInt64:
        return self._wgpu.call["wgpuBufferGetSize", UInt64](buffer)

    def buffer_get_usage(self, buffer: WGPUBufferHandle) -> UInt64:
        return self._wgpu.call["wgpuBufferGetUsage", UInt64](buffer)

    def buffer_get_map_state(self, buffer: WGPUBufferHandle) -> UInt32:
        return self._wgpu.call["wgpuBufferGetMapState", UInt32](buffer)

    def buffer_write_mapped_range(
        self,
        buffer: WGPUBufferHandle,
        offset: UInt,
        data: OpaquePtr,
        size: UInt,
    ) -> UInt32:
        return self._wgpu.call["wgpuBufferWriteMappedRange", UInt32](
            buffer, offset, data, size
        )

    def buffer_read_mapped_range(
        self,
        buffer: WGPUBufferHandle,
        offset: UInt,
        data: OpaquePtr,
        size: UInt,
    ) -> UInt32:
        return self._wgpu.call["wgpuBufferReadMappedRange", UInt32](
            buffer, offset, data, size
        )

    def buffer_destroy(self, buffer: WGPUBufferHandle):
        self._wgpu.call["wgpuBufferDestroy"](buffer)

    def buffer_release(self, buffer: WGPUBufferHandle):
        self._wgpu.call["wgpuBufferRelease"](buffer)

    def buffer_add_ref(self, buffer: WGPUBufferHandle):
        self._wgpu.call["wgpuBufferAddRef"](buffer)

    # ------------------------------------------------------------------
    # CommandEncoder methods
    # ------------------------------------------------------------------

    def command_encoder_begin_compute_pass(
        self,
        encoder: WGPUCommandEncoderHandle,
        desc: UnsafePointer[WGPUComputePassDescriptor, MutExternalOrigin],
    ) -> WGPUComputePassEncoderHandle:
        return self._wgpu.call["wgpuCommandEncoderBeginComputePass", WGPUComputePassEncoderHandle](
            encoder, desc
        )

    def command_encoder_begin_render_pass(
        self,
        encoder: WGPUCommandEncoderHandle,
        desc: UnsafePointer[WGPURenderPassDescriptor, MutExternalOrigin],
    ) -> WGPURenderPassEncoderHandle:
        return self._wgpu.call["wgpuCommandEncoderBeginRenderPass", WGPURenderPassEncoderHandle](
            encoder, desc
        )

    def command_encoder_copy_buffer_to_buffer(
        self,
        encoder: WGPUCommandEncoderHandle,
        src: WGPUBufferHandle,
        src_offset: UInt64,
        dst: WGPUBufferHandle,
        dst_offset: UInt64,
        size: UInt64,
    ):
        self._wgpu.call["wgpuCommandEncoderCopyBufferToBuffer"](
            encoder, src, src_offset, dst, dst_offset, size
        )

    def command_encoder_copy_buffer_to_texture(
        self,
        encoder: WGPUCommandEncoderHandle,
        src: UnsafePointer[WGPUTexelCopyBufferInfo, MutExternalOrigin],
        dst: UnsafePointer[WGPUTexelCopyTextureInfo, MutExternalOrigin],
        size: UnsafePointer[WGPUExtent3D, MutExternalOrigin],
    ):
        self._wgpu.call["wgpuCommandEncoderCopyBufferToTexture"](encoder, src, dst, size)

    def command_encoder_copy_texture_to_buffer(
        self,
        encoder: WGPUCommandEncoderHandle,
        src: UnsafePointer[WGPUTexelCopyTextureInfo, MutExternalOrigin],
        dst: UnsafePointer[WGPUTexelCopyBufferInfo, MutExternalOrigin],
        size: UnsafePointer[WGPUExtent3D, MutExternalOrigin],
    ):
        self._wgpu.call["wgpuCommandEncoderCopyTextureToBuffer"](encoder, src, dst, size)

    def command_encoder_clear_buffer(
        self,
        encoder: WGPUCommandEncoderHandle,
        buffer: WGPUBufferHandle,
        offset: UInt64,
        size: UInt64,
    ):
        self._wgpu.call["wgpuCommandEncoderClearBuffer"](encoder, buffer, offset, size)

    def command_encoder_resolve_query_set(
        self,
        encoder: WGPUCommandEncoderHandle,
        query_set: WGPUQuerySetHandle,
        first_query: UInt32,
        query_count: UInt32,
        destination: WGPUBufferHandle,
        destination_offset: UInt64,
    ):
        self._wgpu.call["wgpuCommandEncoderResolveQuerySet"](
            encoder, query_set, first_query, query_count, destination, destination_offset
        )

    def command_encoder_finish(
        self,
        encoder: WGPUCommandEncoderHandle,
        desc: UnsafePointer[WGPUCommandBufferDescriptor, MutExternalOrigin],
    ) -> WGPUCommandBufferHandle:
        return self._wgpu.call["wgpuCommandEncoderFinish", WGPUCommandBufferHandle](
            encoder, desc
        )

    def command_encoder_release(self, encoder: WGPUCommandEncoderHandle):
        self._wgpu.call["wgpuCommandEncoderRelease"](encoder)

    def command_buffer_release(self, cmd_buf: WGPUCommandBufferHandle):
        self._wgpu.call["wgpuCommandBufferRelease"](cmd_buf)

    # ------------------------------------------------------------------
    # ComputePassEncoder methods
    # ------------------------------------------------------------------

    def compute_pass_set_pipeline(
        self,
        pass_enc: WGPUComputePassEncoderHandle,
        pipeline: WGPUComputePipelineHandle,
    ):
        self._wgpu.call["wgpuComputePassEncoderSetPipeline"](pass_enc, pipeline)

    def compute_pass_set_bind_group(
        self,
        pass_enc: WGPUComputePassEncoderHandle,
        index: UInt32,
        bind_group: WGPUBindGroupHandle,
        dynamic_offsets: OpaquePtr,
        dynamic_offset_count: UInt,
    ):
        self._wgpu.call["wgpuComputePassEncoderSetBindGroup"](
            pass_enc, index, bind_group, dynamic_offset_count, dynamic_offsets
        )

    def compute_pass_dispatch_workgroups(
        self,
        pass_enc: WGPUComputePassEncoderHandle,
        x: UInt32,
        y: UInt32,
        z: UInt32,
    ):
        self._wgpu.call["wgpuComputePassEncoderDispatchWorkgroups"](pass_enc, x, y, z)

    def compute_pass_dispatch_workgroups_indirect(
        self,
        pass_enc: WGPUComputePassEncoderHandle,
        indirect_buffer: WGPUBufferHandle,
        indirect_offset: UInt64,
    ):
        self._wgpu.call["wgpuComputePassEncoderDispatchWorkgroupsIndirect"](
            pass_enc, indirect_buffer, indirect_offset
        )

    def compute_pass_end(self, pass_enc: WGPUComputePassEncoderHandle):
        self._wgpu.call["wgpuComputePassEncoderEnd"](pass_enc)

    def compute_pass_release(self, pass_enc: WGPUComputePassEncoderHandle):
        self._wgpu.call["wgpuComputePassEncoderRelease"](pass_enc)

    # ------------------------------------------------------------------
    # RenderPassEncoder methods
    # ------------------------------------------------------------------

    def render_pass_set_pipeline(
        self,
        pass_enc: WGPURenderPassEncoderHandle,
        pipeline: WGPURenderPipelineHandle,
    ):
        self._wgpu.call["wgpuRenderPassEncoderSetPipeline"](pass_enc, pipeline)

    def render_pass_set_bind_group(
        self,
        pass_enc: WGPURenderPassEncoderHandle,
        index: UInt32,
        bind_group: WGPUBindGroupHandle,
        dynamic_offset_count: UInt,
        dynamic_offsets: OpaquePtr,
    ):
        self._wgpu.call["wgpuRenderPassEncoderSetBindGroup"](
            pass_enc, index, bind_group, dynamic_offset_count, dynamic_offsets
        )

    def render_pass_set_vertex_buffer(
        self,
        pass_enc: WGPURenderPassEncoderHandle,
        slot: UInt32,
        buffer: WGPUBufferHandle,
        offset: UInt64,
        size: UInt64,
    ):
        self._wgpu.call["wgpuRenderPassEncoderSetVertexBuffer"](
            pass_enc, slot, buffer, offset, size
        )

    def render_pass_set_index_buffer(
        self,
        pass_enc: WGPURenderPassEncoderHandle,
        buffer: WGPUBufferHandle,
        format: UInt32,
        offset: UInt64,
        size: UInt64,
    ):
        self._wgpu.call["wgpuRenderPassEncoderSetIndexBuffer"](
            pass_enc, buffer, format, offset, size
        )

    def render_pass_draw(
        self,
        pass_enc: WGPURenderPassEncoderHandle,
        vertex_count: UInt32,
        instance_count: UInt32,
        first_vertex: UInt32,
        first_instance: UInt32,
    ):
        self._wgpu.call["wgpuRenderPassEncoderDraw"](
            pass_enc, vertex_count, instance_count, first_vertex, first_instance
        )

    def render_pass_draw_indexed(
        self,
        pass_enc: WGPURenderPassEncoderHandle,
        index_count: UInt32,
        instance_count: UInt32,
        first_index: UInt32,
        base_vertex: Int32,
        first_instance: UInt32,
    ):
        self._wgpu.call["wgpuRenderPassEncoderDrawIndexed"](
            pass_enc, index_count, instance_count, first_index, base_vertex, first_instance
        )

    def render_pass_set_scissor_rect(
        self,
        pass_enc: WGPURenderPassEncoderHandle,
        x: UInt32, y: UInt32, width: UInt32, height: UInt32,
    ):
        self._wgpu.call["wgpuRenderPassEncoderSetScissorRect"](pass_enc, x, y, width, height)

    def render_pass_set_viewport(
        self,
        pass_enc: WGPURenderPassEncoderHandle,
        x: Float32, y: Float32,
        width: Float32, height: Float32,
        min_depth: Float32, max_depth: Float32,
    ):
        self._wgpu.call["wgpuRenderPassEncoderSetViewport"](
            pass_enc, x, y, width, height, min_depth, max_depth
        )

    def render_pass_set_blend_constant(
        self,
        pass_enc: WGPURenderPassEncoderHandle,
        color: OpaquePtr,
    ):
        self._wgpu.call["wgpuRenderPassEncoderSetBlendConstant"](pass_enc, color)

    def render_pass_end(self, pass_enc: WGPURenderPassEncoderHandle):
        self._wgpu.call["wgpuRenderPassEncoderEnd"](pass_enc)

    def render_pass_release(self, pass_enc: WGPURenderPassEncoderHandle):
        self._wgpu.call["wgpuRenderPassEncoderRelease"](pass_enc)

    # ------------------------------------------------------------------
    # Queue methods
    # ------------------------------------------------------------------

    def queue_submit(
        self,
        queue: WGPUQueueHandle,
        count: UInt,
        commands: UnsafePointer[WGPUCommandBufferHandle, MutExternalOrigin],
    ):
        self._wgpu.call["wgpuQueueSubmit"](queue, count, commands)

    def queue_write_buffer(
        self,
        queue: WGPUQueueHandle,
        buffer: WGPUBufferHandle,
        offset: UInt64,
        data: OpaquePtr,
        size: UInt,
    ):
        self._wgpu.call["wgpuQueueWriteBuffer"](queue, buffer, offset, data, size)

    def queue_write_texture(
        self,
        queue: WGPUQueueHandle,
        destination: OpaquePtr,
        data: OpaquePtr,
        data_size: UInt,
        data_layout: OpaquePtr,
        write_size: OpaquePtr,
    ):
        self._wgpu.call["wgpuQueueWriteTexture"](
            queue, destination, data, data_size, data_layout, write_size
        )

    def queue_release(self, queue: WGPUQueueHandle):
        self._wgpu.call["wgpuQueueRelease"](queue)

    # ------------------------------------------------------------------
    # Texture methods
    # ------------------------------------------------------------------

    def texture_create_view(
        self,
        texture: WGPUTextureHandle,
        desc: UnsafePointer[WGPUTextureViewDescriptor, MutExternalOrigin],
    ) -> WGPUTextureViewHandle:
        return self._wgpu.call["wgpuTextureCreateView", WGPUTextureViewHandle](texture, desc)

    def texture_get_width(self, texture: WGPUTextureHandle) -> UInt32:
        return self._wgpu.call["wgpuTextureGetWidth", UInt32](texture)

    def texture_get_height(self, texture: WGPUTextureHandle) -> UInt32:
        return self._wgpu.call["wgpuTextureGetHeight", UInt32](texture)

    def texture_get_depth_or_array_layers(self, texture: WGPUTextureHandle) -> UInt32:
        return self._wgpu.call["wgpuTextureGetDepthOrArrayLayers", UInt32](texture)

    def texture_get_format(self, texture: WGPUTextureHandle) -> UInt32:
        return self._wgpu.call["wgpuTextureGetFormat", UInt32](texture)

    def texture_get_usage(self, texture: WGPUTextureHandle) -> UInt64:
        return self._wgpu.call["wgpuTextureGetUsage", UInt64](texture)

    def texture_destroy(self, texture: WGPUTextureHandle):
        self._wgpu.call["wgpuTextureDestroy"](texture)

    def texture_release(self, texture: WGPUTextureHandle):
        self._wgpu.call["wgpuTextureRelease"](texture)

    def texture_view_release(self, view: WGPUTextureViewHandle):
        self._wgpu.call["wgpuTextureViewRelease"](view)

    # ------------------------------------------------------------------
    # Sampler / BindGroup / Pipeline methods
    # ------------------------------------------------------------------

    def sampler_release(self, sampler: WGPUSamplerHandle):
        self._wgpu.call["wgpuSamplerRelease"](sampler)

    def bind_group_release(self, bg: WGPUBindGroupHandle):
        self._wgpu.call["wgpuBindGroupRelease"](bg)

    def bind_group_layout_release(self, bgl: WGPUBindGroupLayoutHandle):
        self._wgpu.call["wgpuBindGroupLayoutRelease"](bgl)

    def pipeline_layout_release(self, pl: WGPUPipelineLayoutHandle):
        self._wgpu.call["wgpuPipelineLayoutRelease"](pl)

    def compute_pipeline_release(self, pipeline: WGPUComputePipelineHandle):
        self._wgpu.call["wgpuComputePipelineRelease"](pipeline)

    def render_pipeline_release(self, pipeline: WGPURenderPipelineHandle):
        self._wgpu.call["wgpuRenderPipelineRelease"](pipeline)

    def shader_module_release(self, shader: WGPUShaderModuleHandle):
        self._wgpu.call["wgpuShaderModuleRelease"](shader)

    def query_set_release(self, qs: WGPUQuerySetHandle):
        self._wgpu.call["wgpuQuerySetRelease"](qs)

    def compute_pipeline_get_bind_group_layout(
        self,
        pipeline: WGPUComputePipelineHandle,
        group_index: UInt32,
    ) -> WGPUBindGroupLayoutHandle:
        return self._wgpu.call["wgpuComputePipelineGetBindGroupLayout", WGPUBindGroupLayoutHandle](
            pipeline, group_index
        )

    def render_pipeline_get_bind_group_layout(
        self,
        pipeline: WGPURenderPipelineHandle,
        group_index: UInt32,
    ) -> WGPUBindGroupLayoutHandle:
        return self._wgpu.call["wgpuRenderPipelineGetBindGroupLayout", WGPUBindGroupLayoutHandle](
            pipeline, group_index
        )

    # ------------------------------------------------------------------
    # Surface methods
    # ------------------------------------------------------------------

    def surface_get_capabilities(
        self,
        surface: WGPUSurfaceHandle,
        adapter: WGPUAdapterHandle,
        caps: UnsafePointer[WGPUSurfaceCapabilities, MutExternalOrigin],
    ) -> UInt32:
        return self._wgpu.call["wgpuSurfaceGetCapabilities", UInt32](surface, adapter, caps)

    def surface_configure(
        self,
        surface: WGPUSurfaceHandle,
        config: UnsafePointer[WGPUSurfaceConfiguration, MutExternalOrigin],
    ):
        self._wgpu.call["wgpuSurfaceConfigure"](surface, config)

    def surface_get_current_texture(
        self,
        surface: WGPUSurfaceHandle,
        surface_texture: UnsafePointer[WGPUSurfaceTexture, MutExternalOrigin],
    ):
        self._wgpu.call["wgpuSurfaceGetCurrentTexture"](surface, surface_texture)

    def surface_present(self, surface: WGPUSurfaceHandle):
        self._wgpu.call["wgpuSurfacePresent"](surface)

    def surface_unconfigure(self, surface: WGPUSurfaceHandle):
        self._wgpu.call["wgpuSurfaceUnconfigure"](surface)

    def surface_release(self, surface: WGPUSurfaceHandle):
        self._wgpu.call["wgpuSurfaceRelease"](surface)

    # ------------------------------------------------------------------
    # wgpu-native extensions
    # ------------------------------------------------------------------

    def get_version_native(self) -> UInt32:
        return self._wgpu.call["wgpuGetVersion", UInt32]()

    def set_log_level(self, level: UInt32):
        self._wgpu.call["wgpuSetLogLevel"](level)

    def device_poll(self, device: WGPUDeviceHandle, wait: Bool) -> UInt32:
        var w: UInt32 = WGPU_TRUE if wait else WGPU_FALSE
        return self._wgpu.call["wgpuDevicePoll", UInt32](device, w, OpaquePtr())

    def enumerate_adapters(
        self,
        instance: WGPUInstanceHandle,
        options: OpaquePtr,  # nullable WGPUInstanceEnumerateAdapterOptions*
        out_adapters: UnsafePointer[WGPUAdapterHandle, MutExternalOrigin],
    ) -> UInt:
        return self._wgpu.call["wgpuInstanceEnumerateAdapters", UInt](
            instance, options, out_adapters
        )

    def supported_features_free(
        self,
        features: UnsafePointer[WGPUSupportedFeatures, MutExternalOrigin],
    ):
        self._wgpu.call["wgpuSupportedFeaturesFreeMembers"](features[])

    def surface_capabilities_free(
        self,
        caps: UnsafePointer[WGPUSurfaceCapabilities, MutExternalOrigin],
    ):
        self._wgpu.call["wgpuSurfaceCapabilitiesFreeMembers"](caps[])
