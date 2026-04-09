"""
wgpu._ffi.types — Low-level C type aliases, enum constants, and bitflags
mirroring webgpu.h for the wgpu-native v27 API.
"""

from std.ffi import OwnedDLHandle

# ---------------------------------------------------------------------------
# Opaque handle types (all wgpu objects are pointer-sized)
# ---------------------------------------------------------------------------
comptime OpaquePtr = UnsafePointer[NoneType, MutExternalOrigin]

comptime WGPUAdapterHandle = OpaquePtr
comptime WGPUBindGroupHandle = OpaquePtr
comptime WGPUBindGroupLayoutHandle = OpaquePtr
comptime WGPUBufferHandle = OpaquePtr
comptime WGPUCommandBufferHandle = OpaquePtr
comptime WGPUCommandEncoderHandle = OpaquePtr
comptime WGPUComputePassEncoderHandle = OpaquePtr
comptime WGPUComputePipelineHandle = OpaquePtr
comptime WGPUDeviceHandle = OpaquePtr
comptime WGPUExternalTextureHandle = OpaquePtr
comptime WGPUInstanceHandle = OpaquePtr
comptime WGPUPipelineLayoutHandle = OpaquePtr
comptime WGPUQuerySetHandle = OpaquePtr
comptime WGPUQueueHandle = OpaquePtr
comptime WGPURenderBundleHandle = OpaquePtr
comptime WGPURenderBundleEncoderHandle = OpaquePtr
comptime WGPURenderPassEncoderHandle = OpaquePtr
comptime WGPURenderPipelineHandle = OpaquePtr
comptime WGPUSamplerHandle = OpaquePtr
comptime WGPUShaderModuleHandle = OpaquePtr
comptime WGPUSurfaceHandle = OpaquePtr
comptime WGPUTextureHandle = OpaquePtr
comptime WGPUTextureViewHandle = OpaquePtr

# WGPUBool is uint32_t in C
comptime WGPUBool = UInt32
comptime WGPU_FALSE: UInt32 = 0
comptime WGPU_TRUE: UInt32 = 1

# WGPUFlags is uint64_t in C
comptime WGPUFlags = UInt64

# Sentinel / special values
comptime WGPU_STRLEN: UInt = UInt.MAX              # SIZE_MAX — null-terminated
comptime WGPU_WHOLE_SIZE: UInt64 = UInt64.MAX
comptime WGPU_WHOLE_MAP_SIZE: UInt = UInt.MAX
comptime WGPU_ARRAY_LAYER_COUNT_UNDEFINED: UInt32 = UInt32.MAX
comptime WGPU_COPY_STRIDE_UNDEFINED: UInt32 = UInt32.MAX
comptime WGPU_DEPTH_SLICE_UNDEFINED: UInt32 = UInt32.MAX
comptime WGPU_MIP_LEVEL_COUNT_UNDEFINED: UInt32 = UInt32.MAX
comptime WGPU_QUERY_SET_INDEX_UNDEFINED: UInt32 = UInt32.MAX
comptime WGPU_LIMIT_U32_UNDEFINED: UInt32 = UInt32.MAX
comptime WGPU_LIMIT_U64_UNDEFINED: UInt64 = UInt64.MAX

# ---------------------------------------------------------------------------
# Enum namespaces (constants only — use UInt32 values)
# ---------------------------------------------------------------------------

struct WGPUAdapterType:
    comptime DiscreteGPU: UInt32 = 1
    comptime IntegratedGPU: UInt32 = 2
    comptime CPU: UInt32 = 3
    comptime Unknown: UInt32 = 4

struct WGPUAddressMode:
    comptime Undefined: UInt32 = 0
    comptime ClampToEdge: UInt32 = 1
    comptime Repeat: UInt32 = 2
    comptime MirrorRepeat: UInt32 = 3

struct WGPUBackendType:
    comptime Undefined: UInt32 = 0
    comptime Null: UInt32 = 1
    comptime WebGPU: UInt32 = 2
    comptime D3D11: UInt32 = 3
    comptime D3D12: UInt32 = 4
    comptime Metal: UInt32 = 5
    comptime Vulkan: UInt32 = 6
    comptime OpenGL: UInt32 = 7
    comptime OpenGLES: UInt32 = 8

