"""
Wgpu.diagnostics — Logging and preflight helpers for wgpu-mojo.
"""

from wgpu._ffi.lib import WGPULib
from wgpu._backend.wgpu_native.loader import _WGPU_NATIVE_VERSION
from wgpu._backend.wgpu_native.native_ext import WGPULogLevel
from wgpu._ffi.nulls import null_opaque, null_ptr, null_any_ptr
from wgpu._ffi.types import WGPUAdapterHandle, WGPUAdapterType, WGPUBackendType
from wgpu._ffi.structs import (
    WGPUAdapterInfo, WGPUInstanceDescriptor, WGPUStringView,
)


def set_log_level(level: UInt32) raises:
    """Set wgpu-native log level (0=Off, 1=Error, 2=Warn, 3=Info, 4=Debug, 5=Trace)."""
    var lib = WGPULib()
    lib.set_log_level(level)


# ----------------------------------------------------------------------
# Symbol / ABI checks
# ----------------------------------------------------------------------


def critical_symbols() -> List[String]:
    """wgpu-native symbols whose absence means the loaded library does not
    match the ABI this binding targets (see `_WGPU_NATIVE_VERSION`).

    Deliberately not exhaustive: it covers the core object-lifecycle path
    plus the entry points upstream has renamed across recent releases, which
    is where drift actually shows up. `scripts/check-symbols.sh` checks every
    symbol the binding resolves; this list is the runtime canary `preflight()`
    reports on.
    """
    return [
        # Core path: instance -> adapter -> device -> resources -> submit.
        "wgpuGetVersion",
        "wgpuCreateInstance",
        "wgpuInstanceRequestAdapter",
        "wgpuInstanceEnumerateAdapters",
        "wgpuAdapterRequestDevice",
        "wgpuAdapterGetInfo",
        "wgpuDeviceCreateBuffer",
        "wgpuDeviceCreateTexture",
        "wgpuDeviceCreateShaderModule",
        "wgpuDeviceCreateComputePipeline",
        "wgpuDeviceCreateRenderPipeline",
        "wgpuDeviceCreateCommandEncoder",
        "wgpuQueueSubmit",
        "wgpuQueueWriteBuffer",
        "wgpuBufferMapAsync",
        "wgpuQueueOnSubmittedWorkDone",
        "wgpuDevicePoll",
        "wgpuSurfaceGetCapabilities",
        "wgpuSurfaceConfigure",
        # Renamed or added by recent wgpu-native releases — drift-prone.
        # v29 renamed the push-constant entry points to *SetImmediates;
        # binding the pre-v29 *SetPushConstants names built fine and would
        # only have failed at the first call.
        "wgpuRenderPassEncoderSetImmediates",
        "wgpuComputePassEncoderSetImmediates",
        "wgpuRenderBundleEncoderSetImmediates",
        "wgpuRenderPassEncoderMultiDrawIndirect",
        "wgpuQueueGetTimestampPeriod",
        "wgpuDevicePopErrorScope",
    ]


def missing_symbols(lib: WGPULib) raises -> List[String]:
    """Return the critical symbols absent from an already-loaded library."""
    var missing = List[String]()
    for name in critical_symbols():
        if not lib.has_symbol(name):
            missing.append(name)
    return missing^


def check_symbols() raises -> List[String]:
    """Load libwgpu_native and return the critical symbols it does not export.

    An empty list means the loaded library matches the expected ABI. Raises
    only if the library cannot be loaded at all. Needs no GPU or adapter.
    """
    return missing_symbols(WGPULib())


comptime _LOG_MSG_CAP = 512


def _log_level_name(level: UInt32) -> String:
    if level == WGPULogLevel.Error: return "ERROR"
    if level == WGPULogLevel.Warn:  return "WARN"
    if level == WGPULogLevel.Info:  return "INFO"
    if level == WGPULogLevel.Debug: return "DEBUG"
    if level == WGPULogLevel.Trace: return "TRACE"
    return "LEVEL" + String(level)


