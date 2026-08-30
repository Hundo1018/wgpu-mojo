"""
Wgpu.instance — Instance wrapper (owns WGPULib + WGPUInstance).
"""

from std.memory import ArcPointer
from wgpu.adapter import Adapter
from wgpu._ffi.nulls import null_opaque, null_ptr, null_any_ptr
from wgpu._ffi.lib import WGPULib
from wgpu._ffi.types import (
    WGPUAdapterHandle, WGPUInstanceHandle, WGPUStatus,
)
from wgpu._ffi.structs import (
    WGPUInstanceDescriptor,
    WGPUInstanceLimits,
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
        desc_p.unsafe_free()
        if inst == null_opaque():
            raise Error("wgpuCreateInstance returned null")

        var lib_arc = ArcPointer(lib^)
        self._owner = ArcPointer(InstanceOwner(lib_arc, inst))

    def __init__(out self, *, deinit move: Self):
        self._owner = move._owner^

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

        var chosen = adapters[unsafe_offset=index]
        for i in range(Int(count)):
            if i != index:
                self._owner[].lib()[].adapter_release(adapters[unsafe_offset=i])
        adapters.unsafe_free()

        return Adapter(self._owner, chosen)


# ---------------------------------------------------------------------------
# Instance-global capability queries
#
# These are free functions in webgpu.h, not Instance methods: they answer what
# wgpu-native supports *before* any instance exists, so there is no handle to
# pass. They still need the shared library loaded, hence the WGPULib().
#
# Only instance_limits() is here. wgpuGetInstanceFeatures and
# wgpuHasInstanceFeature are unimplemented!() stubs in wgpu-native v29 — they
# link, but calling one aborts the process. Same for the WGSL-language-feature
# pair. See scripts/known-unimplemented.txt.
# ---------------------------------------------------------------------------


def instance_limits() raises -> WGPUInstanceLimits:
    """Instance-level limits reported by wgpu-native. No Instance required.

    Raises if wgpu-native reports anything other than `WGPUStatus.Success`.
    """
    var lib = WGPULib()
    var p = alloc[WGPUInstanceLimits](1)
    p[] = WGPUInstanceLimits(null_opaque(), UInt(0))
    var status = lib.get_instance_limits(p)
    var limits = p[]
    p.unsafe_free()
    if status != WGPUStatus.Success:
        raise Error(
            "wgpuGetInstanceLimits failed with status " + String(status)
        )
    return limits
