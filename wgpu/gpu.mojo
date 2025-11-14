"""
wgpu.gpu — Entry point and root owner of the wgpu-native library.

GPU owns WGPULib via ArcPointer (reference-counted shared ownership).
All child wrappers (Device, Buffer, ...) hold their own ArcPointer clone,
so the dynamic library stays loaded as long as any wrapper is alive.
No manual tail pins (`_ = gpu^`) needed.
"""

from std.memory import ArcPointer
from wgpu._ffi.lib import WGPULib
from wgpu._ffi.types import (
    WGPUInstanceHandle, WGPUAdapterHandle, WGPUDeviceHandle, OpaquePtr,
    WGPURequestDeviceStatus,
)
from wgpu._ffi.structs import (
    WGPUInstanceDescriptor, WGPURequestAdapterOptions,
    WGPUAdapterInfo, WGPUDeviceDescriptor, WGPUDeviceLostCallbackInfo,
    WGPUUncapturedErrorCallbackInfo, WGPUQueueDescriptor, WGPUStringView,
    WGPULimits,
    str_to_sv,
)
from wgpu._native import WGPUInstanceExtras, WGPUInstanceBackend, WGPUInstanceFlag
from wgpu.device import Device
from wgpu.surface import Surface, create_surface_wayland, create_surface_xlib


