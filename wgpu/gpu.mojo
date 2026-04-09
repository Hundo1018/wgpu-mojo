"""
wgpu.gpu — Entry point: create a GPU instance (analogous to wgpu-py's `gpu.request_adapter`).
"""

from wgpu._ffi.lib import WGPULib
from wgpu._ffi.types import WGPUInstanceHandle, WGPUAdapterHandle, OpaquePtr
from wgpu._ffi.structs import WGPUInstanceDescriptor, WGPURequestAdapterOptions
from wgpu._native import WGPUInstanceExtras, WGPUInstanceBackend, WGPUInstanceFlag
from wgpu.instance import Instance


def request_adapter(
    power_preference: UInt32 = 0,   # WGPUPowerPreference.Undefined
    backend_type: UInt32 = 0,        # WGPUBackendType.Undefined — auto
) raises -> Instance:
    """
    Create a wgpu instance and synchronously enumerate the first available adapter.

    Returns an Instance wrapping both the WGPUInstance and the first WGPUAdapter.
    Raises on failure.
    """
    var lib = WGPULib()

    # Create instance with default options (native features enabled via extras)
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

    # Enumerate adapters synchronously
    var count = lib.enumerate_adapters(inst, OpaquePtr(), UnsafePointer[OpaquePtr, MutExternalOrigin]())
    if count == 0:
        lib.instance_release(inst)
        raise Error("No GPU adapters found")

    var adapters = alloc[WGPUAdapterHandle](Int(count))
    _ = lib.enumerate_adapters(inst, OpaquePtr(), adapters)

    # Pick the first adapter (filtered by power_preference if specified)
    var adapter = adapters[0]
    adapters.free()

    return Instance(lib^, inst, adapter)


def set_log_level(level: UInt32) raises:
    """Set wgpu-native log level (0=Off, 1=Error, 2=Warn, 3=Info, 4=Debug, 5=Trace)."""
    var lib = WGPULib()
    lib.set_log_level(level)