struct WGPUBlendFactor:
    comptime Undefined: UInt32 = 0
    comptime Zero: UInt32 = 1
    comptime One: UInt32 = 2
    comptime Src: UInt32 = 3
    comptime OneMinusSrc: UInt32 = 4
    comptime SrcAlpha: UInt32 = 5
    comptime OneMinusSrcAlpha: UInt32 = 6
    comptime Dst: UInt32 = 7
    comptime OneMinusDst: UInt32 = 8
    comptime DstAlpha: UInt32 = 9
    comptime OneMinusDstAlpha: UInt32 = 10
    comptime SrcAlphaSaturated: UInt32 = 11
    comptime Constant: UInt32 = 12
    comptime OneMinusConstant: UInt32 = 13
    comptime Src1: UInt32 = 14
    comptime OneMinusSrc1: UInt32 = 15
    comptime Src1Alpha: UInt32 = 16
    comptime OneMinusSrc1Alpha: UInt32 = 17

struct WGPUBlendOperation:
    comptime Undefined: UInt32 = 0
    comptime Add: UInt32 = 1
    comptime Subtract: UInt32 = 2
    comptime ReverseSubtract: UInt32 = 3
    comptime Min: UInt32 = 4
    comptime Max: UInt32 = 5

struct WGPUBufferBindingType:
    comptime BindingNotUsed: UInt32 = 0
    comptime Undefined: UInt32 = 1
    comptime Uniform: UInt32 = 2
    comptime Storage: UInt32 = 3
    comptime ReadOnlyStorage: UInt32 = 4

struct WGPUBufferMapState:
    comptime Unmapped: UInt32 = 1
    comptime Pending: UInt32 = 2
    comptime Mapped: UInt32 = 3

struct WGPUCallbackMode:
    comptime WaitAnyOnly: UInt32 = 1
    comptime AllowProcessEvents: UInt32 = 2
    comptime AllowSpontaneous: UInt32 = 3

struct WGPUCompareFunction:
    comptime Undefined: UInt32 = 0
    comptime Never: UInt32 = 1
    comptime Less: UInt32 = 2
    comptime Equal: UInt32 = 3
    comptime LessEqual: UInt32 = 4
    comptime Greater: UInt32 = 5
    comptime NotEqual: UInt32 = 6
    comptime GreaterEqual: UInt32 = 7
    comptime Always: UInt32 = 8

struct WGPUCompilationInfoRequestStatus:
    comptime Success: UInt32 = 1
    comptime CallbackCancelled: UInt32 = 2

struct WGPUCompilationMessageType:
    comptime Error: UInt32 = 1
    comptime Warning: UInt32 = 2
    comptime Info: UInt32 = 3

struct WGPUComponentSwizzle:
    comptime Undefined: UInt32 = 0
    comptime Zero: UInt32 = 1
    comptime One: UInt32 = 2
    comptime R: UInt32 = 3
    comptime G: UInt32 = 4
    comptime B: UInt32 = 5
    comptime A: UInt32 = 6

struct WGPUCompositeAlphaMode:
    comptime Auto: UInt32 = 0
    comptime Opaque: UInt32 = 1
    comptime Premultiplied: UInt32 = 2
    comptime Unpremultiplied: UInt32 = 3
    comptime Inherit: UInt32 = 4

struct WGPUCreatePipelineAsyncStatus:
    comptime Success: UInt32 = 1
    comptime CallbackCancelled: UInt32 = 2
    comptime ValidationError: UInt32 = 3
    comptime InternalError: UInt32 = 4

struct WGPUCullMode:
    comptime Undefined: UInt32 = 0
    comptime NoCull: UInt32 = 1    # 'None' is reserved in Mojo
    comptime Front: UInt32 = 2
    comptime Back: UInt32 = 3

struct WGPUDeviceLostReason:
    comptime Unknown: UInt32 = 1
    comptime Destroyed: UInt32 = 2
    comptime CallbackCancelled: UInt32 = 3
    comptime FailedCreation: UInt32 = 4

struct WGPUErrorFilter:
    comptime Validation: UInt32 = 1
    comptime OutOfMemory: UInt32 = 2
    comptime Internal: UInt32 = 3

struct WGPUErrorType:
    comptime NoError: UInt32 = 1
    comptime Validation: UInt32 = 2
    comptime OutOfMemory: UInt32 = 3
    comptime Internal: UInt32 = 4
    comptime Unknown: UInt32 = 5

struct WGPUFeatureLevel:
    comptime Undefined: UInt32 = 0
    comptime Compatibility: UInt32 = 1
    comptime Core: UInt32 = 2