struct GPU(Movable):
    """Root owner of the wgpu-native library, instance, and adapter.

    WGPULib is held in an ArcPointer — child wrappers clone the Arc,
    so the dynamic library stays loaded until the last wrapper drops.
    """

    var _lib:     ArcPointer[WGPULib]
    var _inst:    WGPUInstanceHandle
    var _adapter: WGPUAdapterHandle
    var _info:    WGPUAdapterInfo

    def __init__(out self) raises:
        # Build everything with a local lib, then assign all fields at once.
        # (Mojo requires all fields initialized before self can be used.)
        var lib = WGPULib()

        # Create wgpu instance
        var desc_p = alloc[WGPUInstanceDescriptor](1)
        desc_p[] = WGPUInstanceDescriptor(
            OpaquePtr(),
            UInt(0),
            UnsafePointer[UInt32, MutExternalOrigin](),
            OpaquePtr(),
        )
        var inst = lib.create_instance(desc_p)
        desc_p.free()
        if not inst:
            raise Error("wgpuCreateInstance returned null")

        # Enumerate adapters synchronously — pick first
        var count = lib.enumerate_adapters(
            inst, OpaquePtr(),
            UnsafePointer[OpaquePtr, MutExternalOrigin](),
        )
        if count == 0:
            lib.instance_release(inst)
            raise Error("No GPU adapters found")

        var adapters = alloc[WGPUAdapterHandle](Int(count))
        _ = lib.enumerate_adapters(inst, OpaquePtr(), adapters)
        var adapter = adapters[0]
        adapters.free()

        # Cache adapter info
        var info_p = alloc[WGPUAdapterInfo](1)
        info_p[] = WGPUAdapterInfo(
            OpaquePtr(),
            WGPUStringView.null_view(),
            WGPUStringView.null_view(),
            WGPUStringView.null_view(),
            WGPUStringView.null_view(),
            0, 0, 0, 0, 0, 0,
        )
        _ = lib.adapter_get_info(adapter, info_p)
        var info = info_p[]
        info_p.free()

        # Now initialize all fields at once
        self._lib     = ArcPointer(lib^)
        self._inst    = inst
        self._adapter = adapter
        self._info    = info

    def __init__(out self, *, deinit take: Self):
        self._lib     = take._lib^
        self._inst    = take._inst
        self._adapter = take._adapter
        self._info    = take._info

    def __del__(deinit self):
        self._lib[].adapter_release(self._adapter)
        self._lib[].instance_release(self._inst)

    # ------------------------------------------------------------------
    # Shared library access — clone the Arc for child wrappers.
    # ------------------------------------------------------------------

    def lib(self) -> ArcPointer[WGPULib]:
        """Return a clone of the ArcPointer to WGPULib.

        Each child wrapper stores its own Arc clone, keeping the
        dynamic library loaded until the last wrapper drops.
        """
        return self._lib

    # ------------------------------------------------------------------
    # Adapter info
    # ------------------------------------------------------------------

    def adapter_info(self) -> WGPUAdapterInfo:
        return self._info

    def backend_type(self) -> UInt32:
        return self._info.backend_type

    def adapter_type(self) -> UInt32:
        return self._info.adapter_type

    def get_version(self) -> UInt32:
        return self._lib[].get_version()

    # ------------------------------------------------------------------
    # Device creation
    # ------------------------------------------------------------------

    def request_device(
        self,
        label: String = "",
        required_features: List[UInt32] = [],
    ) raises -> Device:
        """Synchronously create a Device from this adapter.

        The returned Device holds an ArcPointer clone of WGPULib,
        so the dynamic library stays loaded while Device is alive.
        """
        var label_sv = str_to_sv(label) if label.byte_length() > 0 else WGPUStringView.null_view()

        var lost_cb = WGPUDeviceLostCallbackInfo(
            OpaquePtr(), 0, OpaquePtr(), OpaquePtr(), OpaquePtr()
        )
        var err_cb = WGPUUncapturedErrorCallbackInfo(
            OpaquePtr(), OpaquePtr(), OpaquePtr(), OpaquePtr()
        )
        var queue_desc = WGPUQueueDescriptor(OpaquePtr(), WGPUStringView.null_view())

        var feat_ptr = UnsafePointer[UInt32, MutExternalOrigin]()
        if len(required_features) > 0:
            feat_ptr = alloc[UInt32](len(required_features))
            for i in range(len(required_features)):
                feat_ptr[i] = required_features[i]

        var desc_p = alloc[WGPUDeviceDescriptor](1)
        desc_p[] = WGPUDeviceDescriptor(
            OpaquePtr(),
            label_sv,
            UInt(len(required_features)),
            feat_ptr,
            UnsafePointer[WGPULimits, MutExternalOrigin](),
            queue_desc,
            lost_cb,
            err_cb,
        )
        var dev_result = self._lib[].adapter_request_device_sync(
            self._inst,
            self._adapter,
            desc_p,
        )
        desc_p.free()
        if len(required_features) > 0:
            feat_ptr.free()
        var device = dev_result.device
        var status = dev_result.status
        if status != WGPURequestDeviceStatus.Success:
            raise Error("wgpuAdapterRequestDevice failed, status=" + String(status))
        if not device:
            raise Error("wgpuAdapterRequestDevice returned null device")

        var queue = self._lib[].device_get_queue(device)
        return Device(self._lib, self._inst, device, queue)

    # ------------------------------------------------------------------
    # Raw handle accessors (for Surface creation)
    # ------------------------------------------------------------------

    def inst_handle(self) -> WGPUInstanceHandle:
        return self._inst

    def adapter_handle(self) -> WGPUAdapterHandle:
        return self._adapter

    # ------------------------------------------------------------------
    # Surface creation helpers
    # ------------------------------------------------------------------

    def create_surface_wayland(
        self,
        display: OpaquePtr,
        wayland_surface: OpaquePtr,
    ) raises -> Surface:
        """Create a Surface from a Wayland display + wl_surface pointer."""
        return create_surface_wayland(self._lib, self._inst, display, wayland_surface)

    def create_surface_xlib(
        self,
        display: OpaquePtr,
        window: UInt64,
    ) raises -> Surface:
        """Create a Surface from an X11 Display* and Window id."""
        return create_surface_xlib(self._lib, self._inst, display, window)


# Legacy request_adapter() has been removed.
# Use GPU() as the new entry point:
#
#     var gpu = GPU()
#     var device = gpu.request_device()
#


def set_log_level(level: UInt32) raises:
    """Set wgpu-native log level (0=Off, 1=Error, 2=Warn, 3=Info, 4=Debug, 5=Trace)."""
    var lib = WGPULib()
    lib.set_log_level(level)
