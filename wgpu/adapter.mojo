"""
Wgpu.adapter — Adapter wrapper for a selected WebGPU adapter.

Adapter owns an adapter handle and exposes adapter-specific operations:
device creation, adapter info queries, and surface creation.
"""

from std.memory import ArcPointer
from wgpu._ffi.lib import WGPULib
from wgpu._backend.wgpu_native.alloc_guard import raw_alloc
from wgpu._ffi.nulls import null_opaque, null_ptr, null_any_ptr
from wgpu._ffi.types import (
    WGPUAdapterHandle, WGPUDeviceHandle, WGPUInstanceHandle, WGPURequestDeviceStatus,
)
from wgpu._ffi.structs import (
    WGPUAdapterInfo, WGPUDeviceDescriptor, WGPUDeviceLostCallbackInfo,
    WGPUQueueDescriptor, WGPUStringView, WGPUUncapturedErrorCallbackInfo,
    WGPULimits, str_to_sv,
)
from wgpu.device import Device
from wgpu.instance_owner import InstanceOwner
from wgpu.surface import Surface, create_surface_wayland, create_surface_xlib


struct Adapter(Movable):
    """A selected WebGPU adapter.

    The caller must keep the originating Instance alive while this Adapter
    and its derived Device objects are in use.
    """

    var _owner: ArcPointer[InstanceOwner]
    var _lib: ArcPointer[WGPULib]
    var _inst: WGPUInstanceHandle
    var _handle: WGPUAdapterHandle
    var _info: WGPUAdapterInfo

    def __init__(
        out self,
        owner: ArcPointer[InstanceOwner],
        handle: WGPUAdapterHandle,
    ):
        self._owner = owner
        self._lib = owner[].lib()
        self._inst = owner[].handle()
        self._handle = handle
        var info_p = raw_alloc[WGPUAdapterInfo](1)
        info_p[] = WGPUAdapterInfo(
            null_opaque(),
            WGPUStringView.null_view(),
            WGPUStringView.null_view(),
            WGPUStringView.null_view(),
            WGPUStringView.null_view(),
            0, 0, 0, 0, 0, 0,
        )
        _ = self._lib[].adapter_get_info(self._handle, info_p)
        self._info = info_p[]
        info_p.unsafe_free()

    def __init__(out self, *, deinit move: Self):
        self._owner = move._owner^
        self._lib = move._lib^
        self._inst = move._inst
        self._handle = move._handle
        self._info = move._info

    def __deinit__(deinit self):
        self._lib[].adapter_release(self._handle)

    def adapter_info(self) -> WGPUAdapterInfo:
        return self._info

    def backend_type(self) -> UInt32:
        return self._info.backend_type

    def adapter_type(self) -> UInt32:
        return self._info.adapter_type

    def handle(self) -> WGPUAdapterHandle:
        return self._handle

    def request_device(
        self,
        label: String = "",
        required_features: List[UInt32] = [],
    ) raises -> Device:
        var label_sv = str_to_sv(label) if label.byte_length() > 0 else WGPUStringView.null_view()

        var lost_cb = WGPUDeviceLostCallbackInfo(
            null_opaque(),
            0,
            null_opaque(),
            null_opaque(),
            null_opaque(),
        )
        var err_cb = WGPUUncapturedErrorCallbackInfo(
            null_opaque(),
            null_opaque(),
            null_opaque(),
            null_opaque(),
        )
        var queue_desc = WGPUQueueDescriptor(
            null_opaque(),
            WGPUStringView.null_view(),
        )

        var feat_ptr = null_ptr[UInt32]()
        if len(required_features) > 0:
            feat_ptr = raw_alloc[UInt32](len(required_features))
            for i in range(len(required_features)):
                feat_ptr[unsafe_offset=i] = required_features[i]

        var desc_p = raw_alloc[WGPUDeviceDescriptor](1)
        desc_p[] = WGPUDeviceDescriptor(
            null_opaque(),
            label_sv,
            UInt(len(required_features)),
            feat_ptr,
            null_ptr[WGPULimits](),
            queue_desc,
            lost_cb,
            err_cb,
        )
        var dev_result = self._lib[].adapter_request_device_sync(
            self._inst,
            self._handle,
            desc_p,
        )
        desc_p.unsafe_free()
        if len(required_features) > 0:
            feat_ptr.unsafe_free()

        var device = dev_result.device
        var status = dev_result.status
        if status != WGPURequestDeviceStatus.Success:
            raise Error("wgpuAdapterRequestDevice failed, status=" + String(status))
        if device == null_opaque():
            raise Error("wgpuAdapterRequestDevice returned null device")

        var queue = self._lib[].device_get_queue(device)
        return Device(self._owner, self._lib, self._inst, device, queue)

    def create_surface_wayland(
        self,
        display: OpaquePointer[MutUntrackedOrigin],
        wayland_surface: OpaquePointer[MutUntrackedOrigin],
    ) raises -> Surface:
        return create_surface_wayland(self._lib, self._inst, display, wayland_surface)

    def create_surface_xlib(
        self,
        display: OpaquePointer[MutUntrackedOrigin],
        window: UInt64,
    ) raises -> Surface:
        return create_surface_xlib(self._lib, self._inst, display, window)