struct WGPUFeatureName:
    comptime CoreFeaturesAndLimits: UInt32 = 0x00000001
    comptime DepthClipControl: UInt32 = 0x00000002
    comptime Depth32FloatStencil8: UInt32 = 0x00000003
    comptime TextureCompressionBC: UInt32 = 0x00000004
    comptime TextureCompressionBCSliced3D: UInt32 = 0x00000005
    comptime TextureCompressionETC2: UInt32 = 0x00000006
    comptime TextureCompressionASTC: UInt32 = 0x00000007
    comptime TextureCompressionASTCSliced3D: UInt32 = 0x00000008
    comptime TimestampQuery: UInt32 = 0x00000009
    comptime IndirectFirstInstance: UInt32 = 0x0000000A
    comptime ShaderF16: UInt32 = 0x0000000B
    comptime RG11B10UfloatRenderable: UInt32 = 0x0000000C
    comptime BGRA8UnormStorage: UInt32 = 0x0000000D
    comptime Float32Filterable: UInt32 = 0x0000000E
    comptime Float32Blendable: UInt32 = 0x0000000F
    comptime ClipDistances: UInt32 = 0x00000010
    comptime DualSourceBlending: UInt32 = 0x00000011
    comptime Subgroups: UInt32 = 0x00000012
    comptime TextureFormatsTier1: UInt32 = 0x00000013
    comptime TextureFormatsTier2: UInt32 = 0x00000014
    comptime PrimitiveIndex: UInt32 = 0x00000015
    comptime TextureComponentSwizzle: UInt32 = 0x00000016

struct WGPUFilterMode:
    comptime Undefined: UInt32 = 0
    comptime Nearest: UInt32 = 1
    comptime Linear: UInt32 = 2

struct WGPUFrontFace:
    comptime Undefined: UInt32 = 0
    comptime CCW: UInt32 = 1
    comptime CW: UInt32 = 2

struct WGPUIndexFormat:
    comptime Undefined: UInt32 = 0
    comptime Uint16: UInt32 = 1
    comptime Uint32: UInt32 = 2

struct WGPUInstanceFeatureName:
    comptime TimedWaitAny: UInt32 = 1
    comptime ShaderSourceSPIRV: UInt32 = 2
    comptime MultipleDevicesPerAdapter: UInt32 = 3

struct WGPULoadOp:
    comptime Undefined: UInt32 = 0
    comptime Load: UInt32 = 1
    comptime Clear: UInt32 = 2

struct WGPUMapAsyncStatus:
    comptime Success: UInt32 = 1
    comptime CallbackCancelled: UInt32 = 2
    comptime Error: UInt32 = 3
    comptime Aborted: UInt32 = 4

struct WGPUMipmapFilterMode:
    comptime Undefined: UInt32 = 0
    comptime Nearest: UInt32 = 1
    comptime Linear: UInt32 = 2

struct WGPUOptionalBool:
    comptime FalseVal: UInt32 = 0  # 'False' is reserved in Mojo
    comptime TrueVal: UInt32 = 1   # 'True' is reserved in Mojo
    comptime Undefined: UInt32 = 2

struct WGPUPopErrorScopeStatus:
    comptime Success: UInt32 = 1
    comptime CallbackCancelled: UInt32 = 2
    comptime Error: UInt32 = 3

struct WGPUPowerPreference:
    comptime Undefined: UInt32 = 0
    comptime LowPower: UInt32 = 1
    comptime HighPerformance: UInt32 = 2

struct WGPUPredefinedColorSpace:
    comptime SRGB: UInt32 = 1
    comptime DisplayP3: UInt32 = 2

struct WGPUPresentMode:
    comptime Undefined: UInt32 = 0
    comptime Fifo: UInt32 = 1
    comptime FifoRelaxed: UInt32 = 2
    comptime Immediate: UInt32 = 3
    comptime Mailbox: UInt32 = 4

struct WGPUPrimitiveTopology:
    comptime Undefined: UInt32 = 0
    comptime PointList: UInt32 = 1
    comptime LineList: UInt32 = 2
    comptime LineStrip: UInt32 = 3
    comptime TriangleList: UInt32 = 4
    comptime TriangleStrip: UInt32 = 5

struct WGPUQueryType:
    comptime Occlusion: UInt32 = 1
    comptime Timestamp: UInt32 = 2

