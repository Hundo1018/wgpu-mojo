"""
wgpu — Pure Mojo bindings for wgpu-native (WebGPU).

Quick start:
    from wgpu import request_adapter

    var instance = request_adapter()
    var device   = instance.request_device()
    ...
"""

# Top-level entry point
from wgpu.gpu import request_adapter

# High-level RAII wrappers
from wgpu.instance      import Instance
from wgpu.device        import Device
from wgpu.buffer        import Buffer
from wgpu.texture       import Texture, TextureView
from wgpu.sampler       import Sampler
from wgpu.shader        import ShaderModule
from wgpu.bind_group    import BindGroup, BindGroupLayout
from wgpu.pipeline_layout import PipelineLayout
from wgpu.pipeline      import ComputePipeline, RenderPipeline
from wgpu.command       import CommandEncoder
from wgpu.compute_pass  import ComputePassEncoder
from wgpu.render_pass   import RenderPassEncoder

# Low-level types (for users who need raw descriptors)
from wgpu._ffi.types import (
    OpaquePtr,
    WGPUAdapterType, WGPUAddressMode, WGPUBackendType,
    WGPUBlendFactor, WGPUBlendOperation, WGPUBufferBindingType,
    WGPUCallbackMode, WGPUCompareFunction, WGPUCullMode,
    WGPUFeatureName, WGPUFilterMode, WGPUFrontFace, WGPUIndexFormat,
    WGPULoadOp, WGPUMapAsyncStatus, WGPUMipmapFilterMode,
    WGPUPresentMode, WGPUPrimitiveTopology, WGPUQueryType,
    WGPURequestAdapterStatus, WGPURequestDeviceStatus,
    WGPUSamplerBindingType, WGPUStatus,
    WGPUSType,
    WGPUStorageTextureAccess, WGPUStoreOp,
    WGPUTextureAspect, WGPUTextureDimension,
    WGPUTextureFormat, WGPUTextureSampleType, WGPUTextureViewDimension,
    WGPUVertexFormat, WGPUVertexStepMode,
    WGPUBufferUsage, WGPUColorWriteMask, WGPUMapMode, WGPUShaderStage, WGPUTextureUsage,
    WGPU_WHOLE_SIZE, WGPU_LIMIT_U32_UNDEFINED, WGPU_LIMIT_U64_UNDEFINED,
)
from wgpu._ffi.structs import (
    WGPUStringView, str_to_sv,
    WGPUExtent3D, WGPUOrigin3D, WGPUColor,
    WGPUBlendComponent, WGPUBlendState,
    WGPULimits, wgpu_limits_default,
    WGPUBindGroupEntry, WGPUBindGroupLayoutEntry,
    WGPUBindGroupDescriptor, WGPUBindGroupLayoutDescriptor,
    WGPUBufferBindingLayout, WGPUSamplerBindingLayout,
    WGPUTextureBindingLayout, WGPUStorageTextureBindingLayout,
    WGPUConstantEntry,
    WGPUComputeState, WGPUComputePipelineDescriptor,
    WGPUVertexAttribute, WGPUVertexBufferLayout, WGPUVertexState,
    WGPUMultisampleState, WGPUPrimitiveState,
    WGPUStencilFaceState, WGPUDepthStencilState,
    WGPUColorTargetState, WGPUFragmentState,
    WGPURenderPassColorAttachment, WGPURenderPassDepthStencilAttachment,
    WGPURenderPassDescriptor, WGPURenderPipelineDescriptor,
    WGPUTextureDescriptor, WGPUTextureViewDescriptor,
    WGPUSamplerDescriptor,
    WGPUSurfaceDescriptor, WGPUSurfaceCapabilities, WGPUSurfaceConfiguration,
    WGPUSurfaceSourceWaylandSurface, WGPUSurfaceSourceXlibWindow,
    WGPUTexelCopyBufferLayout, WGPUTexelCopyBufferInfo, WGPUTexelCopyTextureInfo,
    WGPUAdapterInfo,
)
