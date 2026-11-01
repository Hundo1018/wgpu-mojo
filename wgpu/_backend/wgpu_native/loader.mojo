"""
wgpu._ffi.lib — Dynamic library loader and raw function dispatcher.

Loads libwgpu_native.so (and libwgpu_mojo_cb.so, the C log bridge) at
runtime and exposes every webgpu.h + wgpu.h function as a method call. The
async completion callbacks are Mojo: see callbacks.mojo.

Link mode is chosen at compile time with `-D WGPU_LINK=dynamic|static`:

- `dynamic` (default): both libraries are dlopen'ed when `WGPULib()` is built.
- `static`: every call is an `external_call`, so the IR holds a plain `declare`
  per symbol the program actually uses and nothing calls dlopen. The program
  must link libwgpu_native (and, if it uses the log bridge,
  ffi/lib/libwgpu_mojo_cb.a) at build time. In a wasm build those declares
  become module imports. See scripts/test-static.sh for the native link line.
"""

from std.ffi import OwnedDLHandle, external_call
from std.sys.defines import get_defined_string
from std.os import getenv
from std.sys import CompilationTarget
from wgpu._backend.wgpu_native.alloc_guard import AllocGuard, raw_alloc
from wgpu._backend.wgpu_native.target import (
    _WGPU_LINK, _WGPU_TARGET, WGPU_LINK_STATIC, WGPU_TARGET_WEB, native_only,
)
from wgpu._backend.wgpu_native.callbacks import (
    CallbackResult, _AdapterResult, _DeviceResult, _MapResult, _WorkDoneResult, _PopErrorResult,
    request_adapter_callback, request_device_callback, buffer_map_callback,
    queue_work_done_callback, pop_error_scope_callback, sv_arg,
)
from wgpu._backend.wgpu_native.native_ext import WGPUImageSubresourceRange
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
comptime _WGPU_NATIVE_VERSION = "v29.0.1.1"


def _conda_lib_path(lib_name: String) raises -> String:
    """Return $CONDA_PREFIX/lib/<lib_name>, or empty string if CONDA_PREFIX is unset."""
    var prefix = getenv("CONDA_PREFIX")
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


trait _LibBackend(Movable, Deinitable):
    """One C library, reached either through dlopen or through the linker.

    `call` has the same shape as `OwnedDLHandle.call`, so call sites read the
    same in both modes.
    """

    def __init__(out self, lib_name: String, dev_path: String) raises: ...

    def call[
        name: StaticString, R: RegisterPassable = NoneType, *T: AnyType
    ](self, *args: *T) -> R: ...

    def has(self, name: StringSlice) -> Bool: ...


struct _DynamicLib(_LibBackend):
    var _h: OwnedDLHandle

    def __init__(out self, lib_name: String, dev_path: String) raises:
        self._h = _load_lib_with_fallback(lib_name, dev_path)

    @always_inline
    def call[
        name: StaticString, R: RegisterPassable = NoneType, *T: AnyType
    ](self, *args: *T) -> R:
        return self._h.call[name, R](args)

    def has(self, name: StringSlice) -> Bool:
        return Bool(self._h.get_symbol[NoneType](name))


struct _StaticLib(_LibBackend):
    """No handle at all, so dlopen/dlsym/dlclose never reach the IR.

    (An `Optional[OwnedDLHandle]` left at None still emits dlclose in its
    destructor; the type itself has to be absent.)
    """

    def __init__(out self, lib_name: String, dev_path: String) raises:
        pass

    @always_inline
    def call[
        name: StaticString, R: RegisterPassable = NoneType, *T: AnyType
    ](self, *args: *T) -> R:
        comptime assert not (WGPU_TARGET_WEB and native_only(name)), (
            name + " is a wgpu-native extension; the web target has only webgpu.h"
        )
        # `*args`, not `args`: the bare pack would be passed as one pointer.
        return external_call[name, R](*args)

    def has(self, name: StringSlice) -> Bool:
        # Every symbol the program calls was resolved by the linker; a runtime
        # lookup by name has nothing to look in.
        return True


# A comptime type choice needs the trait bound; untyped, the alias has no members.
comptime _Lib: _LibBackend = _StaticLib if WGPU_LINK_STATIC else _DynamicLib


# ---------------------------------------------------------------------------
# WGPULib — owns two DLHandles and dispatches all WGPU function calls
# ---------------------------------------------------------------------------