struct WGPUQueueWorkDoneStatus:
    comptime Success: UInt32 = 1
    comptime CallbackCancelled: UInt32 = 2
    comptime Error: UInt32 = 3

struct WGPURequestAdapterStatus:
    comptime Success: UInt32 = 1
    comptime CallbackCancelled: UInt32 = 2
    comptime Unavailable: UInt32 = 3
    comptime Error: UInt32 = 4

struct WGPURequestDeviceStatus:
    comptime Success: UInt32 = 1
    comptime CallbackCancelled: UInt32 = 2
    comptime Error: UInt32 = 3

struct WGPUSamplerBindingType:
    comptime BindingNotUsed: UInt32 = 0
    comptime Undefined: UInt32 = 1
    comptime Filtering: UInt32 = 2
    comptime NonFiltering: UInt32 = 3
    comptime Comparison: UInt32 = 4

struct WGPUStatus:
    comptime Success: UInt32 = 1
    comptime Error: UInt32 = 2

struct WGPUStencilOperation:
    comptime Undefined: UInt32 = 0
    comptime Keep: UInt32 = 1
    comptime Zero: UInt32 = 2
    comptime Replace: UInt32 = 3
    comptime Invert: UInt32 = 4
    comptime IncrementClamp: UInt32 = 5
    comptime DecrementClamp: UInt32 = 6
    comptime IncrementWrap: UInt32 = 7
    comptime DecrementWrap: UInt32 = 8

struct WGPUStorageTextureAccess:
    comptime BindingNotUsed: UInt32 = 0
    comptime Undefined: UInt32 = 1
    comptime WriteOnly: UInt32 = 2
    comptime ReadOnly: UInt32 = 3
    comptime ReadWrite: UInt32 = 4

struct WGPUStoreOp:
    comptime Undefined: UInt32 = 0
    comptime Store: UInt32 = 1
    comptime Discard: UInt32 = 2

struct WGPUSType:
    comptime ShaderSourceSPIRV: UInt32 = 0x00000001
    comptime ShaderSourceWGSL: UInt32 = 0x00000002
    comptime RenderPassMaxDrawCount: UInt32 = 0x00000003
    comptime SurfaceSourceMetalLayer: UInt32 = 0x00000004
    comptime SurfaceSourceWindowsHWND: UInt32 = 0x00000005
    comptime SurfaceSourceXlibWindow: UInt32 = 0x00000006
    comptime SurfaceSourceWaylandSurface: UInt32 = 0x00000007
    comptime SurfaceSourceAndroidNativeWindow: UInt32 = 0x00000008
    comptime SurfaceSourceXCBWindow: UInt32 = 0x00000009
    comptime SurfaceColorManagement: UInt32 = 0x0000000A
    comptime RequestAdapterWebXROptions: UInt32 = 0x0000000B
    comptime TextureComponentSwizzleDescriptor: UInt32 = 0x0000000C
    comptime ExternalTextureBindingLayout: UInt32 = 0x0000000D
    comptime ExternalTextureBindingEntry: UInt32 = 0x0000000E
    comptime CompatibilityModeLimits: UInt32 = 0x0000000F
    comptime TextureBindingViewDimension: UInt32 = 0x00000010
    # wgpu-native extension STypes (from wgpu.h, start at 0x00030001)
    comptime InstanceExtras: UInt32 = 0x00030001
    comptime DeviceExtras: UInt32 = 0x00030002
    comptime NativeLimits: UInt32 = 0x00030003
    comptime PipelineLayoutExtras: UInt32 = 0x00030004
    comptime ShaderModuleGLSLDescriptor: UInt32 = 0x00030005
    comptime SupportedLimitsExtras: UInt32 = 0x00030003
    comptime PushConstantRange: UInt32 = 0x00030006
    comptime InstanceEnumerateAdapterOptions: UInt32 = 0x00030007
    comptime BindGroupEntryExtras: UInt32 = 0x00030008
    comptime BindGroupLayoutEntryExtras: UInt32 = 0x00030009
    comptime QuerySetDescriptorExtras: UInt32 = 0x0003000A
    comptime SurfaceConfigurationExtras: UInt32 = 0x0003000B

struct WGPUSurfaceGetCurrentTextureStatus:
    comptime SuccessOptimal: UInt32 = 1
    comptime SuccessSuboptimal: UInt32 = 2
    comptime Timeout: UInt32 = 3
    comptime Outdated: UInt32 = 4
    comptime Lost: UInt32 = 5
    comptime Error: UInt32 = 6

