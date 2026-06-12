"""
Wgpu.instance — Instance wrapper (owns WGPULib + WGPUInstance).
"""

from std.memory import ArcPointer
from wgpu.adapter import Adapter
from wgpu._ffi.nulls import null_opaque, null_ptr, null_any_ptr
from wgpu._ffi.lib import WGPULib
from wgpu._ffi.types import (
    WGPUAdapterHandle, WGPUInstanceHandle,
)
from wgpu._ffi.structs import (
    WGPUInstanceDescriptor,
)
from wgpu.instance_owner import InstanceOwner


struct Instance(Movable):
    """
    Owns the wgpu library handle and instance.

    Use request_adapter() to select an adapter, then call
    Adapter.request_device() to create a device.
    """

    var _owner: ArcPointer[InstanceOwner]

    def __init__(out self) raises:
        var lib = WGPULib()
        var desc_p = alloc[WGPUInstanceDescriptor](1)
        desc_p[] = WGPUInstanceDescriptor(
            null_opaque(),
            UInt(0),
            null_ptr[UInt32](),
            null_opaque(),
        )
        var inst = lib.create_instance(desc_p)
        desc_p.free()
        if inst == null_opaque():
            raise Error("wgpuCreateInstance returned null")

        var lib_arc = ArcPointer(lib^)
        self._owner = ArcPointer(InstanceOwner(lib_arc, inst))

    def __init__(out self, *, deinit take: Self):
        self._owner = take._owner^

    def lib(self) -> ArcPointer[WGPULib]:
        return self._owner[].lib()

    def handle(self) -> WGPUInstanceHandle:
        return self._owner[].handle()

    def get_version(self) -> UInt32:
        return self._owner[].lib()[].get_version()

    def request_adapter(self, index: Int = 0) raises -> Adapter:
        var count = self._owner[].lib()[].enumerate_adapters(
            self._owner[].handle(),
            null_opaque(),
            null_ptr[WGPUAdapterHandle](),
        )
        if count == 0:
            raise Error(
                "No GPU adapters found.\n"
                + "Possible causes:\n"
                + "  * No GPU hardware detected (VM, container, headless CI without GPU passthrough)\n"
                + "  * Missing Vulkan/Metal/D3D12 drivers (Linux: install mesa-vulkan-drivers or NVIDIA stack)\n"
                + "  * wgpu-native loaded but backend not available for your GPU\n"
                + "Tip: run 'pixi run example-enumerate' to list available backends, or set\n"
                + "  WGPU_BACKEND=gl for software (Mesa llvmpipe) fallback."
            )
        if index < 0 or index >= Int(count):
            raise Error("Adapter index out of range: " + String(index))

        var adapters = alloc[WGPUAdapterHandle](Int(count))
        _ = self._owner[].lib()[].enumerate_adapters(
            self._owner[].handle(),
            null_opaque(),
            adapters,
        )

        var chosen = adapters[index]
        for i in range(Int(count)):
            if i != index:
                self._owner[].lib()[].adapter_release(adapters[i])
        adapters.free()

        return Adapter(self._owner, chosen)
