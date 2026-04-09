"""
wgpu.instance — High-level Instance wrapper (owns WGPULib + WGPUInstance + WGPUAdapter).
"""

from wgpu._ffi.lib import WGPULib
from wgpu._ffi.types import (
    WGPUInstanceHandle, WGPUAdapterHandle, WGPUDeviceHandle, OpaquePtr,
    WGPURequestDeviceStatus,
)
from wgpu._ffi.structs import (
    WGPUAdapterInfo, WGPUDeviceDescriptor, WGPUDeviceLostCallbackInfo,
    WGPUUncapturedErrorCallbackInfo, WGPUQueueDescriptor, WGPUStringView,
    WGPURequestAdapterOptions, WGPULimits,
    str_to_sv,
)
from wgpu.device import Device


struct Instance(Movable):
    """
    Owns the wgpu library handle, instance, and a chosen adapter.
    The normal entry point is `wgpu.gpu.request_adapter()`.
    """

    var _lib:     WGPULib
    var _inst:    WGPUInstanceHandle
    var _adapter: WGPUAdapterHandle
    var _info:    WGPUAdapterInfo  # cached adapter info

    def __init__(
        out self,
        var lib: WGPULib,
        inst: WGPUInstanceHandle,
        adapter: WGPUAdapterHandle,
    ):
        self._lib     = lib^
        self._inst    = inst
        self._adapter = adapter
        var info_p = alloc[WGPUAdapterInfo](1)
        info_p[] = WGPUAdapterInfo(
            OpaquePtr(),
            WGPUStringView.null_view(),
            WGPUStringView.null_view(),
            WGPUStringView.null_view(),
            WGPUStringView.null_view(),
            0, 0, 0, 0, 0, 0,
        )
        _ = self._lib.adapter_get_info(
            self._adapter,
            info_p,
        )
        self._info = info_p[]
        info_p.free()

    def __del__(deinit self):
        self._lib.adapter_release(self._adapter)
        self._lib.instance_release(self._inst)

    def __init__(out self, *, deinit take: Self):
        self._lib     = take._lib^
        self._inst    = take._inst
        self._adapter = take._adapter
        self._info    = take._info

    # ------------------------------------------------------------------
    # Adapter info properties
    # ------------------------------------------------------------------

    def adapter_info(self) -> WGPUAdapterInfo:
        return self._info

    def backend_type(self) -> UInt32:
        return self._info.backend_type

    def adapter_type(self) -> UInt32:
        return self._info.adapter_type

    # ------------------------------------------------------------------
    # Device creation
    # ------------------------------------------------------------------

    def request_device(
        self,
        label: String = "",
        required_features: List[UInt32] = [],
    ) raises -> Device:
        """Synchronously create a WGPUDevice from this adapter."""
        var label_sv = str_to_sv(label) if len(label) > 0 else WGPUStringView.null_view()

        # Build descriptor
        var lost_cb = WGPUDeviceLostCallbackInfo(
            OpaquePtr(), 0, OpaquePtr(), OpaquePtr(), OpaquePtr()
        )
        var err_cb  = WGPUUncapturedErrorCallbackInfo(
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
        var dev_result = self._lib.adapter_request_device_sync(
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

        var queue = self._lib.device_get_queue(device)
        return Device(self._inst, device, queue)

    def get_version(self) -> UInt32:
        return self._lib.get_version()


# Re-export for convenience
from wgpu._ffi.structs import str_to_sv