struct WGPUTextureAspect:
    comptime Undefined: UInt32 = 0
    comptime All: UInt32 = 1
    comptime StencilOnly: UInt32 = 2
    comptime DepthOnly: UInt32 = 3

struct WGPUTextureDimension:
    comptime Undefined: UInt32 = 0
    comptime D1: UInt32 = 1
    comptime D2: UInt32 = 2
    comptime D3: UInt32 = 3

struct WGPUTextureFormat:
    comptime Undefined: UInt32 = 0x00000000
    comptime R8Unorm: UInt32 = 0x00000001
    comptime R8Snorm: UInt32 = 0x00000002
    comptime R8Uint: UInt32 = 0x00000003
    comptime R8Sint: UInt32 = 0x00000004
    comptime R16Uint: UInt32 = 0x00000005
    comptime R16Sint: UInt32 = 0x00000006
    comptime R16Float: UInt32 = 0x00000007
    comptime RG8Unorm: UInt32 = 0x00000008
    comptime RG8Snorm: UInt32 = 0x00000009
    comptime RG8Uint: UInt32 = 0x0000000A
    comptime RG8Sint: UInt32 = 0x0000000B
    comptime R32Float: UInt32 = 0x0000000C
    comptime R32Uint: UInt32 = 0x0000000D
    comptime R32Sint: UInt32 = 0x0000000E
    comptime RG16Uint: UInt32 = 0x0000000F
    comptime RG16Sint: UInt32 = 0x00000010
    comptime RG16Float: UInt32 = 0x00000011
    comptime RGBA8Unorm: UInt32 = 0x00000012
    comptime RGBA8UnormSrgb: UInt32 = 0x00000013
    comptime RGBA8Snorm: UInt32 = 0x00000014
    comptime RGBA8Uint: UInt32 = 0x00000015
    comptime RGBA8Sint: UInt32 = 0x00000016
    comptime BGRA8Unorm: UInt32 = 0x00000017
    comptime BGRA8UnormSrgb: UInt32 = 0x00000018
    comptime RGB10A2Uint: UInt32 = 0x00000019
    comptime RGB10A2Unorm: UInt32 = 0x0000001A
    comptime RG11B10Ufloat: UInt32 = 0x0000001B
    comptime RGB9E5Ufloat: UInt32 = 0x0000001C
    comptime RG32Float: UInt32 = 0x0000001D
    comptime RG32Uint: UInt32 = 0x0000001E
    comptime RG32Sint: UInt32 = 0x0000001F
    comptime RGBA16Uint: UInt32 = 0x00000020
    comptime RGBA16Sint: UInt32 = 0x00000021
    comptime RGBA16Float: UInt32 = 0x00000022
    comptime RGBA32Float: UInt32 = 0x00000023
    comptime RGBA32Uint: UInt32 = 0x00000024
    comptime RGBA32Sint: UInt32 = 0x00000025
    comptime Stencil8: UInt32 = 0x00000026
    comptime Depth16Unorm: UInt32 = 0x00000027
    comptime Depth24Plus: UInt32 = 0x00000028
    comptime Depth24PlusStencil8: UInt32 = 0x00000029
    comptime Depth32Float: UInt32 = 0x0000002A
    comptime Depth32FloatStencil8: UInt32 = 0x0000002B
    comptime BC1RGBAUnorm: UInt32 = 0x0000002C
    comptime BC1RGBAUnormSrgb: UInt32 = 0x0000002D
    comptime BC2RGBAUnorm: UInt32 = 0x0000002E
    comptime BC2RGBAUnormSrgb: UInt32 = 0x0000002F
    comptime BC3RGBAUnorm: UInt32 = 0x00000030
    comptime BC3RGBAUnormSrgb: UInt32 = 0x00000031
    comptime BC4RUnorm: UInt32 = 0x00000032
    comptime BC4RSnorm: UInt32 = 0x00000033
    comptime BC5RGUnorm: UInt32 = 0x00000034
    comptime BC5RGSnorm: UInt32 = 0x00000035
    comptime BC6HRGBUfloat: UInt32 = 0x00000036
    comptime BC6HRGBFloat: UInt32 = 0x00000037
    comptime BC7RGBAUnorm: UInt32 = 0x00000038
    comptime BC7RGBAUnormSrgb: UInt32 = 0x00000039
    comptime ETC2RGB8Unorm: UInt32 = 0x0000003A
    comptime ETC2RGB8UnormSrgb: UInt32 = 0x0000003B
    comptime ETC2RGB8A1Unorm: UInt32 = 0x0000003C
    comptime ETC2RGB8A1UnormSrgb: UInt32 = 0x0000003D
    comptime ETC2RGBA8Unorm: UInt32 = 0x0000003E
    comptime ETC2RGBA8UnormSrgb: UInt32 = 0x0000003F
    comptime EACR11Unorm: UInt32 = 0x00000040
    comptime EACR11Snorm: UInt32 = 0x00000041
    comptime EACRG11Unorm: UInt32 = 0x00000042
    comptime EACRG11Snorm: UInt32 = 0x00000043
    comptime ASTC4x4Unorm: UInt32 = 0x00000044
    comptime ASTC4x4UnormSrgb: UInt32 = 0x00000045
    comptime ASTC5x4Unorm: UInt32 = 0x00000046
    comptime ASTC5x4UnormSrgb: UInt32 = 0x00000047
    comptime ASTC5x5Unorm: UInt32 = 0x00000048
    comptime ASTC5x5UnormSrgb: UInt32 = 0x00000049
    comptime ASTC6x5Unorm: UInt32 = 0x0000004A
    comptime ASTC6x5UnormSrgb: UInt32 = 0x0000004B
    comptime ASTC6x6Unorm: UInt32 = 0x0000004C
    comptime ASTC6x6UnormSrgb: UInt32 = 0x0000004D
    comptime ASTC8x5Unorm: UInt32 = 0x0000004E
    comptime ASTC8x5UnormSrgb: UInt32 = 0x0000004F
    comptime ASTC8x6Unorm: UInt32 = 0x00000050
    comptime ASTC8x6UnormSrgb: UInt32 = 0x00000051
    comptime ASTC8x8Unorm: UInt32 = 0x00000052
    comptime ASTC8x8UnormSrgb: UInt32 = 0x00000053
    comptime ASTC10x5Unorm: UInt32 = 0x00000054
    comptime ASTC10x5UnormSrgb: UInt32 = 0x00000055
    comptime ASTC10x6Unorm: UInt32 = 0x00000056
    comptime ASTC10x6UnormSrgb: UInt32 = 0x00000057
    comptime ASTC10x8Unorm: UInt32 = 0x00000058
    comptime ASTC10x8UnormSrgb: UInt32 = 0x00000059
    comptime ASTC10x10Unorm: UInt32 = 0x0000005A
    comptime ASTC10x10UnormSrgb: UInt32 = 0x0000005B
    comptime ASTC12x10Unorm: UInt32 = 0x0000005C
    comptime ASTC12x10UnormSrgb: UInt32 = 0x0000005D
    comptime ASTC12x12Unorm: UInt32 = 0x0000005E
    comptime ASTC12x12UnormSrgb: UInt32 = 0x0000005F
    comptime R16Unorm: UInt32 = 0x00000060
    comptime RG16Unorm: UInt32 = 0x00000061
    comptime RGBA16Unorm: UInt32 = 0x00000062
    comptime R16Snorm: UInt32 = 0x00000063
    comptime RG16Snorm: UInt32 = 0x00000064
    comptime RGBA16Snorm: UInt32 = 0x00000065