def install_log_callback(level: UInt32 = WGPULogLevel.Warn) raises:
    """Route wgpu-native's log into a buffer that `drain_log()` can read.

    Without this, wgpu-native writes to stderr and Mojo never sees it, so
    validation failures surface only as raw status codes. Sets the log level
    too — the callback receives nothing at `WGPULogLevel.Off`.

    Installs a process-global callback: calling it twice just replaces it.
    """
    var lib = WGPULib()
    lib.log_install()
    lib.set_log_level(level)


def drain_log() raises -> List[String]:
    """Take all buffered log messages, oldest first, as "LEVEL: text".

    Empty if nothing was logged or `install_log_callback()` was never called.
    Draining removes the messages, so each is returned exactly once.
    """
    var lib = WGPULib()
    var out = List[String]()
    var buf = alloc[UInt8](_LOG_MSG_CAP)
    var lvl = alloc[UInt32](1)
    while True:
        lvl[] = UInt32(0)
        var n = lib.log_take(buf, UInt(_LOG_MSG_CAP), lvl)
        if n < 0:
            break
        var text = String()
        for i in range(Int(n)):
            text += chr(Int(buf[unsafe_offset=i]))
        out.append(_log_level_name(lvl[]) + ": " + text)
    buf.unsafe_free()
    lvl.unsafe_free()
    return out^


def log_dropped_count() raises -> UInt64:
    """Messages discarded because the C-side ring buffer was full."""
    return WGPULib().log_dropped()


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
    var null_ptr = null_any_ptr()
    if sv.data == null_ptr:
        return "<null>"
    var p = sv.data.unsafe_bitcast[UInt8]()
    var n = sv.length
    if n > 2048:
        n = 2048
    var out = String()
    var i = UInt(0)
    while i < n and p[unsafe_offset=Int(i)] != 0:
        out += chr(Int(p[unsafe_offset=Int(i)]))
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

    # preflight() must never raise — errors go into the returned string.
    try:
        var missing = missing_symbols(lib)
        if len(missing) > 0:
            lines += (
                "  SYMBOL CHECK FAILED: " + String(len(missing)) + " of "
                + String(len(critical_symbols()))
                + " critical symbols are missing from the loaded library.\n"
                + "  Expected wgpu-native ABI: " + _WGPU_NATIVE_VERSION + "\n"
            )
            for name in missing:
                lines += "    missing: " + name + "\n"
        else:
            lines += (
                "  symbol check: OK (" + String(len(critical_symbols()))
                + " critical symbols present)\n"
            )
    except e:
        lines += "  symbol check: FAILED to run: " + String(e) + "\n"

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
        return lines + "  ERROR: wgpuCreateInstance returned null\n"

    var count = lib.enumerate_adapters(
        inst,
        null_opaque(),
        null_ptr[WGPUAdapterHandle](),
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
        null_opaque(),
        adapters,
    )

    var info_p = alloc[WGPUAdapterInfo](1)
    for i in range(Int(count)):
        info_p[] = WGPUAdapterInfo(
            null_opaque(),
            WGPUStringView.null_view(), WGPUStringView.null_view(),
            WGPUStringView.null_view(), WGPUStringView.null_view(),
            0, 0, 0, 0, 0, 0,
        )
        _ = lib.adapter_get_info(adapters[unsafe_offset=i], info_p)
        var info = info_p[]
        lines += (
            "  adapter[" + String(i) + "]: "
            + _sv_to_str(info.device) + " | "
            + _backend_type_name(info.backend_type) + " | "
            + _adapter_type_name(info.adapter_type) + "\n"
        )
        lib.adapter_release(adapters[unsafe_offset=i])

    info_p.unsafe_free()
    adapters.unsafe_free()
    lib.instance_release(inst)
    return lines