struct WGPULib(Movable):
    """Loaded wgpu-native shared library + callback helpers."""

    var _wgpu: _Lib
    var _cb:   _Lib


    def __init__(out self) raises:
        # Three-stage fallback for each library:
        #   1. Bare name via LD_LIBRARY_PATH / DYLD_LIBRARY_PATH
        #   2. $CONDA_PREFIX/lib/<name>  (conda-installed, pixi activation not needed)
        #   3. ffi/lib/<name>            (dev-tree, CWD = repo root)
        # All three failing raises a descriptive error listing searched paths.
        comptime assert _WGPU_LINK == "dynamic" or _WGPU_LINK == "static", (
            "-D WGPU_LINK must be `dynamic` or `static`"
        )
        comptime assert _WGPU_TARGET == "native" or _WGPU_TARGET == "web", (
            "-D WGPU_TARGET must be `native` or `web`"
        )
        # With -D WGPU_LINK=static nothing is loaded; see _StaticLib.
        self._wgpu = _Lib(_WGPU_LIB_NAME, _WGPU_LIB_PATH)
        self._cb   = _Lib(_CB_LIB_NAME,   _CB_LIB_PATH)

    def __init__(out self, *, deinit move: Self):
        self._wgpu = move._wgpu^
        self._cb   = move._cb^

    # ------------------------------------------------------------------
    # Symbol introspection (ABI drift detection)
    # ------------------------------------------------------------------

    def has_symbol(self, name: StringSlice) -> Bool:
        """True if `name` is exported by the loaded libwgpu_native."""
        # Symbols are resolved lazily at each call site, so naming a symbol
        # upstream has renamed still compiles and only fails once that path
        # first runs. This is the null-safe probe used to catch that early;
        # see wgpu.diagnostics and scripts/check-symbols.sh. Always True in
        # static mode, where the linker has already done this check.
        return self._wgpu.has(name)

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

    # ------------------------------------------------------------------
    # Non-blocking requests
    #
    # Each *_start fires a request and returns the heap slot its callback
    # writes into (status 0 until then). The slot must stay allocated until
    # done() — the callback writes into it whenever it fires — so whoever holds
    # it frees it only after that. `pump` lets callbacks run without blocking;
    # `wait_for` blocks (native only: a browser's main thread cannot block,
    # and its callbacks only run once control returns to the event loop).
    # ------------------------------------------------------------------

    def pump(self, instance: WGPUInstanceHandle, device: WGPUDeviceHandle, wait: Bool):
        """Give pending callbacks a chance to run. `device` may be null."""
        comptime if not WGPU_TARGET_WEB:
            if Int(device) != 0:
                # The WGPUBool says whether the queue drained, which is not what
                # decides any request's outcome; its callback status is.
                _ = self._wgpu.call["wgpuDevicePoll", UInt32](
                    device, WGPU_TRUE if wait else WGPU_FALSE, null_opaque()
                )
        self._wgpu.call["wgpuInstanceProcessEvents"](instance)

    def wait_for[R: CallbackResult](
        self,
        slot: Pointer[R, MutUntrackedOrigin],
        instance: WGPUInstanceHandle,
        device: WGPUDeviceHandle,
    ) raises:
        """Block until the request behind `slot` completes."""
        comptime assert not WGPU_TARGET_WEB, (
            "blocking waits are native-only; on the web poll the request's ready() each frame"
        )
        # A blocking poll returns once the queue is idle, by which point the
        # callback has fired; the bound only turns a lost callback into an error.
        for _ in range(10_000):
            if slot[].done():
                return
            self.pump(instance, device, True)
        raise Error("wgpu request never completed (callback did not fire)")

    def instance_request_adapter_start(
        self,
        instance: WGPUInstanceHandle,
        options: Pointer[WGPURequestAdapterOptions, MutUntrackedOrigin],
    ) -> Pointer[_AdapterResult, MutUntrackedOrigin]:
        var slot = raw_alloc[_AdapterResult](1)
        slot[] = _AdapterResult.pending()
        var cb_info = WGPURequestAdapterCallbackInfo(
            null_opaque(),
            WGPUCallbackMode.AllowSpontaneous,
            request_adapter_callback(),
            slot.unsafe_bitcast[NoneType](),
            null_opaque(),
        )
        _ = self._wgpu.call["wgpuInstanceRequestAdapter", WGPUFuture](
            instance, options, cb_info
        )
        return slot

    def instance_request_adapter_sync(
        self,
        instance: WGPUInstanceHandle,
        options: Pointer[WGPURequestAdapterOptions, MutUntrackedOrigin],
    ) raises -> _AdapterResult:
        """Request an adapter and block until it arrives."""
        var slot = self.instance_request_adapter_start(instance, options)
        self.wait_for(slot, instance, null_opaque())
        var r = slot[]
        slot.unsafe_free()
        return r

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
        """Request a device and block until it arrives."""
        var slot = self.adapter_request_device_start(adapter, desc)
        self.wait_for(slot, instance, null_opaque())
        var r = slot[]
        slot.unsafe_free()
        return r

    def adapter_request_device_start(
        self,
        adapter: WGPUAdapterHandle,
        desc: Pointer[WGPUDeviceDescriptor, MutUntrackedOrigin],
    ) -> Pointer[_DeviceResult, MutUntrackedOrigin]:
        var slot = raw_alloc[_DeviceResult](1)
        slot[] = _DeviceResult.pending()
        var cb_info = WGPURequestDeviceCallbackInfo(
            null_opaque(),
            WGPUCallbackMode.AllowSpontaneous,
            request_device_callback(),
            slot.unsafe_bitcast[NoneType](),
            null_opaque(),
        )
        _ = self._wgpu.call["wgpuAdapterRequestDevice", WGPUFuture](
            adapter, desc, cb_info
        )
        return slot

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

    def device_create_shader_module_trusted(
        self,
        device: WGPUDeviceHandle,
        desc: Pointer[WGPUShaderModuleDescriptor, MutUntrackedOrigin],
        runtime_checks: UInt64,  # WGPUShaderRuntimeChecks
    ) -> WGPUShaderModuleHandle:
        """Create a shader module with chosen runtime checks (wgpu-native v29.0.1.1+)."""
        return self._wgpu.call["wgpuDeviceCreateShaderModuleTrusted", WGPUShaderModuleHandle](
            device, desc, runtime_checks
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
        var slot = self.buffer_map_start(buffer, mode, offset, size)
        self.wait_for(slot, instance, device)
        var status = slot[].status
        slot.unsafe_free()
        return status

    def buffer_map_start(
        self,
        buffer: WGPUBufferHandle,
        mode: UInt64,
        offset: UInt,
        size: UInt,
    ) -> Pointer[_MapResult, MutUntrackedOrigin]:
        var slot = raw_alloc[_MapResult](1)
        slot[] = _MapResult.pending()
        var cb_info = WGPUBufferMapCallbackInfo(
            null_opaque(),
            WGPUCallbackMode.AllowSpontaneous,
            buffer_map_callback(),
            slot.unsafe_bitcast[NoneType](),
            null_opaque(),
        )
        _ = self._wgpu.call["wgpuBufferMapAsync", WGPUFuture](
            buffer, mode, offset, size, cb_info
        )
        return slot

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

    def command_encoder_clear_texture(
        self,
        encoder: WGPUCommandEncoderHandle,
        texture: WGPUTextureHandle,
        subresource_range: Pointer[WGPUImageSubresourceRange, MutUntrackedOrigin],
    ):
        """Clear a texture range (wgpu-native v29.0.1.1+; needs the ClearTexture feature)."""
        self._wgpu.call["wgpuCommandEncoderClearTexture"](encoder, texture, subresource_range)

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
        self._wgpu.call["wgpuSurfaceCapabilitiesFreeMembers"](caps[])

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
        callback_info: WGPUPopErrorScopeCallbackInfo,
    ):
        _ = self._wgpu.call["wgpuDevicePopErrorScope", WGPUFuture](device, callback_info)

    def device_pop_error_scope_start(
        self, device: WGPUDeviceHandle
    ) -> Pointer[_PopErrorResult, MutUntrackedOrigin]:
        var slot = raw_alloc[_PopErrorResult](1)
        slot[] = _PopErrorResult.pending()
        self.device_pop_error_scope(
            device,
            WGPUPopErrorScopeCallbackInfo(
                null_opaque(),
                WGPUCallbackMode.AllowSpontaneous,
                pop_error_scope_callback(),
                slot.unsafe_bitcast[NoneType](),
                null_opaque(),
            ),
        )
        return slot

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
        self._wgpu.call["wgpuCommandEncoderInsertDebugMarker"](encoder, sv_arg(label))

    def command_encoder_push_debug_group(
        self,
        encoder: WGPUCommandEncoderHandle,
        label: WGPUStringView,
    ):
        self._wgpu.call["wgpuCommandEncoderPushDebugGroup"](encoder, sv_arg(label))

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
        self._wgpu.call["wgpuComputePassEncoderInsertDebugMarker"](pass_enc, sv_arg(label))

    def compute_pass_push_debug_group(
        self,
        pass_enc: WGPUComputePassEncoderHandle,
        label: WGPUStringView,
    ):
        self._wgpu.call["wgpuComputePassEncoderPushDebugGroup"](pass_enc, sv_arg(label))

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
        self._wgpu.call["wgpuRenderPassEncoderInsertDebugMarker"](pass_enc, sv_arg(label))

    def render_pass_push_debug_group(
        self,
        pass_enc: WGPURenderPassEncoderHandle,
        label: WGPUStringView,
    ):
        self._wgpu.call["wgpuRenderPassEncoderPushDebugGroup"](pass_enc, sv_arg(label))

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
        device: WGPUDeviceHandle,
        queue: WGPUQueueHandle,
    ) raises -> UInt32:
        """Block until submitted queue work is done. Returns status.

        The slot is freed only once the callback has fired: freeing it after a
        non-blocking pump (what this once did) let the callback write into
        freed memory.
        """
        var slot = self.queue_on_submitted_work_done_start(queue)
        self.wait_for(slot, instance, device)
        var status = slot[].status
        slot.unsafe_free()
        return status

    def queue_on_submitted_work_done_start(
        self, queue: WGPUQueueHandle
    ) -> Pointer[_WorkDoneResult, MutUntrackedOrigin]:
        var slot = raw_alloc[_WorkDoneResult](1)
        slot[] = _WorkDoneResult.pending()
        var cb_info = WGPUQueueWorkDoneCallbackInfo(
            null_opaque(),
            WGPUCallbackMode.AllowSpontaneous,
            queue_work_done_callback(),
            slot.unsafe_bitcast[NoneType](),
            null_opaque(),
        )
        _ = self._wgpu.call["wgpuQueueOnSubmittedWorkDone", WGPUFuture](queue, cb_info)
        return slot

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
        self._wgpu.call["wgpuRenderBundleEncoderInsertDebugMarker"](encoder, sv_arg(label))

    def render_bundle_encoder_push_debug_group(
        self,
        encoder: WGPURenderBundleEncoderHandle,
        label: WGPUStringView,
    ):
        self._wgpu.call["wgpuRenderBundleEncoderPushDebugGroup"](encoder, sv_arg(label))

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
        data: OpaquePointer[MutUntrackedOrigin],
        size: UInt,
    ):
        # webgpu.h order: (encoder, offset, data, size). v29.0.0.0's wgpu.h had
        # (encoder, offset, sizeBytes, data); v29.0.1.1 moved the function into
        # webgpu.h and swapped the last two.
        self._wgpu.call["wgpuRenderPassEncoderSetImmediates"](
            pass_enc, offset, data, size
        )

    def compute_pass_set_immediates(
        self,
        pass_enc: WGPUComputePassEncoderHandle,
        offset: UInt32,
        data: OpaquePointer[MutUntrackedOrigin],
        size: UInt,
    ):
        # webgpu.h order: (encoder, offset, data, size). v29.0.0.0's wgpu.h had
        # (encoder, offset, sizeBytes, data); v29.0.1.1 moved the function into
        # webgpu.h and swapped the last two.
        self._wgpu.call["wgpuComputePassEncoderSetImmediates"](
            pass_enc, offset, data, size
        )

    def render_bundle_encoder_set_immediates(
        self,
        encoder: WGPURenderBundleEncoderHandle,
        offset: UInt32,
        data: OpaquePointer[MutUntrackedOrigin],
        size: UInt,
    ):
        # webgpu.h order: (encoder, offset, data, size). v29.0.0.0's wgpu.h had
        # (encoder, offset, sizeBytes, data); v29.0.1.1 moved the function into
        # webgpu.h and swapped the last two.
        self._wgpu.call["wgpuRenderBundleEncoderSetImmediates"](
            encoder, offset, data, size
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