struct WGPUTextureSampleType:
    comptime BindingNotUsed: UInt32 = 0
    comptime Undefined: UInt32 = 1
    comptime Float: UInt32 = 2
    comptime UnfilterableFloat: UInt32 = 3
    comptime Depth: UInt32 = 4
    comptime Sint: UInt32 = 5
    comptime Uint: UInt32 = 6

struct WGPUTextureViewDimension:
    comptime Undefined: UInt32 = 0
    comptime D1: UInt32 = 1
    comptime D2: UInt32 = 2
    comptime D2Array: UInt32 = 3
    comptime Cube: UInt32 = 4
    comptime CubeArray: UInt32 = 5
    comptime D3: UInt32 = 6

struct WGPUToneMappingMode:
    comptime Standard: UInt32 = 1
    comptime Extended: UInt32 = 2

struct WGPUVertexFormat:
    comptime Uint8: UInt32 = 0x00000001
    comptime Uint8x2: UInt32 = 0x00000002
    comptime Uint8x4: UInt32 = 0x00000003
    comptime Sint8: UInt32 = 0x00000004
    comptime Sint8x2: UInt32 = 0x00000005
    comptime Sint8x4: UInt32 = 0x00000006
    comptime Unorm8: UInt32 = 0x00000007
    comptime Unorm8x2: UInt32 = 0x00000008
    comptime Unorm8x4: UInt32 = 0x00000009
    comptime Snorm8: UInt32 = 0x0000000A
    comptime Snorm8x2: UInt32 = 0x0000000B
    comptime Snorm8x4: UInt32 = 0x0000000C
    comptime Uint16: UInt32 = 0x0000000D
    comptime Uint16x2: UInt32 = 0x0000000E
    comptime Uint16x4: UInt32 = 0x0000000F
    comptime Sint16: UInt32 = 0x00000010
    comptime Sint16x2: UInt32 = 0x00000011
    comptime Sint16x4: UInt32 = 0x00000012
    comptime Unorm16: UInt32 = 0x00000013
    comptime Unorm16x2: UInt32 = 0x00000014
    comptime Unorm16x4: UInt32 = 0x00000015
    comptime Snorm16: UInt32 = 0x00000016
    comptime Snorm16x2: UInt32 = 0x00000017
    comptime Snorm16x4: UInt32 = 0x00000018
    comptime Float16: UInt32 = 0x00000019
    comptime Float16x2: UInt32 = 0x0000001A
    comptime Float16x4: UInt32 = 0x0000001B
    comptime Float32: UInt32 = 0x0000001C
    comptime Float32x2: UInt32 = 0x0000001D
    comptime Float32x3: UInt32 = 0x0000001E
    comptime Float32x4: UInt32 = 0x0000001F
    comptime Uint32: UInt32 = 0x00000020
    comptime Uint32x2: UInt32 = 0x00000021
    comptime Uint32x3: UInt32 = 0x00000022
    comptime Uint32x4: UInt32 = 0x00000023
    comptime Sint32: UInt32 = 0x00000024
    comptime Sint32x2: UInt32 = 0x00000025
    comptime Sint32x3: UInt32 = 0x00000026
    comptime Sint32x4: UInt32 = 0x00000027
    comptime Unorm10_10_10_2: UInt32 = 0x00000028
    comptime Unorm8x4BGRA: UInt32 = 0x00000029

