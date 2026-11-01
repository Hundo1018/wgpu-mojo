"""wgpu._backend.wgpu_native.target — compile-time build target.

`-D WGPU_LINK=static` resolves every wgpu call at link time (#13).
`-D WGPU_TARGET=web` builds for the browser (#14): wasm64 + emdawnwebgpu. It
implies static linking, and only standard `webgpu.h` is available, so a call to
a wgpu-native extension fails to compile instead of trapping in the browser.
"""

from std.sys.defines import get_defined_string

comptime _WGPU_LINK = get_defined_string["WGPU_LINK", "dynamic"]()
comptime _WGPU_TARGET = get_defined_string["WGPU_TARGET", "native"]()

comptime WGPU_TARGET_WEB = _WGPU_TARGET == "web"
"""True when built with `-D WGPU_TARGET=web`."""

comptime WGPU_LINK_STATIC = _WGPU_LINK == "static" or WGPU_TARGET_WEB
"""True when symbols are resolved at link time: `-D WGPU_LINK=static`, or the web target."""


# Functions bound in loader.mojo that the browser does not have: everything
# declared in ffi/include/webgpu/wgpu.h, plus the `*SetImmediates` calls that
# wgpu-native's webgpu.h has and emdawnwebgpu's does not.
# scripts/check-web-imports.sh keeps this list equal to that definition.
comptime _NATIVE_ONLY = (
    "wgpuCommandEncoderClearTexture",
    "wgpuComputePassEncoderBeginPipelineStatisticsQuery",
    "wgpuComputePassEncoderEndPipelineStatisticsQuery",
    "wgpuComputePassEncoderSetImmediates",
    "wgpuComputePassEncoderWriteTimestamp",
    "wgpuDeviceCreateShaderModuleSpirV",
    "wgpuDeviceCreateShaderModuleTrusted",
    "wgpuDeviceGetNativeMetalDevice",
    "wgpuDevicePoll",
    "wgpuDeviceStartGraphicsDebuggerCapture",
    "wgpuDeviceStopGraphicsDebuggerCapture",
    "wgpuGenerateReport",
    "wgpuGetVersion",
    "wgpuInstanceEnumerateAdapters",
    "wgpuQueueGetNativeMetalCommandQueue",
    "wgpuQueueGetTimestampPeriod",
    "wgpuQueueSubmitForIndex",
    "wgpuRenderBundleEncoderSetImmediates",
    "wgpuRenderPassEncoderBeginPipelineStatisticsQuery",
    "wgpuRenderPassEncoderEndPipelineStatisticsQuery",
    "wgpuRenderPassEncoderMultiDrawIndexedIndirect",
    "wgpuRenderPassEncoderMultiDrawIndexedIndirectCount",
    "wgpuRenderPassEncoderMultiDrawIndirect",
    "wgpuRenderPassEncoderMultiDrawIndirectCount",
    "wgpuRenderPassEncoderSetImmediates",
    "wgpuRenderPassEncoderWriteTimestamp",
    "wgpuSetLogCallback",
    "wgpuSetLogLevel",
    "wgpuTextureGetNativeMetalTexture",
)


def native_only(name: StaticString) -> Bool:
    """True if `name` is a wgpu-native extension the browser lacks."""
    comptime for i in range(len(_NATIVE_ONLY)):
        if name == _NATIVE_ONLY[i]:
            return True
    return False
