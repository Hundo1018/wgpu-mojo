"""
wgpu._ffi.lib — Dynamic library loader and raw function dispatcher.

Loads libwgpu_native.so and libwgpu_mojo_cb.so at runtime and exposes
every webgpu.h + wgpu.h function as a method call.
"""

from std.ffi import OwnedDLHandle
from std.sys import CompilationTarget
from wgpu._backend.wgpu_native.alloc_guard import AllocGuard
from wgpu._backend.wgpu_native.nulls import null_opaque, null_ptr, null_any_ptr
from wgpu._backend.wgpu_native.types import (
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
from wgpu._backend.wgpu_native.structs import (
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
    WGPUSupportedInstanceFeatures, WGPUInstanceLimits,
    WGPUShaderModuleDescriptorSpirV,
    WGPUCompilationInfoCallbackInfo,
    WGPUCreateComputePipelineAsyncCallbackInfo,
    WGPUCreateRenderPipelineAsyncCallbackInfo,
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
    var message_data: OpaquePointer[MutUntrackedOrigin]
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
    var raw = libc.call["getenv", OpaquePointer[MutUntrackedOrigin]](
        Pointer(name_bytes.unsafe_ptr())
    )
    var null_ptr = null_opaque()
    if raw == null_ptr:
        return String("")
    var p = Pointer(raw).unsafe_bitcast[UInt8]()
    var out = String()
    var i = 0
    while p[unsafe_offset=i] != 0:
        out += chr(Int(p[unsafe_offset=i]))
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
    var _adapter_cb_ptr: OpaquePointer[MutUntrackedOrigin]
    var _device_cb_ptr: OpaquePointer[MutUntrackedOrigin]
    var _map_cb_ptr: OpaquePointer[MutUntrackedOrigin]
    var _done_cb_ptr: OpaquePointer[MutUntrackedOrigin]
    var _pop_error_cb_ptr: OpaquePointer[MutUntrackedOrigin]

    def __init__(out self) raises:
        # Three-stage fallback for each library:
        #   1. Bare name via LD_LIBRARY_PATH / DYLD_LIBRARY_PATH
        #   2. $CONDA_PREFIX/lib/<name>  (conda-installed, pixi activation not needed)
        #   3. ffi/lib/<name>            (dev-tree, CWD = repo root)
        # All three failing raises a descriptive error listing searched paths.
        self._wgpu = _load_lib_with_fallback(_WGPU_LIB_NAME, _WGPU_LIB_PATH)
        self._cb   = _load_lib_with_fallback(_CB_LIB_NAME,   _CB_LIB_PATH)
        self._adapter_cb_ptr = self._cb.call["wgpu_mojo_get_adapter_callback", OpaquePointer[MutUntrackedOrigin]]()
        self._device_cb_ptr  = self._cb.call["wgpu_mojo_get_device_callback",  OpaquePointer[MutUntrackedOrigin]]()
        self._map_cb_ptr     = self._cb.call["wgpu_mojo_get_buffer_map_callback", OpaquePointer[MutUntrackedOrigin]]()
        self._done_cb_ptr    = self._cb.call["wgpu_mojo_get_queue_done_callback", OpaquePointer[MutUntrackedOrigin]]()
        self._pop_error_cb_ptr = self._cb.call["wgpu_mojo_get_pop_error_callback", OpaquePointer[MutUntrackedOrigin]]()

    def __init__(out self, *, deinit move: Self):
        self._wgpu = move._wgpu^
        self._cb   = move._cb^
        self._adapter_cb_ptr = move._adapter_cb_ptr
        self._device_cb_ptr  = move._device_cb_ptr
        self._map_cb_ptr     = move._map_cb_ptr
        self._done_cb_ptr    = move._done_cb_ptr
        self._pop_error_cb_ptr = move._pop_error_cb_ptr

    # ------------------------------------------------------------------
    # Symbol introspection (ABI drift detection)
    # ------------------------------------------------------------------

    def has_symbol(self, name: StringSlice) -> Bool:
        """True if `name` is exported by the loaded libwgpu_native."""
        # Symbols are resolved lazily at each call site, so naming a symbol
        # upstream has renamed still compiles and only fails once that path
        # first runs. This is the null-safe probe used to catch that early;
        # see wgpu.diagnostics and scripts/check-symbols.sh.
        return Bool(self._wgpu.get_symbol[NoneType](name))

    # ------------------------------------------------------------------
    # Global functions
    # ------------------------------------------------------------------

    def get_version(self) -> UInt32:
        return self._wgpu.call["wgpuGetVersion", UInt32]()

    def create_instance(self, desc: Pointer[WGPUInstanceDescriptor, MutUntrackedOrigin]) -> WGPUInstanceHandle:
        return self._wgpu.call["wgpuCreateInstance", WGPUInstanceHandle](desc)

    # ------------------------------------------------------------------
    # Instance methods
    # ------------------------------------------------------------------

    def instance_enumerate_adapters(
        self,
        instance: WGPUInstanceHandle,
        options: OpaquePointer[MutUntrackedOrigin],
        adapters: Pointer[WGPUAdapterHandle, MutUntrackedOrigin],
    ) -> UInt:
        return self._wgpu.call["wgpuInstanceEnumerateAdapters", UInt](
            instance, options, adapters
        )

    def instance_request_adapter_sync(
        self,
        instance: WGPUInstanceHandle,
        options: Pointer[WGPURequestAdapterOptions, MutUntrackedOrigin],
    ) raises -> _AdapterResult:
        """Synchronously request an adapter via AllowSpontaneous callback."""
        with AllocGuard[_AdapterResult](1) as result:
            result[] = _AdapterResult(null_opaque(), 0)

            with AllocGuard[WGPURequestAdapterCallbackInfo](1) as cb_info_p:
                cb_info_p[] = WGPURequestAdapterCallbackInfo(
                    null_opaque(),
                    WGPUCallbackMode.AllowSpontaneous,
                    self._adapter_cb_ptr,
                    result.unsafe_bitcast[NoneType](),
                    null_opaque(),
                )
                _ = self._cb.call["wgpu_mojo_instance_request_adapter", WGPUFuture](
                    instance, options, cb_info_p
                )

            self._wgpu.call["wgpuInstanceProcessEvents"](instance)
            return _AdapterResult(result[].adapter, result[].status)

    def instance_process_events(self, instance: WGPUInstanceHandle):
        self._wgpu.call["wgpuInstanceProcessEvents"](instance)

    def instance_create_surface(
        self,
        instance: WGPUInstanceHandle,
        desc: Pointer[WGPUSurfaceDescriptor, MutUntrackedOrigin],
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
        desc: Pointer[WGPUDeviceDescriptor, MutUntrackedOrigin],
    ) raises -> _DeviceResult:
        """Synchronously request a device via AllowSpontaneous callback."""
        with AllocGuard[_DeviceResult](1) as result:
            result[] = _DeviceResult(null_opaque(), 0)

            with AllocGuard[WGPURequestDeviceCallbackInfo](1) as cb_info_p:
                cb_info_p[] = WGPURequestDeviceCallbackInfo(
                    null_opaque(),
                    WGPUCallbackMode.AllowSpontaneous,
                    self._device_cb_ptr,
                    result.unsafe_bitcast[NoneType](),
                    null_opaque(),
                )
                _ = self._cb.call["wgpu_mojo_adapter_request_device", WGPUFuture](
                    adapter, desc, cb_info_p
                )

            self._wgpu.call["wgpuInstanceProcessEvents"](instance)
            return _DeviceResult(result[].device, result[].status)

    def adapter_get_info(
        self,
        adapter: WGPUAdapterHandle,
        info: Pointer[WGPUAdapterInfo, MutUntrackedOrigin],
    ) -> UInt32:
        return self._wgpu.call["wgpuAdapterGetInfo", UInt32](adapter, info)

    def adapter_get_limits(
        self,
        adapter: WGPUAdapterHandle,
        limits: Pointer[WGPULimits, MutUntrackedOrigin],
    ) -> UInt32:
        return self._wgpu.call["wgpuAdapterGetLimits", UInt32](adapter, limits)

    def adapter_get_features(
        self,
        adapter: WGPUAdapterHandle,
        features: Pointer[WGPUSupportedFeatures, MutUntrackedOrigin],
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
        desc: Pointer[WGPUBufferDescriptor, MutUntrackedOrigin],
    ) -> WGPUBufferHandle:
        return self._wgpu.call["wgpuDeviceCreateBuffer", WGPUBufferHandle](device, desc)

    def device_create_command_encoder(
        self,
        device: WGPUDeviceHandle,
        desc: Pointer[WGPUCommandEncoderDescriptor, MutUntrackedOrigin],
    ) -> WGPUCommandEncoderHandle:
        return self._wgpu.call["wgpuDeviceCreateCommandEncoder", WGPUCommandEncoderHandle](
            device, desc
        )

    def device_create_compute_pipeline(
        self,
        device: WGPUDeviceHandle,
        desc: Pointer[WGPUComputePipelineDescriptor, MutUntrackedOrigin],
    ) -> WGPUComputePipelineHandle:
        return self._wgpu.call["wgpuDeviceCreateComputePipeline", WGPUComputePipelineHandle](
            device, desc
        )

    def device_create_render_pipeline(
        self,
        device: WGPUDeviceHandle,
        desc: Pointer[WGPURenderPipelineDescriptor, MutUntrackedOrigin],
    ) -> WGPURenderPipelineHandle:
        return self._wgpu.call["wgpuDeviceCreateRenderPipeline", WGPURenderPipelineHandle](
            device, desc
        )

    def device_create_shader_module(
        self,
        device: WGPUDeviceHandle,
        desc: Pointer[WGPUShaderModuleDescriptor, MutUntrackedOrigin],
    ) -> WGPUShaderModuleHandle:
        return self._wgpu.call["wgpuDeviceCreateShaderModule", WGPUShaderModuleHandle](
            device, desc
        )

    def device_create_bind_group(
        self,
        device: WGPUDeviceHandle,
        desc: Pointer[WGPUBindGroupDescriptor, MutUntrackedOrigin],
    ) -> WGPUBindGroupHandle:
        return self._wgpu.call["wgpuDeviceCreateBindGroup", WGPUBindGroupHandle](device, desc)

    def device_create_bind_group_layout(
        self,
        device: WGPUDeviceHandle,
        desc: Pointer[WGPUBindGroupLayoutDescriptor, MutUntrackedOrigin],
    ) -> WGPUBindGroupLayoutHandle:
        return self._wgpu.call["wgpuDeviceCreateBindGroupLayout", WGPUBindGroupLayoutHandle](
            device, desc
        )

    def device_create_pipeline_layout(
        self,
        device: WGPUDeviceHandle,
        desc: Pointer[WGPUPipelineLayoutDescriptor, MutUntrackedOrigin],
    ) -> WGPUPipelineLayoutHandle:
        return self._wgpu.call["wgpuDeviceCreatePipelineLayout", WGPUPipelineLayoutHandle](
            device, desc
        )

    def device_create_sampler(
        self,
        device: WGPUDeviceHandle,
        desc: Pointer[WGPUSamplerDescriptor, MutUntrackedOrigin],
    ) -> WGPUSamplerHandle:
        return self._wgpu.call["wgpuDeviceCreateSampler", WGPUSamplerHandle](device, desc)

    def device_create_texture(
        self,
        device: WGPUDeviceHandle,
        desc: Pointer[WGPUTextureDescriptor, MutUntrackedOrigin],
    ) -> WGPUTextureHandle:
        return self._wgpu.call["wgpuDeviceCreateTexture", WGPUTextureHandle](device, desc)

    def device_create_query_set(
        self,
        device: WGPUDeviceHandle,
        desc: Pointer[WGPUQuerySetDescriptor, MutUntrackedOrigin],
    ) -> WGPUQuerySetHandle:
        return self._wgpu.call["wgpuDeviceCreateQuerySet", WGPUQuerySetHandle](device, desc)

    def device_get_queue(self, device: WGPUDeviceHandle) -> WGPUQueueHandle:
        return self._wgpu.call["wgpuDeviceGetQueue", WGPUQueueHandle](device)

    def device_get_limits(
        self,
        device: WGPUDeviceHandle,
        limits: Pointer[WGPULimits, MutUntrackedOrigin],
    ) -> UInt32:
        return self._wgpu.call["wgpuDeviceGetLimits", UInt32](device, limits)

    def device_has_feature(self, device: WGPUDeviceHandle, feature: UInt32) -> UInt32:
        return self._wgpu.call["wgpuDeviceHasFeature", UInt32](device, feature)

    def device_poll(self, device: WGPUDeviceHandle, wait: UInt32) -> UInt32:
        return self._wgpu.call["wgpuDevicePoll", UInt32](device, wait, null_opaque())

    def device_push_error_scope(self, device: WGPUDeviceHandle, filter: UInt32):
        self._wgpu.call["wgpuDevicePushErrorScope"](device, filter)

    def device_destroy(self, device: WGPUDeviceHandle):
        self._wgpu.call["wgpuDeviceDestroy"](device)

    def device_release(self, device: WGPUDeviceHandle):
        self._wgpu.call["wgpuDeviceRelease"](device)

    def device_add_ref(self, device: WGPUDeviceHandle):
        self._wgpu.call["wgpuDeviceAddRef"](device)

    # wgpu-native extension: RenderDoc-style frame capture. Returns WGPUBool;
    # false when no graphics debugger is attached.
    def device_start_graphics_debugger_capture(self, device: WGPUDeviceHandle) -> UInt32:
        return self._wgpu.call["wgpuDeviceStartGraphicsDebuggerCapture", UInt32](device)

    def device_stop_graphics_debugger_capture(self, device: WGPUDeviceHandle):
        self._wgpu.call["wgpuDeviceStopGraphicsDebuggerCapture"](device)

    # Metal interop. Returns NULL on non-Metal backends rather than failing, so
    # these are safe to call anywhere; they are only meaningful on macOS.
    def device_get_native_metal_device(
        self, device: WGPUDeviceHandle
    ) -> OpaquePointer[MutUntrackedOrigin]:
        return self._wgpu.call["wgpuDeviceGetNativeMetalDevice", OpaquePointer[MutUntrackedOrigin]](device)

    def queue_get_native_metal_command_queue(
        self, queue: WGPUQueueHandle
    ) -> OpaquePointer[MutUntrackedOrigin]:
        return self._wgpu.call["wgpuQueueGetNativeMetalCommandQueue", OpaquePointer[MutUntrackedOrigin]](queue)

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
                    result.unsafe_bitcast[NoneType](),
                    None,
                )
                _ = self._cb.call["wgpu_mojo_buffer_map_async", WGPUFuture](
                    buffer, mode, offset, size, cb_info_p
                )

            # Blocking poll: the WGPUBool it returns reports whether the queue
            # drained, which is not what decides the outcome here — the map
            # callback's status is. Discarded deliberately.
            _ = self._wgpu.call["wgpuDevicePoll", UInt32](device, WGPU_TRUE, null_opaque())
            return result[].status

    def buffer_get_mapped_range(
        self,
        buffer: WGPUBufferHandle,
        offset: UInt,
        size: UInt,
    ) -> OpaquePointer[MutUntrackedOrigin]:
        return self._wgpu.call["wgpuBufferGetMappedRange", OpaquePointer[MutUntrackedOrigin]](buffer, offset, size)

    def buffer_get_const_mapped_range(
        self,
        buffer: WGPUBufferHandle,
        offset: UInt,
        size: UInt,
    ) -> OpaquePointer[MutUntrackedOrigin]:
        return self._wgpu.call["wgpuBufferGetConstMappedRange", OpaquePointer[MutUntrackedOrigin]](buffer, offset, size)

    def buffer_unmap(self, buffer: WGPUBufferHandle):
        self._wgpu.call["wgpuBufferUnmap"](buffer)

    def buffer_get_size(self, buffer: WGPUBufferHandle) -> UInt64:
        return self._wgpu.call["wgpuBufferGetSize", UInt64](buffer)

    def buffer_get_usage(self, buffer: WGPUBufferHandle) -> UInt64:
        return self._wgpu.call["wgpuBufferGetUsage", UInt64](buffer)

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
        desc: Pointer[WGPUComputePassDescriptor, MutUntrackedOrigin],
    ) -> WGPUComputePassEncoderHandle:
        return self._wgpu.call["wgpuCommandEncoderBeginComputePass", WGPUComputePassEncoderHandle](
            encoder, desc
        )

    def command_encoder_begin_render_pass(
        self,
        encoder: WGPUCommandEncoderHandle,
        desc: Pointer[WGPURenderPassDescriptor, MutUntrackedOrigin],
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
        src: Pointer[WGPUTexelCopyBufferInfo, MutUntrackedOrigin],
        dst: Pointer[WGPUTexelCopyTextureInfo, MutUntrackedOrigin],
        size: Pointer[WGPUExtent3D, MutUntrackedOrigin],
    ):
        self._wgpu.call["wgpuCommandEncoderCopyBufferToTexture"](encoder, src, dst, size)

    def command_encoder_copy_texture_to_buffer(
        self,
        encoder: WGPUCommandEncoderHandle,
        src: Pointer[WGPUTexelCopyTextureInfo, MutUntrackedOrigin],
        dst: Pointer[WGPUTexelCopyBufferInfo, MutUntrackedOrigin],
        size: Pointer[WGPUExtent3D, MutUntrackedOrigin],
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
        desc: Pointer[WGPUCommandBufferDescriptor, MutUntrackedOrigin],
    ) -> WGPUCommandBufferHandle:
        return self._wgpu.call["wgpuCommandEncoderFinish", WGPUCommandBufferHandle](
            encoder, desc
        )

    def command_encoder_release(self, encoder: WGPUCommandEncoderHandle):
        self._wgpu.call["wgpuCommandEncoderRelease"](encoder)

    def command_encoder_add_ref(self, encoder: WGPUCommandEncoderHandle):
        self._wgpu.call["wgpuCommandEncoderAddRef"](encoder)

    def command_buffer_release(self, cmd_buf: WGPUCommandBufferHandle):
        self._wgpu.call["wgpuCommandBufferRelease"](cmd_buf)

    def command_buffer_add_ref(self, cmd_buf: WGPUCommandBufferHandle):
        self._wgpu.call["wgpuCommandBufferAddRef"](cmd_buf)

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
        dynamic_offsets: OpaquePointer[MutUntrackedOrigin],
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

    def compute_pass_add_ref(self, pass_enc: WGPUComputePassEncoderHandle):
        self._wgpu.call["wgpuComputePassEncoderAddRef"](pass_enc)

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
        dynamic_offsets: OpaquePointer[MutUntrackedOrigin],
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
        color: OpaquePointer[MutUntrackedOrigin],
    ):
        self._wgpu.call["wgpuRenderPassEncoderSetBlendConstant"](pass_enc, color)

    def render_pass_end(self, pass_enc: WGPURenderPassEncoderHandle):
        self._wgpu.call["wgpuRenderPassEncoderEnd"](pass_enc)

    def render_pass_release(self, pass_enc: WGPURenderPassEncoderHandle):
        self._wgpu.call["wgpuRenderPassEncoderRelease"](pass_enc)

    def render_pass_add_ref(self, pass_enc: WGPURenderPassEncoderHandle):
        self._wgpu.call["wgpuRenderPassEncoderAddRef"](pass_enc)

    # ------------------------------------------------------------------
    # Queue methods
    # ------------------------------------------------------------------

    def queue_submit(
        self,
        queue: WGPUQueueHandle,
        count: UInt,
        commands: Pointer[WGPUCommandBufferHandle, MutUntrackedOrigin],
    ):
        self._wgpu.call["wgpuQueueSubmit"](queue, count, commands)

    def queue_write_buffer(
        self,
        queue: WGPUQueueHandle,
        buffer: WGPUBufferHandle,
        offset: UInt64,
        data: OpaquePointer[MutUntrackedOrigin],
        size: UInt,
    ):
        self._wgpu.call["wgpuQueueWriteBuffer"](queue, buffer, offset, data, size)

    def queue_write_texture(
        self,
        queue: WGPUQueueHandle,
        destination: OpaquePointer[MutUntrackedOrigin],
        data: OpaquePointer[MutUntrackedOrigin],
        data_size: UInt,
        data_layout: OpaquePointer[MutUntrackedOrigin],
        write_size: OpaquePointer[MutUntrackedOrigin],
    ) :
        self._wgpu.call["wgpuQueueWriteTexture"](
            queue, destination, data, data_size, data_layout, write_size
        )

    def queue_release(self, queue: WGPUQueueHandle):
        self._wgpu.call["wgpuQueueRelease"](queue)

    def queue_add_ref(self, queue: WGPUQueueHandle):
        self._wgpu.call["wgpuQueueAddRef"](queue)

    # ------------------------------------------------------------------
    # Texture methods
    # ------------------------------------------------------------------

    def texture_create_view(
        self,
        texture: WGPUTextureHandle,
        desc: Pointer[WGPUTextureViewDescriptor, MutUntrackedOrigin],
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

    def texture_view_add_ref(self, view: WGPUTextureViewHandle):
        self._wgpu.call["wgpuTextureViewAddRef"](view)

    # ------------------------------------------------------------------
    # Sampler / BindGroup / Pipeline methods
    # ------------------------------------------------------------------

    def sampler_release(self, sampler: WGPUSamplerHandle):
        self._wgpu.call["wgpuSamplerRelease"](sampler)

    def sampler_add_ref(self, sampler: WGPUSamplerHandle):
        self._wgpu.call["wgpuSamplerAddRef"](sampler)

    def bind_group_release(self, bg: WGPUBindGroupHandle):
        self._wgpu.call["wgpuBindGroupRelease"](bg)

    def bind_group_add_ref(self, bg: WGPUBindGroupHandle):
        self._wgpu.call["wgpuBindGroupAddRef"](bg)

    def bind_group_layout_release(self, bgl: WGPUBindGroupLayoutHandle):
        self._wgpu.call["wgpuBindGroupLayoutRelease"](bgl)

    def bind_group_layout_add_ref(self, bgl: WGPUBindGroupLayoutHandle):
        self._wgpu.call["wgpuBindGroupLayoutAddRef"](bgl)

    def pipeline_layout_release(self, pl: WGPUPipelineLayoutHandle):
        self._wgpu.call["wgpuPipelineLayoutRelease"](pl)

    def pipeline_layout_add_ref(self, pl: WGPUPipelineLayoutHandle):
        self._wgpu.call["wgpuPipelineLayoutAddRef"](pl)

    def compute_pipeline_release(self, pipeline: WGPUComputePipelineHandle):
        self._wgpu.call["wgpuComputePipelineRelease"](pipeline)

    def compute_pipeline_add_ref(self, pipeline: WGPUComputePipelineHandle):
        self._wgpu.call["wgpuComputePipelineAddRef"](pipeline)

    def render_pipeline_release(self, pipeline: WGPURenderPipelineHandle):
        self._wgpu.call["wgpuRenderPipelineRelease"](pipeline)

    def render_pipeline_add_ref(self, pipeline: WGPURenderPipelineHandle):
        self._wgpu.call["wgpuRenderPipelineAddRef"](pipeline)

    def shader_module_release(self, shader: WGPUShaderModuleHandle):
        self._wgpu.call["wgpuShaderModuleRelease"](shader)

    def shader_module_add_ref(self, shader: WGPUShaderModuleHandle):
        self._wgpu.call["wgpuShaderModuleAddRef"](shader)

    def query_set_release(self, qs: WGPUQuerySetHandle):
        self._wgpu.call["wgpuQuerySetRelease"](qs)

    def query_set_add_ref(self, qs: WGPUQuerySetHandle):
        self._wgpu.call["wgpuQuerySetAddRef"](qs)

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
        caps: Pointer[WGPUSurfaceCapabilities, MutUntrackedOrigin],
    ) -> UInt32:
        return self._wgpu.call["wgpuSurfaceGetCapabilities", UInt32](surface, adapter, caps)

    def surface_configure(
        self,
        surface: WGPUSurfaceHandle,
        config: Pointer[WGPUSurfaceConfiguration, MutUntrackedOrigin],
    ):
        self._wgpu.call["wgpuSurfaceConfigure"](surface, config)

    def surface_get_current_texture(
        self,
        surface: WGPUSurfaceHandle,
        surface_texture: Pointer[WGPUSurfaceTexture, MutUntrackedOrigin],
    ):
        self._wgpu.call["wgpuSurfaceGetCurrentTexture"](surface, surface_texture)

    def surface_present(self, surface: WGPUSurfaceHandle) -> UInt32:   # WGPUStatus
        return self._wgpu.call["wgpuSurfacePresent", UInt32](surface)

    def surface_unconfigure(self, surface: WGPUSurfaceHandle):
        self._wgpu.call["wgpuSurfaceUnconfigure"](surface)

    def surface_release(self, surface: WGPUSurfaceHandle):
        self._wgpu.call["wgpuSurfaceRelease"](surface)

    def surface_add_ref(self, surface: WGPUSurfaceHandle):
        self._wgpu.call["wgpuSurfaceAddRef"](surface)

    # ------------------------------------------------------------------
    # wgpu-native extensions
    # ------------------------------------------------------------------

    def get_version_native(self) -> UInt32:
        return self._wgpu.call["wgpuGetVersion", UInt32]()

    def set_log_level(self, level: UInt32):
        self._wgpu.call["wgpuSetLogLevel"](level)

    # wgpuSetLogCallback takes a stored C function pointer, which Mojo cannot
    # produce, and wgpu-native calls it from its own threads. The C bridge owns
    # a mutex-guarded ring buffer; these drain it. See ffi/wgpu_callbacks.c.
    def log_install(self):
        self._cb.call["wgpu_mojo_log_install"]()

    def log_take(
        self,
        out_text: Pointer[UInt8, MutUntrackedOrigin],
        cap: UInt,
        out_level: Pointer[UInt32, MutUntrackedOrigin],
    ) -> Int32:
        return self._cb.call["wgpu_mojo_log_take", Int32](out_text, cap, out_level)

    def log_dropped(self) -> UInt64:
        return self._cb.call["wgpu_mojo_log_dropped", UInt64]()

    def device_poll(self, device: WGPUDeviceHandle, wait: Bool) -> UInt32:
        var w: UInt32 = WGPU_TRUE if wait else WGPU_FALSE
        return self._wgpu.call["wgpuDevicePoll", UInt32](device, w, null_opaque())

    def enumerate_adapters(
        self,
        instance: WGPUInstanceHandle,
        options: OpaquePointer[MutUntrackedOrigin],  # nullable WGPUInstanceEnumerateAdapterOptions*
        out_adapters: Pointer[WGPUAdapterHandle, MutUntrackedOrigin],
    ) -> UInt:
        return self._wgpu.call["wgpuInstanceEnumerateAdapters", UInt](
            instance, options, out_adapters
        )

    def supported_features_free(
        self,
        features: Pointer[WGPUSupportedFeatures, MutUntrackedOrigin],
    ):
        self._wgpu.call["wgpuSupportedFeaturesFreeMembers"](features[])

    def surface_capabilities_free(
        self,
        caps: Pointer[WGPUSurfaceCapabilities, MutUntrackedOrigin],
    ):
        # wgpuSurfaceCapabilitiesFreeMembers takes struct by value; Mojo FFI
        # cannot safely pass non-TrivialRegisterPassable structs by value, so we
        # call a thin C wrapper that accepts a pointer and dereferences it.
        self._cb.call["wgpu_mojo_surface_capabilities_free_members"](caps)

    # ------------------------------------------------------------------
    # Missing standard WebGPU functions — Instance / global
    # ------------------------------------------------------------------

    def get_instance_limits(
        self,
        limits: Pointer[WGPUInstanceLimits, MutUntrackedOrigin],
    ) -> UInt32:   # WGPUStatus
        return self._wgpu.call["wgpuGetInstanceLimits", UInt32](limits)

    # ------------------------------------------------------------------
    # Missing Device methods
    # ------------------------------------------------------------------

    def device_get_features(
        self,
        device: WGPUDeviceHandle,
        features: Pointer[WGPUSupportedFeatures, MutUntrackedOrigin],
    ):
        self._wgpu.call["wgpuDeviceGetFeatures"](device, features)

    def device_pop_error_scope(
        self,
        device: WGPUDeviceHandle,
        callback_info_ptr: Pointer[WGPUPopErrorScopeCallbackInfo, MutUntrackedOrigin],
    ):
        self._cb.call["wgpu_mojo_device_pop_error_scope"](device, callback_info_ptr)

    def device_create_render_bundle_encoder(
        self,
        device: WGPUDeviceHandle,
        desc: Pointer[WGPURenderBundleEncoderDescriptor, MutUntrackedOrigin],
    ) -> WGPURenderBundleEncoderHandle:
        return self._wgpu.call["wgpuDeviceCreateRenderBundleEncoder", WGPURenderBundleEncoderHandle](
            device, desc
        )

    # ------------------------------------------------------------------
    # Missing Buffer methods
    # ------------------------------------------------------------------

    # ------------------------------------------------------------------
    # Missing CommandEncoder methods
    # ------------------------------------------------------------------

    def command_encoder_copy_texture_to_texture(
        self,
        encoder: WGPUCommandEncoderHandle,
        src: Pointer[WGPUTexelCopyTextureInfo, MutUntrackedOrigin],
        dst: Pointer[WGPUTexelCopyTextureInfo, MutUntrackedOrigin],
        size: Pointer[WGPUExtent3D, MutUntrackedOrigin],
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
        bundles: Pointer[WGPURenderBundleHandle, MutUntrackedOrigin],
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
                    null_opaque(),
                    WGPUCallbackMode.AllowSpontaneous,
                    self._done_cb_ptr,
                    result.unsafe_bitcast[NoneType](),
                    null_opaque(),
                )
                _ = self._cb.call["wgpu_mojo_queue_on_submitted_work_done", WGPUFuture](queue, cb_info_p)
            self._wgpu.call["wgpuInstanceProcessEvents"](instance)
            return result[].status

    # ------------------------------------------------------------------
    # Missing Texture methods
    # ------------------------------------------------------------------

    def texture_get_dimension(self, texture: WGPUTextureHandle) -> UInt32:
        return self._wgpu.call["wgpuTextureGetDimension", UInt32](texture)

    def texture_get_mip_level_count(self, texture: WGPUTextureHandle) -> UInt32:
        return self._wgpu.call["wgpuTextureGetMipLevelCount", UInt32](texture)

    def texture_get_sample_count(self, texture: WGPUTextureHandle) -> UInt32:
        return self._wgpu.call["wgpuTextureGetSampleCount", UInt32](texture)

    def texture_add_ref(self, texture: WGPUTextureHandle):
        self._wgpu.call["wgpuTextureAddRef"](texture)

    def texture_get_native_metal_texture(
        self, texture: WGPUTextureHandle
    ) -> OpaquePointer[MutUntrackedOrigin]:
        """Underlying MTLTexture, or null on non-Metal backends."""
        return self._wgpu.call["wgpuTextureGetNativeMetalTexture", OpaquePointer[MutUntrackedOrigin]](texture)

    # ------------------------------------------------------------------
    # Missing setLabel methods on remaining objects
    # ------------------------------------------------------------------

    # ------------------------------------------------------------------
    # Missing QuerySet methods
    # ------------------------------------------------------------------

    def query_set_get_count(self, qs: WGPUQuerySetHandle) -> UInt32:
        return self._wgpu.call["wgpuQuerySetGetCount", UInt32](qs)

    def query_set_get_type(self, qs: WGPUQuerySetHandle) -> UInt32:
        return self._wgpu.call["wgpuQuerySetGetType", UInt32](qs)

    def query_set_destroy(self, qs: WGPUQuerySetHandle):
        self._wgpu.call["wgpuQuerySetDestroy"](qs)

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
        dynamic_offsets: OpaquePointer[MutUntrackedOrigin],
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

    def render_bundle_encoder_finish(
        self,
        encoder: WGPURenderBundleEncoderHandle,
        desc: Pointer[WGPURenderBundleDescriptor, MutUntrackedOrigin],
    ) -> WGPURenderBundleHandle:
        return self._wgpu.call["wgpuRenderBundleEncoderFinish", WGPURenderBundleHandle](
            encoder, desc
        )

    def render_bundle_encoder_release(self, encoder: WGPURenderBundleEncoderHandle):
        self._wgpu.call["wgpuRenderBundleEncoderRelease"](encoder)

    def render_bundle_encoder_add_ref(self, encoder: WGPURenderBundleEncoderHandle):
        self._wgpu.call["wgpuRenderBundleEncoderAddRef"](encoder)

    def render_bundle_release(self, bundle: WGPURenderBundleHandle):
        self._wgpu.call["wgpuRenderBundleRelease"](bundle)

    def render_bundle_add_ref(self, bundle: WGPURenderBundleHandle):
        self._wgpu.call["wgpuRenderBundleAddRef"](bundle)

    # ------------------------------------------------------------------
    # wgpu-native extension: timestamp period
    # ------------------------------------------------------------------

    def queue_get_timestamp_period(self, queue: WGPUQueueHandle) -> Float32:
        """Returns nanoseconds per GPU timestamp tick (TimestampQuery feature required)."""
        return self._wgpu.call["wgpuQueueGetTimestampPeriod", Float32](queue)

    # ------------------------------------------------------------------
    # wgpu-native extension: set immediates (push constants, v29 name)
    # ------------------------------------------------------------------

    def render_pass_set_immediates(
        self,
        pass_enc: WGPURenderPassEncoderHandle,
        offset: UInt32,
        size_bytes: UInt32,
        data: OpaquePointer[MutUntrackedOrigin],
    ):
        self._wgpu.call["wgpuRenderPassEncoderSetImmediates"](
            pass_enc, offset, size_bytes, data
        )

    def compute_pass_set_immediates(
        self,
        pass_enc: WGPUComputePassEncoderHandle,
        offset: UInt32,
        size_bytes: UInt32,
        data: OpaquePointer[MutUntrackedOrigin],
    ):
        self._wgpu.call["wgpuComputePassEncoderSetImmediates"](
            pass_enc, offset, size_bytes, data
        )

    def render_bundle_encoder_set_immediates(
        self,
        encoder: WGPURenderBundleEncoderHandle,
        offset: UInt32,
        size_bytes: UInt32,
        data: OpaquePointer[MutUntrackedOrigin],
    ):
        self._wgpu.call["wgpuRenderBundleEncoderSetImmediates"](
            encoder, offset, size_bytes, data
        )

    # ------------------------------------------------------------------
    # wgpu-native extension: generate report
    # ------------------------------------------------------------------

    def generate_report(
        self,
        instance: WGPUInstanceHandle,
        report: OpaquePointer[MutUntrackedOrigin],  # WGPUGlobalReport*
    ):
        self._wgpu.call["wgpuGenerateReport"](instance, report)

    # ------------------------------------------------------------------
    # wgpu-native extension: queue submit with index
    # ------------------------------------------------------------------

    def queue_submit_for_index(
        self,
        queue: WGPUQueueHandle,
        count: UInt,
        commands: Pointer[WGPUCommandBufferHandle, MutUntrackedOrigin],
    ) -> UInt64:
        return self._wgpu.call["wgpuQueueSubmitForIndex", UInt64](queue, count, commands)

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