struct WGPUVertexStepMode:
    comptime Undefined: UInt32 = 0
    comptime Vertex: UInt32 = 1
    comptime Instance: UInt32 = 2

struct WGPUWaitStatus:
    comptime Success: UInt32 = 1
    comptime TimedOut: UInt32 = 2
    comptime Error: UInt32 = 3

struct WGPUWGSLLanguageFeatureName:
    comptime ReadonlyAndReadwriteStorageTextures: UInt32 = 1
    comptime Packed4x8IntegerDotProduct: UInt32 = 2
    comptime UnrestrictedPointerParameters: UInt32 = 3
    comptime PointerCompositeAccess: UInt32 = 4
    comptime ChromiumTestingUnimplemented: UInt32 = 5
    comptime ChromiumTestingUnsafeExperimental: UInt32 = 6
    comptime ChromiumTestingExperimental: UInt32 = 7
    comptime ChromiumTestingShippedWithKillswitch: UInt32 = 8
    comptime ChromiumTestingShipped: UInt32 = 9

# ---------------------------------------------------------------------------
# Bitflags — structs wrapping UInt64, supporting |, &, ~
# ---------------------------------------------------------------------------

@fieldwise_init
struct WGPUBufferUsage(TrivialRegisterPassable):
    var value: UInt64

    comptime NONE = WGPUBufferUsage(0)
    comptime MAP_READ = WGPUBufferUsage(0x0001)
    comptime MAP_WRITE = WGPUBufferUsage(0x0002)
    comptime COPY_SRC = WGPUBufferUsage(0x0004)
    comptime COPY_DST = WGPUBufferUsage(0x0008)
    comptime INDEX = WGPUBufferUsage(0x0010)
    comptime VERTEX = WGPUBufferUsage(0x0020)
    comptime UNIFORM = WGPUBufferUsage(0x0040)
    comptime STORAGE = WGPUBufferUsage(0x0080)
    comptime INDIRECT = WGPUBufferUsage(0x0100)
    comptime QUERY_RESOLVE = WGPUBufferUsage(0x0200)

    def __or__(self, rhs: WGPUBufferUsage) -> WGPUBufferUsage:
        return WGPUBufferUsage(self.value | rhs.value)

    def __and__(self, rhs: WGPUBufferUsage) -> WGPUBufferUsage:
        return WGPUBufferUsage(self.value & rhs.value)

    def __invert__(self) -> WGPUBufferUsage:
        return WGPUBufferUsage(~self.value)

    def __eq__(self, rhs: WGPUBufferUsage) -> Bool:
        return self.value == rhs.value

    def contains(self, flag: WGPUBufferUsage) -> Bool:
        return (self.value & flag.value) == flag.value


