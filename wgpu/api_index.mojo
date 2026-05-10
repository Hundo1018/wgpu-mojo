"""
wgpu.api_index — Human-readable index of the public wgpu API surface.

Call api_index() to get a structured text listing every symbol exported by
the wgpu package. Useful for consumers who only have the compiled .mojopkg
and cannot browse source files.

Example::

    from wgpu.api_index import api_index
    print(api_index())
"""


def api_index() -> String:
    """Return a structured text index of all public wgpu symbols.

    The output is stable across patch releases. Symbols are grouped by
    category and listed alphabetically within each group.

    This is intentionally a static listing (not reflection-based) so it
    works identically from source and from a compiled .mojopkg.
    """
    return """wgpu-mojo public API index (wgpu-native ABI: v29.0.0.0)
================================================================

## Entry points
  Instance                    — owns WGPULib + WGPUInstance
  Instance.request_adapter()  — select an Adapter by index (default 0)
  Instance.get_version()      — wgpu-native library version as UInt32
  Adapter                     — selected GPU adapter
  Adapter.request_device()    — create a Device from the selected adapter
  Adapter.adapter_info()      — WGPUAdapterInfo for the selected adapter
  Adapter.backend_type()      — UInt32 backend (use WGPUBackendType constants)
  Adapter.adapter_type()      — UInt32 adapter kind (WGPUAdapterType constants)
  Adapter.create_surface_wayland() — create a Surface from Wayland display + wl_surface
  Adapter.create_surface_xlib()    — create a Surface from X11 Display* + Window id
  set_log_level(level)        — set wgpu-native log verbosity (0=Off … 5=Trace)
  preflight()                 — diagnostic string: library paths, adapter list

## RAII wrappers (own GPU objects; release on drop)
  Device                      — logical GPU device + queue
  Buffer                      — GPU memory buffer
  Texture                     — GPU texture object
  TextureView                 — view into a Texture
  Surface                     — OS window surface (swapchain)
  SurfaceFrame                — one renderable frame from a Surface
  Sampler                     — texture sampler configuration
  ShaderModule                — compiled WGSL shader
  BindGroup                   — descriptor set binding group
  BindGroupLayout             — layout template for BindGroup
  PipelineLayout              — layout for pipeline descriptor sets
  ComputePipeline             — compute pipeline state
  RenderPipeline              — render pipeline state
  CommandEncoder              — records GPU commands
  CommandBuffer               — finalized command buffer for submission
  ComputePassEncoder          — encodes compute dispatch commands
  RenderPassEncoder           — encodes render draw commands
  QuerySet                    — GPU timing / occlusion query set

## Strongly typed handle newtypes (TrivialRegisterPassable, for FFI boundaries)
  AdapterHandle, DeviceHandle, QueueHandle
  BufferHandle, TextureHandle, TextureViewHandle
  SamplerHandle, ShaderModuleHandle
  BindGroupHandle, BindGroupLayoutHandle
  PipelineLayoutHandle, ComputePipelineHandle, RenderPipelineHandle
  CommandEncoderHandle, CommandBufferHandle
  ComputePassEncoderHandle, RenderPassEncoderHandle
  QuerySetHandle, SurfaceHandle, InstanceHandle

## Enum structs (comptime UInt32 constants)
  WGPUAdapterType             — DiscreteGPU, IntegratedGPU, CPU, Unknown
  WGPUAddressMode             — ClampToEdge, Repeat, MirrorRepeat
  WGPUBackendType             — Vulkan, Metal, D3D12, D3D11, OpenGL, OpenGLES, WebGPU, Null
  WGPUBlendFactor             — Zero, One, Src, Dst, SrcAlpha, …
  WGPUBlendOperation          — Add, Subtract, ReverseSubtract, Min, Max
  WGPUBufferBindingType       — Uniform, Storage, ReadOnlyStorage
  WGPUCallbackMode            — WaitAnyOnly, AllowProcessEvents, AllowSpontaneous
  WGPUCompareFunction         — Never, Less, Equal, LessEqual, Greater, …
  WGPUCullMode                — None, Front, Back
  WGPUFeatureName             — (standard WebGPU feature names)
  WGPUFilterMode              — Nearest, Linear
  WGPUFrontFace               — CCW, CW
  WGPUIndexFormat             — Uint16, Uint32
  WGPULoadOp                  — Undefined, Load, Clear
  WGPUMapAsyncStatus          — Success, InstanceDropped, Error, Aborted, Unknown
  WGPUMipmapFilterMode        — Nearest, Linear
  WGPUPresentMode             — Fifo, FifoRelaxed, Immediate, Mailbox
  WGPUPrimitiveTopology       — PointList, LineList, LineStrip, TriangleList, TriangleStrip
  WGPUQueryType               — Occlusion, Timestamp
  WGPURequestAdapterStatus    — Success, InstanceDropped, Unavailable, Error, Unknown
  WGPURequestDeviceStatus     — Success, InstanceDropped, Error, Unknown
  WGPUSamplerBindingType      — Filtering, NonFiltering, Comparison
  WGPUStatus                  — Success, Error
  WGPUStorageTextureAccess    — Undefined, WriteOnly, ReadOnly, ReadWrite
  WGPUStoreOp                 — Undefined, Store, Discard
  WGPUSType                   — (chain struct type tags)
  WGPUTextureAspect           — All, StencilOnly, DepthOnly
  WGPUTextureDimension        — 1D, 2D, 3D
  WGPUTextureFormat           — RGBA8Unorm, BGRA8Unorm, Depth24Plus, … (50+ formats)
  WGPUTextureSampleType       — Float, UnfilterableFloat, Depth, Sint, Uint
  WGPUTextureViewDimension    — 1D, 2D, 2DArray, Cube, CubeArray, 3D
  WGPUVertexFormat            — Float32, Float32x2, Float32x4, …
  WGPUVertexStepMode          — VertexBufferNotUsed, Vertex, Instance

## Bitflag structs (UInt64 bitmasks; combine with |)
  WGPUBufferUsage             — COPY_SRC, COPY_DST, INDEX, VERTEX, UNIFORM, STORAGE, …
  WGPUColorWriteMask          — RED, GREEN, BLUE, ALPHA, ALL
  WGPUMapMode                 — Read, Write
  WGPUShaderStage             — VERTEX, FRAGMENT, COMPUTE, NONE
  WGPUTextureUsage            — COPY_SRC, COPY_DST, TEXTURE_BINDING, STORAGE_BINDING, RENDER_ATTACHMENT

## Constants
  WGPU_WHOLE_SIZE             — UInt64: pass for "whole buffer" range
  WGPU_LIMIT_U32_UNDEFINED    — UInt32: sentinel for "adapter default" limit
  WGPU_LIMIT_U64_UNDEFINED    — UInt64: sentinel for "adapter default" limit

## Descriptor structs (pass to Device creation methods)
  WGPUExtent3D                — { width, height, depthOrArrayLayers }
  WGPUOrigin3D                — { x, y, z }
  WGPUColor                   — { r, g, b, a } Float64
  WGPUBlendComponent          — { operation, srcFactor, dstFactor }
  WGPUBlendState              — { color: WGPUBlendComponent, alpha: WGPUBlendComponent }
  WGPULimits                  — all adapter/device limits
  WGPUBindGroupEntry          — single binding entry (buffer, sampler, texture)
  WGPUBindGroupLayoutEntry    — binding slot layout (type, visibility)
  WGPUBindGroupDescriptor     — list of WGPUBindGroupEntry
  WGPUBindGroupLayoutDescriptor — list of WGPUBindGroupLayoutEntry
  WGPUBufferBindingLayout     — { type, hasDynamicOffset, minBindingSize }
  WGPUSamplerBindingLayout    — { type }
  WGPUTextureBindingLayout    — { sampleType, viewDimension, multisampled }
  WGPUStorageTextureBindingLayout — { access, format, viewDimension }
  WGPUConstantEntry           — pipeline-overridable constant { key, value }
  WGPUComputeState            — { module, entryPoint, constants }
  WGPUComputePipelineDescriptor — { layout, compute: WGPUComputeState }
  WGPUVertexAttribute         — { format, offset, shaderLocation }
  WGPUVertexBufferLayout      — { arrayStride, stepMode, attributes }
  WGPUVertexState             — { module, entryPoint, buffers }
  WGPUMultisampleState        — { count, mask, alphaToCoverageEnabled }
  WGPUPrimitiveState          — { topology, stripIndexFormat, frontFace, cullMode }
  WGPUStencilFaceState        — { compare, failOp, depthFailOp, passOp }
  WGPUDepthStencilState       — { format, depthWriteEnabled, depthCompare, … }
  WGPUColorTargetState        — { format, blend, writeMask }
  WGPUFragmentState           — { module, entryPoint, targets }
  WGPURenderPassColorAttachment — { view, resolveTarget, loadOp, storeOp, clearValue }
  WGPURenderPassDepthStencilAttachment — { view, depthLoadOp, depthStoreOp, … }
  WGPURenderPassDescriptor    — { colorAttachments, depthStencilAttachment }
  WGPURenderPipelineDescriptor — { layout, vertex, primitive, depthStencil, multisample, fragment }
  WGPUTextureDescriptor       — { size, mipLevelCount, sampleCount, dimension, format, usage }
  WGPUTextureViewDescriptor   — { format, dimension, aspect, baseMipLevel, … }
  WGPUSamplerDescriptor       — { addressModeU/V/W, magFilter, minFilter, … }
  WGPUSurfaceDescriptor       — platform-specific surface source
  WGPUSurfaceCapabilities     — formats and present modes supported by a surface
  WGPUSurfaceConfiguration    — { device, format, usage, width, height, presentMode }
  WGPUSurfaceTexture          — { texture, status }
  WGPUSurfaceSourceWaylandSurface — Wayland-specific surface source
  WGPUSurfaceSourceXlibWindow — X11-specific surface source
  WGPUTexelCopyBufferLayout   — { offset, bytesPerRow, rowsPerImage }
  WGPUTexelCopyBufferInfo     — { layout, buffer }
  WGPUTexelCopyTextureInfo    — { texture, mipLevel, origin, aspect }
  WGPUAdapterInfo             — vendor, architecture, device, description + type fields
  WGPUStringView              — FFI string type { data, length }
  str_to_sv(ref s: String)    — borrow a String as WGPUStringView for FFI calls
  wgpu_limits_default()       — return WGPULimits with all fields set to UNDEFINED

## Utility
  api_index()                 — return this text (from wgpu.api_index)
"""
