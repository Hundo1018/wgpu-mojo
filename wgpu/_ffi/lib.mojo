"""
wgpu._ffi.lib — Dynamic library loader and raw function dispatcher.

Loads libwgpu_native.so and libwgpu_mojo_cb.so at runtime and exposes
every webgpu.h + wgpu.h function as a method call.
"""

from std.ffi import OwnedDLHandle
from std.sys import CompilationTarget
from wgpu._ffi.alloc_guard import AllocGuard
from wgpu._ffi.types import (
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
    WGPUSupportedWGSLLanguageFeatures,
    WGPUCompilationInfoCallbackInfo,
    WGPUPopErrorScopeCallbackInfo,
    WGPUQueueWorkDoneCallbackInfo,
    WGPUExtent3D,
    WGPUColor,
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


@fieldwise_init
struct _PopErrorResult(TrivialRegisterPassable):
    var status: UInt32
    var type: UInt32
    var message_data: OpaquePointer[MutExternalOrigin]
    var message_len: UInt


# ---------------------------------------------------------------------------
# Platform-aware library names and dev-tree fallback paths
# ---------------------------------------------------------------------------

def _wgpu_lib_name() -> String:
    """System library name (bare, for conda-installed package)."""
    comptime if CompilationTarget.is_macos():
        return "libwgpu_native.dylib"
    elif CompilationTarget.is_linux():
        return "libwgpu_native.so"
    else:  # Windows
        return "wgpu_native.dll"

def _cb_lib_name() -> String:
    """Callback bridge library name (bare, for conda-installed package)."""
    comptime if CompilationTarget.is_macos():
        return "libwgpu_mojo_cb.dylib"
    elif CompilationTarget.is_linux():
        return "libwgpu_mojo_cb.so"
    else:  # Windows
        return "wgpu_mojo_cb.dll"

def _wgpu_dev_path() -> String:
    """Dev-tree relative path (ffi/lib/, works when CWD is repo root)."""
    comptime if CompilationTarget.is_macos():
        return "ffi/lib/libwgpu_native.dylib"
    elif CompilationTarget.is_linux():
        return "ffi/lib/libwgpu_native.so"
    else:  # Windows
        return "ffi/lib/wgpu_native.dll"

def _cb_dev_path() -> String:
    """Dev-tree relative path for callback bridge."""
    comptime if CompilationTarget.is_macos():
        return "ffi/lib/libwgpu_mojo_cb.dylib"
    elif CompilationTarget.is_linux():
        return "ffi/lib/libwgpu_mojo_cb.so"
    else:  # Windows
        return "ffi/lib/wgpu_mojo_cb.dll"

comptime _WGPU_LIB_NAME = _wgpu_lib_name()
comptime _CB_LIB_NAME   = _cb_lib_name()
comptime _WGPU_LIB_PATH = _wgpu_dev_path()
comptime _CB_LIB_PATH   = _cb_dev_path()

# Expected wgpu-native ABI version (matches ffi/wgpu-native-meta/wgpu-native-git-tag)
comptime _WGPU_NATIVE_VERSION = "v29.0.0.0"


# ---------------------------------------------------------------------------
# Runtime environment helpers (no std.env module in current nightly)
# ---------------------------------------------------------------------------

def _read_env_var(name: String) raises -> String:
    """Read an environment variable via libc getenv.

    Returns an empty string when the variable is unset or empty.
    This avoids depending on std.env (not available in current Mojo nightly).
    """
    var libc = OwnedDLHandle("libc.so.6")
    var name_bytes = name.as_bytes()
    var raw = libc.call["getenv", OpaquePointer[MutExternalOrigin]](
        name_bytes.unsafe_ptr()
    )
    var null_ptr = OpaquePointer[MutExternalOrigin](unsafe_from_address=0)
    if raw == null_ptr:
        return String("")
    var p = raw.bitcast[UInt8]()
    var out = String()
    var i = 0
    while p[i] != 0:
        out += chr(Int(p[i]))
        i += 1
    return out


def _conda_lib_path(lib_name: String) raises -> String:
    """Return $CONDA_PREFIX/lib/<lib_name>, or empty string if CONDA_PREFIX is unset."""
    var prefix = _read_env_var("CONDA_PREFIX")
    if prefix == "":
        return String("")
    return prefix + "/lib/" + lib_name


def _load_lib_with_fallback(lib_name: String, dev_path: String) raises -> OwnedDLHandle:
    """Try to load a shared library from three locations in priority order:

    1. Bare name (resolved via LD_LIBRARY_PATH / DYLD_LIBRARY_PATH / PATH)
    2. $CONDA_PREFIX/lib/<lib_name>  (conda-installed package without pixi activation)
    3. ffi/lib/<lib_name>            (dev-tree, CWD must be repo root)

    Raises a descriptive Error listing all searched paths when all three fail.
    """
    # Path 1: bare name
    try:
        return OwnedDLHandle(lib_name)
    except:
        pass

    # Path 2: $CONDA_PREFIX/lib/
    var conda_path = String("")
    try:
        conda_path = _conda_lib_path(lib_name)
        if conda_path != "":
            return OwnedDLHandle(conda_path)
    except:
        pass

    # Path 3: dev-tree relative path
    try:
        return OwnedDLHandle(dev_path)
    except:
        pass

    # All three failed — build an actionable error message
    var msg = (
        "Failed to load " + lib_name + ". Searched:\n"
        + "  [1] " + lib_name + "  (via LD_LIBRARY_PATH / DYLD_LIBRARY_PATH)\n"
    )
    if conda_path != "":
        msg += "  [2] " + conda_path + "  (via $CONDA_PREFIX)\n"
    else:
        msg += "  [2] <skipped — CONDA_PREFIX is not set>\n"
    msg += (
        "  [3] " + dev_path + "  (dev-tree relative path)\n"
        + "wgpu-native expected ABI: " + _WGPU_NATIVE_VERSION + "\n"
        + "Fix: run 'pixi install' inside the wgpu-mojo repo, or ensure\n"
        + "  $CONDA_PREFIX/lib is on LD_LIBRARY_PATH before running your program."
    )
    raise Error(msg)


# ---------------------------------------------------------------------------
# WGPULib — owns two DLHandles and dispatches all WGPU function calls
# ---------------------------------------------------------------------------

struct WGPULib(Movable):
    """Loaded wgpu-native shared library + callback helpers."""

    var _wgpu: OwnedDLHandle
    var _cb:   OwnedDLHandle

    # Cached callback function pointers (void*)
    var _adapter_cb_ptr: OpaquePointer[MutExternalOrigin]
    var _device_cb_ptr: OpaquePointer[MutExternalOrigin]
    var _map_cb_ptr: OpaquePointer[MutExternalOrigin]
    var _done_cb_ptr: OpaquePointer[MutExternalOrigin]
    var _pop_error_cb_ptr: OpaquePointer[MutExternalOrigin]

    def __init__(out self) raises:
        # Three-stage fallback for each library:
        #   1. Bare name via LD_LIBRARY_PATH / DYLD_LIBRARY_PATH
        #   2. $CONDA_PREFIX/lib/<name>  (conda-installed, pixi activation not needed)
        #   3. ffi/lib/<name>            (dev-tree, CWD = repo root)
        # All three failing raises a descriptive error listing searched paths.
        self._wgpu = _load_lib_with_fallback(_WGPU_LIB_NAME, _WGPU_LIB_PATH)
        self._cb   = _load_lib_with_fallback(_CB_LIB_NAME,   _CB_LIB_PATH)
        self._adapter_cb_ptr = self._cb.call["wgpu_mojo_get_adapter_callback", OpaquePointer[MutExternalOrigin]]()
        self._device_cb_ptr  = self._cb.call["wgpu_mojo_get_device_callback",  OpaquePointer[MutExternalOrigin]]()
        self._map_cb_ptr     = self._cb.call["wgpu_mojo_get_buffer_map_callback", OpaquePointer[MutExternalOrigin]]()
        self._done_cb_ptr    = self._cb.call["wgpu_mojo_get_queue_done_callback", OpaquePointer[MutExternalOrigin]]()
        self._pop_error_cb_ptr = self._cb.call["wgpu_mojo_get_pop_error_callback", OpaquePointer[MutExternalOrigin]]()

    def __init__(out self, *, deinit take: Self):
        self._wgpu = take._wgpu^
        self._cb   = take._cb^
        self._adapter_cb_ptr = take._adapter_cb_ptr
        self._device_cb_ptr  = take._device_cb_ptr
        self._map_cb_ptr     = take._map_cb_ptr
        self._done_cb_ptr    = take._done_cb_ptr
        self._pop_error_cb_ptr = take._pop_error_cb_ptr

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
        options: OpaquePointer[MutExternalOrigin],
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
        """Synchronously request an adapter via AllowSpontaneous callback."""
        with AllocGuard[_AdapterResult](1) as result:
            result[] = _AdapterResult(WGPUAdapterHandle(unsafe_from_address=0), 0)

            with AllocGuard[WGPURequestAdapterCallbackInfo](1) as cb_info_p:
                cb_info_p[] = WGPURequestAdapterCallbackInfo(
                    OpaquePointer[MutExternalOrigin](unsafe_from_address=0),
                    WGPUCallbackMode.AllowSpontaneous,
                    self._adapter_cb_ptr,
                    result.bitcast[NoneType](),
                    OpaquePointer[MutExternalOrigin](unsafe_from_address=0),
                )
                _ = self._cb.call["wgpu_mojo_instance_request_adapter", WGPUFuture](
                    instance, options, cb_info_p
                )

            self._wgpu.call["wgpuInstanceProcessEvents"](instance)
            return _AdapterResult(result[].adapter, result[].status)

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
        """Synchronously request a device via AllowSpontaneous callback."""
        with AllocGuard[_DeviceResult](1) as result:
            result[] = _DeviceResult(WGPUDeviceHandle(unsafe_from_address=0), 0)

            with AllocGuard[WGPURequestDeviceCallbackInfo](1) as cb_info_p:
                cb_info_p[] = WGPURequestDeviceCallbackInfo(
                    OpaquePointer[MutExternalOrigin](unsafe_from_address=0),
                    WGPUCallbackMode.AllowSpontaneous,
                    self._device_cb_ptr,
                    result.bitcast[NoneType](),
                    OpaquePointer[MutExternalOrigin](unsafe_from_address=0),
                )
                _ = self._cb.call["wgpu_mojo_adapter_request_device", WGPUFuture](
                    adapter, desc, cb_info_p
                )

            self._wgpu.call["wgpuInstanceProcessEvents"](instance)
            return _DeviceResult(result[].device, result[].status)

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
        return self._wgpu.call["wgpuDevicePoll", UInt32](device, wait, OpaquePointer[MutExternalOrigin](unsafe_from_address=0))

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
        with AllocGuard[_MapResult](1) as result:
            result[] = _MapResult(0)

            with AllocGuard[WGPUBufferMapCallbackInfo](1) as cb_info_p:
                cb_info_p[] = WGPUBufferMapCallbackInfo(
                    None,
                    WGPUCallbackMode.AllowSpontaneous,
                    self._map_cb_ptr,
                    result.bitcast[NoneType](),
                    None,
                )
                _ = self._cb.call["wgpu_mojo_buffer_map_async", WGPUFuture](
                    buffer, mode, offset, size, cb_info_p
                )

            self._wgpu.call["wgpuDevicePoll"](device, WGPU_TRUE, OpaquePointer[MutExternalOrigin](unsafe_from_address=0))
            return result[].status

    def buffer_get_mapped_range(
        self,
        buffer: WGPUBufferHandle,
        offset: UInt,
        size: UInt,
    ) -> OpaquePointer[MutExternalOrigin]:
        return self._wgpu.call["wgpuBufferGetMappedRange", OpaquePointer[MutExternalOrigin]](buffer, offset, size)

    def buffer_get_const_mapped_range(
        self,
        buffer: WGPUBufferHandle,
        offset: UInt,
        size: UInt,
    ) -> OpaquePointer[MutExternalOrigin]:
        return self._wgpu.call["wgpuBufferGetConstMappedRange", OpaquePointer[MutExternalOrigin]](buffer, offset, size)

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
        data: OpaquePointer[MutExternalOrigin],
        size: UInt,
    ) -> UInt32:
        return self._wgpu.call["wgpuBufferWriteMappedRange", UInt32](
            buffer, offset, data, size
        )

    def buffer_read_mapped_range(
        self,
        buffer: WGPUBufferHandle,
        offset: UInt,
        data: OpaquePointer[MutExternalOrigin],
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
        dynamic_offsets: OpaquePointer[MutExternalOrigin],
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
        dynamic_offsets: OpaquePointer[MutExternalOrigin],
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
        color: OpaquePointer[MutExternalOrigin],
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
        data: OpaquePointer[MutExternalOrigin],
        size: UInt,
    ):
        self._wgpu.call["wgpuQueueWriteBuffer"](queue, buffer, offset, data, size)

    def queue_write_texture(
        self,
        queue: WGPUQueueHandle,
        destination: OpaquePointer[MutExternalOrigin],
        data: OpaquePointer[MutExternalOrigin],
        data_size: UInt,
        data_layout: OpaquePointer[MutExternalOrigin],
        write_size: OpaquePointer[MutExternalOrigin],
    ) :
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
        return self._wgpu.call["wgpuDevicePoll", UInt32](device, w, OpaquePointer[MutExternalOrigin](unsafe_from_address=0))

    def enumerate_adapters(
        self,
        instance: WGPUInstanceHandle,
        options: OpaquePointer[MutExternalOrigin],  # nullable WGPUInstanceEnumerateAdapterOptions*
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
        # wgpuSurfaceCapabilitiesFreeMembers takes struct by value; Mojo FFI
        # cannot safely pass non-TrivialRegisterPassable structs by value, so we
        # call a thin C wrapper that accepts a pointer and dereferences it.
        self._cb.call["wgpu_mojo_surface_capabilities_free_members"](caps)

    # ------------------------------------------------------------------
    # Missing standard WebGPU functions — Instance / global
    # ------------------------------------------------------------------

    def instance_get_wgsl_language_features(
        self,
        instance: WGPUInstanceHandle,
        features: UnsafePointer[WGPUSupportedWGSLLanguageFeatures, MutExternalOrigin],
    ):
        self._wgpu.call["wgpuInstanceGetWGSLLanguageFeatures"](instance, features)

    def instance_has_wgsl_language_feature(
        self,
        instance: WGPUInstanceHandle,
        feature: UInt32,
    ) -> UInt32:
        return self._wgpu.call["wgpuInstanceHasWGSLLanguageFeature", UInt32](instance, feature)

    # ------------------------------------------------------------------
    # Missing Device methods
    # ------------------------------------------------------------------

    def device_get_adapter_info(
        self,
        device: WGPUDeviceHandle,
        info: UnsafePointer[WGPUAdapterInfo, MutExternalOrigin],
    ) -> UInt32:
        return self._wgpu.call["wgpuDeviceGetAdapterInfo", UInt32](device, info)

    def device_get_features(
        self,
        device: WGPUDeviceHandle,
        features: UnsafePointer[WGPUSupportedFeatures, MutExternalOrigin],
    ):
        self._wgpu.call["wgpuDeviceGetFeatures"](device, features)

    def device_get_lost_future(self, device: WGPUDeviceHandle) -> WGPUFuture:
        return self._wgpu.call["wgpuDeviceGetLostFuture", WGPUFuture](device)

    def device_set_label(self, device: WGPUDeviceHandle, label: WGPUStringView):
        self._wgpu.call["wgpuDeviceSetLabel"](device, label)

    def device_pop_error_scope(
        self,
        device: WGPUDeviceHandle,
        callback_info_ptr: UnsafePointer[WGPUPopErrorScopeCallbackInfo, MutExternalOrigin],
    ):
        self._cb.call["wgpu_mojo_device_pop_error_scope"](device, callback_info_ptr)

    def device_create_render_bundle_encoder(
        self,
        device: WGPUDeviceHandle,
        desc: UnsafePointer[WGPURenderBundleEncoderDescriptor, MutExternalOrigin],
    ) -> WGPURenderBundleEncoderHandle:
        return self._wgpu.call["wgpuDeviceCreateRenderBundleEncoder", WGPURenderBundleEncoderHandle](
            device, desc
        )

    # ------------------------------------------------------------------
    # Missing Buffer methods
    # ------------------------------------------------------------------

    def buffer_set_label(self, buffer: WGPUBufferHandle, label: WGPUStringView):
        self._wgpu.call["wgpuBufferSetLabel"](buffer, label)

    # ------------------------------------------------------------------
    # Missing CommandEncoder methods
    # ------------------------------------------------------------------

    def command_encoder_copy_texture_to_texture(
        self,
        encoder: WGPUCommandEncoderHandle,
        src: UnsafePointer[WGPUTexelCopyTextureInfo, MutExternalOrigin],
        dst: UnsafePointer[WGPUTexelCopyTextureInfo, MutExternalOrigin],
        size: UnsafePointer[WGPUExtent3D, MutExternalOrigin],
    ):
        self._wgpu.call["wgpuCommandEncoderCopyTextureToTexture"](encoder, src, dst, size)

    def command_encoder_insert_debug_marker(
        self,
        encoder: WGPUCommandEncoderHandle,
        label: WGPUStringView,
    ):
        self._wgpu.call["wgpuCommandEncoderInsertDebugMarker"](encoder, label)

    def command_encoder_push_debug_group(
        self,
        encoder: WGPUCommandEncoderHandle,
        label: WGPUStringView,
    ):
        self._wgpu.call["wgpuCommandEncoderPushDebugGroup"](encoder, label)

    def command_encoder_pop_debug_group(self, encoder: WGPUCommandEncoderHandle):
        self._wgpu.call["wgpuCommandEncoderPopDebugGroup"](encoder)

    def command_encoder_write_timestamp(
        self,
        encoder: WGPUCommandEncoderHandle,
        query_set: WGPUQuerySetHandle,
        query_index: UInt32,
    ):
        self._wgpu.call["wgpuCommandEncoderWriteTimestamp"](encoder, query_set, query_index)

    def command_encoder_set_label(
        self,
        encoder: WGPUCommandEncoderHandle,
        label: WGPUStringView,
    ):
        self._wgpu.call["wgpuCommandEncoderSetLabel"](encoder, label)

    # ------------------------------------------------------------------
    # Missing ComputePassEncoder methods
    # ------------------------------------------------------------------

    def compute_pass_insert_debug_marker(
        self,
        pass_enc: WGPUComputePassEncoderHandle,
        label: WGPUStringView,
    ):
        self._wgpu.call["wgpuComputePassEncoderInsertDebugMarker"](pass_enc, label)

    def compute_pass_push_debug_group(
        self,
        pass_enc: WGPUComputePassEncoderHandle,
        label: WGPUStringView,
    ):
        self._wgpu.call["wgpuComputePassEncoderPushDebugGroup"](pass_enc, label)

    def compute_pass_pop_debug_group(self, pass_enc: WGPUComputePassEncoderHandle):
        self._wgpu.call["wgpuComputePassEncoderPopDebugGroup"](pass_enc)

    def compute_pass_set_label(
        self,
        pass_enc: WGPUComputePassEncoderHandle,
        label: WGPUStringView,
    ):
        self._wgpu.call["wgpuComputePassEncoderSetLabel"](pass_enc, label)

    # ------------------------------------------------------------------
    # Missing RenderPassEncoder methods
    # ------------------------------------------------------------------

    def render_pass_draw_indirect(
        self,
        pass_enc: WGPURenderPassEncoderHandle,
        buffer: WGPUBufferHandle,
        offset: UInt64,
    ):
        self._wgpu.call["wgpuRenderPassEncoderDrawIndirect"](pass_enc, buffer, offset)

    def render_pass_draw_indexed_indirect(
        self,
        pass_enc: WGPURenderPassEncoderHandle,
        buffer: WGPUBufferHandle,
        offset: UInt64,
    ):
        self._wgpu.call["wgpuRenderPassEncoderDrawIndexedIndirect"](pass_enc, buffer, offset)

    def render_pass_begin_occlusion_query(
        self,
        pass_enc: WGPURenderPassEncoderHandle,
        query_index: UInt32,
    ):
        self._wgpu.call["wgpuRenderPassEncoderBeginOcclusionQuery"](pass_enc, query_index)

    def render_pass_end_occlusion_query(self, pass_enc: WGPURenderPassEncoderHandle):
        self._wgpu.call["wgpuRenderPassEncoderEndOcclusionQuery"](pass_enc)

    def render_pass_execute_bundles(
        self,
        pass_enc: WGPURenderPassEncoderHandle,
        bundle_count: UInt,
        bundles: UnsafePointer[WGPURenderBundleHandle, MutExternalOrigin],
    ):
        self._wgpu.call["wgpuRenderPassEncoderExecuteBundles"](pass_enc, bundle_count, bundles)

    def render_pass_insert_debug_marker(
        self,
        pass_enc: WGPURenderPassEncoderHandle,
        label: WGPUStringView,
    ):
        self._wgpu.call["wgpuRenderPassEncoderInsertDebugMarker"](pass_enc, label)

    def render_pass_push_debug_group(
        self,
        pass_enc: WGPURenderPassEncoderHandle,
        label: WGPUStringView,
    ):
        self._wgpu.call["wgpuRenderPassEncoderPushDebugGroup"](pass_enc, label)

    def render_pass_pop_debug_group(self, pass_enc: WGPURenderPassEncoderHandle):
        self._wgpu.call["wgpuRenderPassEncoderPopDebugGroup"](pass_enc)

    def render_pass_set_label(
        self,
        pass_enc: WGPURenderPassEncoderHandle,
        label: WGPUStringView,
    ):
        self._wgpu.call["wgpuRenderPassEncoderSetLabel"](pass_enc, label)

    def render_pass_set_stencil_reference(
        self,
        pass_enc: WGPURenderPassEncoderHandle,
        reference: UInt32,
    ):
        self._wgpu.call["wgpuRenderPassEncoderSetStencilReference"](pass_enc, reference)

    # ------------------------------------------------------------------
    # Missing Queue methods
    # ------------------------------------------------------------------

    def queue_on_submitted_work_done_sync(
        self,
        instance: WGPUInstanceHandle,
        queue: WGPUQueueHandle,
    ) raises -> UInt32:
        """Block until submitted queue work is done. Returns status."""
        with AllocGuard[_WorkDoneResult](1) as result:
            result[] = _WorkDoneResult(0)
            with AllocGuard[WGPUQueueWorkDoneCallbackInfo](1) as cb_info_p:
                cb_info_p[] = WGPUQueueWorkDoneCallbackInfo(
                    OpaquePointer[MutExternalOrigin](unsafe_from_address=0),
                    WGPUCallbackMode.AllowSpontaneous,
                    self._done_cb_ptr,
                    result.bitcast[NoneType](),
                    OpaquePointer[MutExternalOrigin](unsafe_from_address=0),
                )
                _ = self._cb.call["wgpu_mojo_queue_on_submitted_work_done", WGPUFuture](queue, cb_info_p)
            self._wgpu.call["wgpuInstanceProcessEvents"](instance)
            return result[].status

    def queue_set_label(self, queue: WGPUQueueHandle, label: WGPUStringView):
        self._wgpu.call["wgpuQueueSetLabel"](queue, label)

    # ------------------------------------------------------------------
    # Missing Texture methods
    # ------------------------------------------------------------------

    def texture_get_dimension(self, texture: WGPUTextureHandle) -> UInt32:
        return self._wgpu.call["wgpuTextureGetDimension", UInt32](texture)

    def texture_get_mip_level_count(self, texture: WGPUTextureHandle) -> UInt32:
        return self._wgpu.call["wgpuTextureGetMipLevelCount", UInt32](texture)

    def texture_get_sample_count(self, texture: WGPUTextureHandle) -> UInt32:
        return self._wgpu.call["wgpuTextureGetSampleCount", UInt32](texture)

    def texture_set_label(self, texture: WGPUTextureHandle, label: WGPUStringView):
        self._wgpu.call["wgpuTextureSetLabel"](texture, label)

    def texture_add_ref(self, texture: WGPUTextureHandle):
        self._wgpu.call["wgpuTextureAddRef"](texture)

    # ------------------------------------------------------------------
    # Missing setLabel methods on remaining objects
    # ------------------------------------------------------------------

    def texture_view_set_label(self, view: WGPUTextureViewHandle, label: WGPUStringView):
        self._wgpu.call["wgpuTextureViewSetLabel"](view, label)

    def sampler_set_label(self, sampler: WGPUSamplerHandle, label: WGPUStringView):
        self._wgpu.call["wgpuSamplerSetLabel"](sampler, label)

    def shader_module_set_label(self, shader: WGPUShaderModuleHandle, label: WGPUStringView):
        self._wgpu.call["wgpuShaderModuleSetLabel"](shader, label)

    def shader_module_get_compilation_info(
        self,
        shader: WGPUShaderModuleHandle,
        callback_info_ptr: UnsafePointer[WGPUCompilationInfoCallbackInfo, MutExternalOrigin],
    ):
        self._cb.call["wgpu_mojo_shader_get_compilation_info"](shader, callback_info_ptr)

    def bind_group_set_label(self, bg: WGPUBindGroupHandle, label: WGPUStringView):
        self._wgpu.call["wgpuBindGroupSetLabel"](bg, label)

    def bind_group_layout_set_label(self, bgl: WGPUBindGroupLayoutHandle, label: WGPUStringView):
        self._wgpu.call["wgpuBindGroupLayoutSetLabel"](bgl, label)

    def pipeline_layout_set_label(self, pl: WGPUPipelineLayoutHandle, label: WGPUStringView):
        self._wgpu.call["wgpuPipelineLayoutSetLabel"](pl, label)

    def compute_pipeline_set_label(self, pipeline: WGPUComputePipelineHandle, label: WGPUStringView):
        self._wgpu.call["wgpuComputePipelineSetLabel"](pipeline, label)

    def render_pipeline_set_label(self, pipeline: WGPURenderPipelineHandle, label: WGPUStringView):
        self._wgpu.call["wgpuRenderPipelineSetLabel"](pipeline, label)

    # ------------------------------------------------------------------
    # Missing QuerySet methods
    # ------------------------------------------------------------------

    def query_set_get_count(self, qs: WGPUQuerySetHandle) -> UInt32:
        return self._wgpu.call["wgpuQuerySetGetCount", UInt32](qs)

    def query_set_get_type(self, qs: WGPUQuerySetHandle) -> UInt32:
        return self._wgpu.call["wgpuQuerySetGetType", UInt32](qs)

    def query_set_destroy(self, qs: WGPUQuerySetHandle):
        self._wgpu.call["wgpuQuerySetDestroy"](qs)

    def query_set_set_label(self, qs: WGPUQuerySetHandle, label: WGPUStringView):
        self._wgpu.call["wgpuQuerySetSetLabel"](qs, label)

    # ------------------------------------------------------------------
    # RenderBundleEncoder methods
    # ------------------------------------------------------------------

    def render_bundle_encoder_set_pipeline(
        self,
        encoder: WGPURenderBundleEncoderHandle,
        pipeline: WGPURenderPipelineHandle,
    ):
        self._wgpu.call["wgpuRenderBundleEncoderSetPipeline"](encoder, pipeline)

    def render_bundle_encoder_set_bind_group(
        self,
        encoder: WGPURenderBundleEncoderHandle,
        index: UInt32,
        bind_group: WGPUBindGroupHandle,
        dynamic_offset_count: UInt,
        dynamic_offsets: OpaquePointer[MutExternalOrigin],
    ):
        self._wgpu.call["wgpuRenderBundleEncoderSetBindGroup"](
            encoder, index, bind_group, dynamic_offset_count, dynamic_offsets
        )

    def render_bundle_encoder_set_vertex_buffer(
        self,
        encoder: WGPURenderBundleEncoderHandle,
        slot: UInt32,
        buffer: WGPUBufferHandle,
        offset: UInt64,
        size: UInt64,
    ):
        self._wgpu.call["wgpuRenderBundleEncoderSetVertexBuffer"](
            encoder, slot, buffer, offset, size
        )

    def render_bundle_encoder_set_index_buffer(
        self,
        encoder: WGPURenderBundleEncoderHandle,
        buffer: WGPUBufferHandle,
        format: UInt32,
        offset: UInt64,
        size: UInt64,
    ):
        self._wgpu.call["wgpuRenderBundleEncoderSetIndexBuffer"](
            encoder, buffer, format, offset, size
        )

    def render_bundle_encoder_draw(
        self,
        encoder: WGPURenderBundleEncoderHandle,
        vertex_count: UInt32,
        instance_count: UInt32,
        first_vertex: UInt32,
        first_instance: UInt32,
    ):
        self._wgpu.call["wgpuRenderBundleEncoderDraw"](
            encoder, vertex_count, instance_count, first_vertex, first_instance
        )

    def render_bundle_encoder_draw_indexed(
        self,
        encoder: WGPURenderBundleEncoderHandle,
        index_count: UInt32,
        instance_count: UInt32,
        first_index: UInt32,
        base_vertex: Int32,
        first_instance: UInt32,
    ):
        self._wgpu.call["wgpuRenderBundleEncoderDrawIndexed"](
            encoder, index_count, instance_count, first_index, base_vertex, first_instance
        )

    def render_bundle_encoder_draw_indirect(
        self,
        encoder: WGPURenderBundleEncoderHandle,
        buffer: WGPUBufferHandle,
        offset: UInt64,
    ):
        self._wgpu.call["wgpuRenderBundleEncoderDrawIndirect"](encoder, buffer, offset)

    def render_bundle_encoder_draw_indexed_indirect(
        self,
        encoder: WGPURenderBundleEncoderHandle,
        buffer: WGPUBufferHandle,
        offset: UInt64,
    ):
        self._wgpu.call["wgpuRenderBundleEncoderDrawIndexedIndirect"](encoder, buffer, offset)

    def render_bundle_encoder_insert_debug_marker(
        self,
        encoder: WGPURenderBundleEncoderHandle,
        label: WGPUStringView,
    ):
        self._wgpu.call["wgpuRenderBundleEncoderInsertDebugMarker"](encoder, label)

    def render_bundle_encoder_push_debug_group(
        self,
        encoder: WGPURenderBundleEncoderHandle,
        label: WGPUStringView,
    ):
        self._wgpu.call["wgpuRenderBundleEncoderPushDebugGroup"](encoder, label)

    def render_bundle_encoder_pop_debug_group(self, encoder: WGPURenderBundleEncoderHandle):
        self._wgpu.call["wgpuRenderBundleEncoderPopDebugGroup"](encoder)

    def render_bundle_encoder_set_label(
        self,
        encoder: WGPURenderBundleEncoderHandle,
        label: WGPUStringView,
    ):
        self._wgpu.call["wgpuRenderBundleEncoderSetLabel"](encoder, label)

    def render_bundle_encoder_finish(
        self,
        encoder: WGPURenderBundleEncoderHandle,
        desc: UnsafePointer[WGPURenderBundleDescriptor, MutExternalOrigin],
    ) -> WGPURenderBundleHandle:
        return self._wgpu.call["wgpuRenderBundleEncoderFinish", WGPURenderBundleHandle](
            encoder, desc
        )

    def render_bundle_encoder_release(self, encoder: WGPURenderBundleEncoderHandle):
        self._wgpu.call["wgpuRenderBundleEncoderRelease"](encoder)

    def render_bundle_set_label(self, bundle: WGPURenderBundleHandle, label: WGPUStringView):
        self._wgpu.call["wgpuRenderBundleSetLabel"](bundle, label)

    def render_bundle_release(self, bundle: WGPURenderBundleHandle):
        self._wgpu.call["wgpuRenderBundleRelease"](bundle)

    # ------------------------------------------------------------------
    # wgpu-native extension: generate report
    # ------------------------------------------------------------------

    def generate_report(
        self,
        instance: WGPUInstanceHandle,
        report: OpaquePointer[MutExternalOrigin],  # WGPUGlobalReport*
    ):
        self._wgpu.call["wgpuGenerateReport"](instance, report)

    # ------------------------------------------------------------------
    # wgpu-native extension: queue submit with index
    # ------------------------------------------------------------------

    def queue_submit_for_index(
        self,
        queue: WGPUQueueHandle,
        count: UInt,
        commands: UnsafePointer[WGPUCommandBufferHandle, MutExternalOrigin],
    ) -> UInt64:
        return self._wgpu.call["wgpuQueueSubmitForIndex", UInt64](queue, count, commands)

    # ------------------------------------------------------------------
    # wgpu-native extension: push constants
    # ------------------------------------------------------------------

    def render_pass_set_push_constants(
        self,
        pass_enc: WGPURenderPassEncoderHandle,
        stages: UInt64,   # WGPUShaderStage
        offset: UInt32,
        size_bytes: UInt32,
        data: OpaquePointer[MutExternalOrigin],
    ):
        self._wgpu.call["wgpuRenderPassEncoderSetPushConstants"](
            pass_enc, stages, offset, size_bytes, data
        )

    def compute_pass_set_push_constants(
        self,
        pass_enc: WGPUComputePassEncoderHandle,
        offset: UInt32,
        size_bytes: UInt32,
        data: OpaquePointer[MutExternalOrigin],
    ):
        self._wgpu.call["wgpuComputePassEncoderSetPushConstants"](
            pass_enc, offset, size_bytes, data
        )

    # ------------------------------------------------------------------
    # wgpu-native extension: multi-draw indirect
    # ------------------------------------------------------------------

    def render_pass_multi_draw_indirect(
        self,
        pass_enc: WGPURenderPassEncoderHandle,
        buffer: WGPUBufferHandle,
        offset: UInt64,
        count: UInt32,
    ):
        self._wgpu.call["wgpuRenderPassEncoderMultiDrawIndirect"](
            pass_enc, buffer, offset, count
        )

    def render_pass_multi_draw_indexed_indirect(
        self,
        pass_enc: WGPURenderPassEncoderHandle,
        buffer: WGPUBufferHandle,
        offset: UInt64,
        count: UInt32,
    ):
        self._wgpu.call["wgpuRenderPassEncoderMultiDrawIndexedIndirect"](
            pass_enc, buffer, offset, count
        )

    def render_pass_multi_draw_indirect_count(
        self,
        pass_enc: WGPURenderPassEncoderHandle,
        buffer: WGPUBufferHandle,
        offset: UInt64,
        count_buffer: WGPUBufferHandle,
        count_buffer_offset: UInt64,
        max_count: UInt32,
    ):
        self._wgpu.call["wgpuRenderPassEncoderMultiDrawIndirectCount"](
            pass_enc, buffer, offset, count_buffer, count_buffer_offset, max_count
        )

    def render_pass_multi_draw_indexed_indirect_count(
        self,
        pass_enc: WGPURenderPassEncoderHandle,
        buffer: WGPUBufferHandle,
        offset: UInt64,
        count_buffer: WGPUBufferHandle,
        count_buffer_offset: UInt64,
        max_count: UInt32,
    ):
        self._wgpu.call["wgpuRenderPassEncoderMultiDrawIndexedIndirectCount"](
            pass_enc, buffer, offset, count_buffer, count_buffer_offset, max_count
        )

    # ------------------------------------------------------------------
    # wgpu-native extension: pipeline statistics queries
    # ------------------------------------------------------------------

    def compute_pass_begin_pipeline_statistics_query(
        self,
        pass_enc: WGPUComputePassEncoderHandle,
        query_set: WGPUQuerySetHandle,
        query_index: UInt32,
    ):
        self._wgpu.call["wgpuComputePassEncoderBeginPipelineStatisticsQuery"](
            pass_enc, query_set, query_index
        )

    def compute_pass_end_pipeline_statistics_query(
        self,
        pass_enc: WGPUComputePassEncoderHandle,
    ):
        self._wgpu.call["wgpuComputePassEncoderEndPipelineStatisticsQuery"](pass_enc)

    def render_pass_begin_pipeline_statistics_query(
        self,
        pass_enc: WGPURenderPassEncoderHandle,
        query_set: WGPUQuerySetHandle,
        query_index: UInt32,
    ):
        self._wgpu.call["wgpuRenderPassEncoderBeginPipelineStatisticsQuery"](
            pass_enc, query_set, query_index
        )

    def render_pass_end_pipeline_statistics_query(
        self,
        pass_enc: WGPURenderPassEncoderHandle,
    ):
        self._wgpu.call["wgpuRenderPassEncoderEndPipelineStatisticsQuery"](pass_enc)

    # ------------------------------------------------------------------
    # wgpu-native extension: timestamp writes in passes
    # ------------------------------------------------------------------

    def compute_pass_write_timestamp(
        self,
        pass_enc: WGPUComputePassEncoderHandle,
        query_set: WGPUQuerySetHandle,
        query_index: UInt32,
    ):
        self._wgpu.call["wgpuComputePassEncoderWriteTimestamp"](pass_enc, query_set, query_index)

    def render_pass_write_timestamp(
        self,
        pass_enc: WGPURenderPassEncoderHandle,
        query_set: WGPUQuerySetHandle,
        query_index: UInt32,
    ):
        self._wgpu.call["wgpuRenderPassEncoderWriteTimestamp"](pass_enc, query_set, query_index)
