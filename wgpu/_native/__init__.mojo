"""wgpu._native — Backward-compat shim. Use wgpu._backend.wgpu_native.native_ext."""

from wgpu._backend.wgpu_native.native_ext import (
    WGPUNativeSType, WGPUNativeFeature, WGPULogLevel, WGPUShaderRuntimeChecks,
    WGPUInstanceBackend, WGPUInstanceFlag,
    NativeDisplayHandleData, WGPUNativeDisplayHandle,
    WGPUInstanceExtras, WGPUDeviceExtras, WGPUNativeLimits,
    WGPUInstanceEnumerateAdapterOptions,
    WGPURegistryReport, WGPUHubReport, WGPUGlobalReport,
    WGPUBindGroupEntryExtras, WGPUBindGroupLayoutEntryExtras,
    WGPUQuerySetDescriptorExtras, WGPUSurfaceConfigurationExtras,
    WGPUPrimitiveStateExtras, WGPUSamplerDescriptorExtras,
    WGPUImageSubresourceRange,
)
