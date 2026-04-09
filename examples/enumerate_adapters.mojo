"""
examples/enumerate_adapters.mojo — List all available GPU adapters synchronously.

Run from project root:
    pixi run example-enumerate
"""

from wgpu._ffi.lib import WGPULib
from wgpu._ffi.types import OpaquePtr, WGPUAdapterType, WGPUBackendType
from wgpu._ffi.structs import WGPUInstanceDescriptor, WGPUAdapterInfo


def backend_name(t: UInt32) -> String:
    if t == WGPUBackendType.Vulkan:    return "Vulkan"
    if t == WGPUBackendType.Metal:     return "Metal"
    if t == WGPUBackendType.D3D12:     return "D3D12"
    if t == WGPUBackendType.D3D11:     return "D3D11"
    if t == WGPUBackendType.OpenGL:    return "OpenGL"
    if t == WGPUBackendType.OpenGLES:  return "OpenGLES"
    if t == WGPUBackendType.Null:      return "Null"
    return "Unknown"


def adapter_type_name(t: UInt32) -> String:
    if t == WGPUAdapterType.DiscreteGPU:   return "DiscreteGPU"
    if t == WGPUAdapterType.IntegratedGPU: return "IntegratedGPU"
    if t == WGPUAdapterType.CPU:           return "CPU"
    return "Unknown"


def print_sv(label: String, sv: WGPUStringView):
    """Print a WGPUStringView field safely."""
    if Bool(sv.data):
        # Reinterpret as char pointer and read bytes
        var cstr = sv.data.bitcast[UInt8]()
        var i = UInt(0)
        var result = String()
        while i < sv.length and cstr[Int(i)] != 0:
            result += chr(Int(cstr[Int(i)]))
            i += 1
        print(label + ": " + result)
    else:
        print(label + ": <null>")


def main() raises:
    print("=== wgpu-mojo: Enumerate Adapters ===")

    var lib  = WGPULib()
    print("wgpu-native version:", lib.get_version())

    # Create instance
    var desc_p = alloc[WGPUInstanceDescriptor](1)
    desc_p[] = WGPUInstanceDescriptor(
        OpaquePtr(), UInt(0),
        UnsafePointer[UInt32, MutExternalOrigin](),
        UnsafePointer[NoneType, MutExternalOrigin](),
    )
    var inst = lib.create_instance(desc_p)
    desc_p.free()
    if not inst:
        print("ERROR: wgpuCreateInstance returned null")
        return

    # Count adapters
    var count = lib.enumerate_adapters(
        inst, OpaquePtr(),
        UnsafePointer[OpaquePtr, MutExternalOrigin]()
    )
    print("Adapters found:", count)

    if count == 0:
        print("No GPU adapters available.")
        lib.instance_release(inst)
        return

    # Fill adapter list
    var adapters = alloc[OpaquePtr](count)
    _ = lib.enumerate_adapters(inst, OpaquePtr(), adapters)

    for i in range(count):
        var adapter = adapters[i]
        var info_p = alloc[WGPUAdapterInfo](1)
        info_p[] = WGPUAdapterInfo(
            OpaquePtr(),
            WGPUStringView.null_view(), WGPUStringView.null_view(),
            WGPUStringView.null_view(), WGPUStringView.null_view(),
            0, 0, 0, 0, 0, 0,
        )
        _ = lib.adapter_get_info(adapter, info_p)
        var info = info_p[]
        info_p.free()

        print("\n--- Adapter", i, "---")
        print_sv("  vendor      ", info.vendor)
        print_sv("  device      ", info.device)
        print_sv("  description ", info.description)
        print("  backend_type:", backend_name(info.backend_type))
        print("  adapter_type:", adapter_type_name(info.adapter_type))
        print("  vendor_id:   ", info.vendor_id)
        print("  device_id:   ", info.device_id)

        lib.adapter_release(adapter)

    adapters.free()
    lib.instance_release(inst)
    print("\nDone.")
