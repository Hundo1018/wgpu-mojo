"""wgpu._ffi.handles — Backward-compat shim. Use wgpu._backend.wgpu_native.handles."""

from wgpu._backend.wgpu_native.handles import (
    AdapterHandle, DeviceHandle, QueueHandle, BufferHandle,
    TextureHandle, TextureViewHandle, SamplerHandle, ShaderModuleHandle,
    BindGroupLayoutHandle, BindGroupHandle, PipelineLayoutHandle,
    ComputePipelineHandle, RenderPipelineHandle,
    CommandEncoderHandle, CommandBufferHandle,
    QuerySetHandle, SurfaceHandle,
    InstanceHandle, ComputePassEncoderHandle, RenderPassEncoderHandle,
    RenderBundleHandle, RenderBundleEncoderHandle,
)
