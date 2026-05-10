"""
Wgpu.diagnostics — Logging and preflight helpers for wgpu-mojo.
"""

from wgpu._ffi.lib import WGPULib
from wgpu._ffi.types import WGPUAdapterHandle, WGPUAdapterType, WGPUBackendType
from wgpu._ffi.structs import (
    WGPUAdapterInfo, WGPUInstanceDescriptor, WGPUStringView,
)


def set_log_level(level: UInt32) raises:
    """Set wgpu-native log level (0=Off, 1=Error, 2=Warn, 3=Info, 4=Debug, 5=Trace)."""
    var lib = WGPULib()
    lib.set_log_level(level)


def _backend_type_name(t: UInt32) -> String:
    if t == WGPUBackendType.Vulkan:   return "Vulkan"
    if t == WGPUBackendType.Metal:    return "Metal"
    if t == WGPUBackendType.D3D12:    return "D3D12"
    if t == WGPUBackendType.D3D11:    return "D3D11"
    if t == WGPUBackendType.OpenGL:   return "OpenGL"
    if t == WGPUBackendType.OpenGLES: return "OpenGLES"
    if t == WGPUBackendType.WebGPU:   return "WebGPU"
    if t == WGPUBackendType.Null:     return "Null"
    return "Unknown(" + String(t) + ")"


def _adapter_type_name(t: UInt32) -> String:
    if t == WGPUAdapterType.DiscreteGPU:   return "DiscreteGPU"
    if t == WGPUAdapterType.IntegratedGPU: return "IntegratedGPU"
    if t == WGPUAdapterType.CPU:           return "CPU"
    return "Unknown(" + String(t) + ")"


def _sv_to_str(sv: WGPUStringView) -> String:
    var null_ptr = UnsafePointer[NoneType, MutAnyOrigin](unsafe_from_address=0)
    if sv.data == null_ptr:
        return "<null>"
    var p = sv.data.bitcast[UInt8]()
    var n = sv.length
    if n > 2048:
        n = 2048
    var out = String()
    var i = UInt(0)
    while i < n and p[Int(i)] != 0:
        out += chr(Int(p[Int(i)]))
        i += 1
    return out


def preflight() -> String:
    """Run a pre-flight check and return a human-readable diagnostic string."""
    var lib: WGPULib
    try:
        lib = WGPULib()
    except e:
        return "wgpu preflight FAILED (library load error):\n" + String(e)

    var lines = String("wgpu preflight OK\n")
    lines += "  wgpu-native version: " + String(lib.get_version()) + "\n"

    var desc_p = alloc[WGPUInstanceDescriptor](1)
    desc_p[] = WGPUInstanceDescriptor(
        OpaquePointer[MutExternalOrigin](unsafe_from_address=0),
        UInt(0),
        UnsafePointer[UInt32, MutExternalOrigin](unsafe_from_address=0),
        OpaquePointer[MutExternalOrigin](unsafe_from_address=0),
    )
    var inst = lib.create_instance(desc_p)
    desc_p.free()
    if inst == OpaquePointer[MutExternalOrigin](unsafe_from_address=0):
        return lines + "  ERROR: wgpuCreateInstance returned null\n"

    var count = lib.enumerate_adapters(
        inst,
        OpaquePointer[MutExternalOrigin](unsafe_from_address=0),
        UnsafePointer[WGPUAdapterHandle, MutExternalOrigin](unsafe_from_address=0),
    )
    lines += "  adapters found: " + String(count) + "\n"

    if count == 0:
        lib.instance_release(inst)
        lines += (
            "  WARNING: No GPU adapters detected.\n"
            + "  Possible causes: missing Vulkan/Metal/D3D12 drivers, "
            + "headless environment, or VM without GPU passthrough.\n"
        )
        return lines

    var adapters = alloc[WGPUAdapterHandle](Int(count))
    _ = lib.enumerate_adapters(
        inst,
        OpaquePointer[MutExternalOrigin](unsafe_from_address=0),
        adapters,
    )

    var info_p = alloc[WGPUAdapterInfo](1)
    for i in range(Int(count)):
        info_p[] = WGPUAdapterInfo(
            OpaquePointer[MutExternalOrigin](unsafe_from_address=0),
            WGPUStringView.null_view(), WGPUStringView.null_view(),
            WGPUStringView.null_view(), WGPUStringView.null_view(),
            0, 0, 0, 0, 0, 0,
        )
        _ = lib.adapter_get_info(adapters[i], info_p)
        var info = info_p[]
        lines += (
            "  adapter[" + String(i) + "]: "
            + _sv_to_str(info.device) + " | "
            + _backend_type_name(info.backend_type) + " | "
            + _adapter_type_name(info.adapter_type) + "\n"
        )
        lib.adapter_release(adapters[i])

    info_p.free()
    adapters.free()
    lib.instance_release(inst)
    return lines