@fieldwise_init
struct WGPUColorWriteMask(TrivialRegisterPassable):
    var value: UInt64

    comptime NONE = WGPUColorWriteMask(0)
    comptime RED = WGPUColorWriteMask(0x1)
    comptime GREEN = WGPUColorWriteMask(0x2)
    comptime BLUE = WGPUColorWriteMask(0x4)
    comptime ALPHA = WGPUColorWriteMask(0x8)
    comptime ALL = WGPUColorWriteMask(0xF)

    def __or__(self, rhs: WGPUColorWriteMask) -> WGPUColorWriteMask:
        return WGPUColorWriteMask(self.value | rhs.value)

    def __and__(self, rhs: WGPUColorWriteMask) -> WGPUColorWriteMask:
        return WGPUColorWriteMask(self.value & rhs.value)

    def __invert__(self) -> WGPUColorWriteMask:
        return WGPUColorWriteMask(~self.value)

    def __eq__(self, rhs: WGPUColorWriteMask) -> Bool:
        return self.value == rhs.value


@fieldwise_init
struct WGPUMapMode(TrivialRegisterPassable):
    var value: UInt64

    comptime NONE = WGPUMapMode(0)
    comptime READ = WGPUMapMode(0x1)
    comptime WRITE = WGPUMapMode(0x2)

    def __or__(self, rhs: WGPUMapMode) -> WGPUMapMode:
        return WGPUMapMode(self.value | rhs.value)

    def __and__(self, rhs: WGPUMapMode) -> WGPUMapMode:
        return WGPUMapMode(self.value & rhs.value)

    def __eq__(self, rhs: WGPUMapMode) -> Bool:
        return self.value == rhs.value


@fieldwise_init
struct WGPUShaderStage(TrivialRegisterPassable):
    var value: UInt64

    comptime NONE = WGPUShaderStage(0)
    comptime VERTEX = WGPUShaderStage(0x1)
    comptime FRAGMENT = WGPUShaderStage(0x2)
    comptime COMPUTE = WGPUShaderStage(0x4)

    def __or__(self, rhs: WGPUShaderStage) -> WGPUShaderStage:
        return WGPUShaderStage(self.value | rhs.value)

    def __and__(self, rhs: WGPUShaderStage) -> WGPUShaderStage:
        return WGPUShaderStage(self.value & rhs.value)

    def __eq__(self, rhs: WGPUShaderStage) -> Bool:
        return self.value == rhs.value


@fieldwise_init
struct WGPUTextureUsage(TrivialRegisterPassable):
    var value: UInt64

    comptime NONE = WGPUTextureUsage(0)
    comptime COPY_SRC = WGPUTextureUsage(0x01)
    comptime COPY_DST = WGPUTextureUsage(0x02)
    comptime TEXTURE_BINDING = WGPUTextureUsage(0x04)
    comptime STORAGE_BINDING = WGPUTextureUsage(0x08)
    comptime RENDER_ATTACHMENT = WGPUTextureUsage(0x10)
    comptime TRANSIENT_ATTACHMENT = WGPUTextureUsage(0x20)

    def __or__(self, rhs: WGPUTextureUsage) -> WGPUTextureUsage:
        return WGPUTextureUsage(self.value | rhs.value)

    def __and__(self, rhs: WGPUTextureUsage) -> WGPUTextureUsage:
        return WGPUTextureUsage(self.value & rhs.value)

    def __invert__(self) -> WGPUTextureUsage:
        return WGPUTextureUsage(~self.value)

    def __eq__(self, rhs: WGPUTextureUsage) -> Bool:
        return self.value == rhs.value

    def contains(self, flag: WGPUTextureUsage) -> Bool:
        return (self.value & flag.value) == flag.value
