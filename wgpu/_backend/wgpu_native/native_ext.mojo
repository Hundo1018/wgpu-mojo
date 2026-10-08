"""wgpu._native — wgpu-native extension types and structs."""

from wgpu._backend.wgpu_native.types import WGPUFlags

# ---------------------------------------------------------------------------
# WGPUNativeSType constants
# ---------------------------------------------------------------------------

struct WGPUNativeSType:
    """Values of wgpu.h's WGPUNativeSType. Checked against the header by check-struct-layout."""
    comptime DeviceExtras: UInt32 = 0x00030001
    comptime NativeLimits: UInt32 = 0x00030002
    comptime ShaderSourceGLSL: UInt32 = 0x00030003
    comptime InstanceExtras: UInt32 = 0x00030004
    comptime BindGroupEntryExtras: UInt32 = 0x00030005
    comptime BindGroupLayoutEntryExtras: UInt32 = 0x00030006
    comptime QuerySetDescriptorExtras: UInt32 = 0x00030007
    comptime SurfaceConfigurationExtras: UInt32 = 0x00030008
    comptime SurfaceSourceSwapChainPanel: UInt32 = 0x00030009
    comptime PrimitiveStateExtras: UInt32 = 0x0003000A
    comptime SamplerDescriptorExtras: UInt32 = 0x0003000B

# ---------------------------------------------------------------------------
# WGPUNativeFeature constants
# ---------------------------------------------------------------------------

struct WGPUNativeFeature:
    """Values of wgpu.h's WGPUNativeFeature. Checked against the header by check-struct-layout."""
    comptime Immediates: UInt32 = 0x00030001
    comptime TextureAdapterSpecificFormatFeatures: UInt32 = 0x00030002
    comptime MultiDrawIndirectCount: UInt32 = 0x00030004
    comptime VertexWritableStorage: UInt32 = 0x00030005
    comptime TextureBindingArray: UInt32 = 0x00030006
    comptime SampledTextureAndStorageBufferArrayNonUniformIndexing: UInt32 = 0x00030007
    comptime PipelineStatisticsQuery: UInt32 = 0x00030008
    comptime StorageResourceBindingArray: UInt32 = 0x00030009
    comptime PartiallyBoundBindingArray: UInt32 = 0x0003000A
    comptime TextureFormat16bitNorm: UInt32 = 0x0003000B
    comptime TextureCompressionAstcHdr: UInt32 = 0x0003000C
    comptime MappablePrimaryBuffers: UInt32 = 0x0003000E
    comptime BufferBindingArray: UInt32 = 0x0003000F
    comptime StorageTextureArrayNonUniformIndexing: UInt32 = 0x00030010
    comptime AddressModeClampToZero: UInt32 = 0x00030011
    comptime AddressModeClampToBorder: UInt32 = 0x00030012
    comptime PolygonModeLine: UInt32 = 0x00030013
    comptime PolygonModePoint: UInt32 = 0x00030014
    comptime ConservativeRasterization: UInt32 = 0x00030015
    comptime ClearTexture: UInt32 = 0x00030016
    comptime Multiview: UInt32 = 0x00030018
    comptime VertexAttribute64bit: UInt32 = 0x00030019
    comptime TextureFormatNv12: UInt32 = 0x0003001A
    comptime RayQuery: UInt32 = 0x0003001C
    comptime ShaderF64: UInt32 = 0x0003001D
    comptime ShaderI16: UInt32 = 0x0003001E
    comptime ShaderEarlyDepthTest: UInt32 = 0x00030020
    comptime Subgroup: UInt32 = 0x00030021
    comptime SubgroupVertex: UInt32 = 0x00030022
    comptime SubgroupBarrier: UInt32 = 0x00030023
    comptime TimestampQueryInsideEncoders: UInt32 = 0x00030024
    comptime TimestampQueryInsidePasses: UInt32 = 0x00030025
    comptime ShaderInt64: UInt32 = 0x00030026
    comptime ShaderFloat32Atomic: UInt32 = 0x00030027
    comptime TextureAtomic: UInt32 = 0x00030028
    comptime TextureFormatP010: UInt32 = 0x00030029
    comptime PipelineCache: UInt32 = 0x0003002B
    comptime ShaderInt64AtomicMinMax: UInt32 = 0x0003002C
    comptime ShaderInt64AtomicAllOps: UInt32 = 0x0003002D
    comptime TextureInt64Atomic: UInt32 = 0x00030030
    comptime ShaderBarycentrics: UInt32 = 0x00030037
    comptime SelectiveMultiview: UInt32 = 0x00030038
    comptime MultisampleArray: UInt32 = 0x0003003A
    comptime CooperativeMatrix: UInt32 = 0x0003003B
    comptime ShaderPerVertex: UInt32 = 0x0003003C
    comptime ShaderDrawIndex: UInt32 = 0x0003003D
    comptime AccelerationStructureBindingArray: UInt32 = 0x0003003E
    comptime MemoryDecorationCoherent: UInt32 = 0x0003003F
    comptime MemoryDecorationVolatile: UInt32 = 0x00030040

# ---------------------------------------------------------------------------
# WGPUShaderRuntimeChecks bitflags (uint64_t) — wgpuDeviceCreateShaderModuleTrusted
# ---------------------------------------------------------------------------

struct WGPUShaderRuntimeChecks:
    comptime None_: UInt64 = 0x0000000000000000
    comptime BoundsChecks: UInt64 = 0x0000000000000001
    comptime ForceLoopBounding: UInt64 = 0x0000000000000002
    comptime RayQueryInitializationTracking: UInt64 = 0x0000000000000004
    comptime TaskShaderDispatchTracking: UInt64 = 0x0000000000000008
    comptime MeshShaderPrimitiveIndicesClamp: UInt64 = 0x0000000000000010
    comptime ALL: UInt64 = 0x000000000000001F

# ---------------------------------------------------------------------------
# WGPULogLevel constants
# ---------------------------------------------------------------------------

struct WGPULogLevel:
    comptime Off: UInt32   = 0
    comptime Error: UInt32 = 1
    comptime Warn: UInt32  = 2
    comptime Info: UInt32  = 3
    comptime Debug: UInt32 = 4
    comptime Trace: UInt32 = 5

# ---------------------------------------------------------------------------
# WGPUInstanceBackend bitflags  (uint64_t)
# ---------------------------------------------------------------------------

@fieldwise_init
struct WGPUInstanceBackend(TrivialRegisterPassable):
    var value: UInt64

    comptime ALL        = WGPUInstanceBackend(0)
    comptime VULKAN     = WGPUInstanceBackend(1 << 0)
    comptime GL         = WGPUInstanceBackend(1 << 1)
    comptime METAL      = WGPUInstanceBackend(1 << 2)
    comptime DX12       = WGPUInstanceBackend(1 << 3)
    comptime BROWSER    = WGPUInstanceBackend(1 << 5)
    comptime PRIMARY    = WGPUInstanceBackend((1 << 0) | (1 << 2) | (1 << 3) | (1 << 5))
    comptime SECONDARY  = WGPUInstanceBackend(1 << 1)

    def __or__(self, rhs: WGPUInstanceBackend) -> WGPUInstanceBackend:
        return WGPUInstanceBackend(self.value | rhs.value)

    def __and__(self, rhs: WGPUInstanceBackend) -> WGPUInstanceBackend:
        return WGPUInstanceBackend(self.value & rhs.value)

    def __eq__(self, rhs: WGPUInstanceBackend) -> Bool:
        return self.value == rhs.value

    def contains(self, flag: WGPUInstanceBackend) -> Bool:
        return (self.value & flag.value) == flag.value

# ---------------------------------------------------------------------------
# WGPUInstanceFlag bitflags (uint64_t)
# ---------------------------------------------------------------------------

@fieldwise_init
struct WGPUInstanceFlag(TrivialRegisterPassable):
    var value: UInt64

    comptime EMPTY       = WGPUInstanceFlag(0)
    comptime DEBUG       = WGPUInstanceFlag(1 << 0)
    comptime VALIDATION  = WGPUInstanceFlag(1 << 1)
    comptime DISCARD_HAL_LABELS = WGPUInstanceFlag(1 << 2)
    comptime ALLOW_UNDERLYING_NONCOMPLIANT_ADAPTER = WGPUInstanceFlag(1 << 3)
    comptime GPU_BASED_VALIDATION = WGPUInstanceFlag(1 << 4)
    comptime VALIDATION_INDIRECT_CALL = WGPUInstanceFlag(1 << 5)
    comptime AUTOMATIC_TIMESTAMP_NORMALIZATION = WGPUInstanceFlag(1 << 6)
    comptime DEFAULT     = WGPUInstanceFlag(1 << 24)
    comptime DEBUGGING   = WGPUInstanceFlag(1 << 25)
    comptime ADVANCED_DEBUGGING = WGPUInstanceFlag(1 << 26)
    comptime WITH_ENV    = WGPUInstanceFlag(1 << 27)

    def __or__(self, rhs: WGPUInstanceFlag) -> WGPUInstanceFlag:
        return WGPUInstanceFlag(self.value | rhs.value)

    def __and__(self, rhs: WGPUInstanceFlag) -> WGPUInstanceFlag:
        return WGPUInstanceFlag(self.value & rhs.value)

    def __eq__(self, rhs: WGPUInstanceFlag) -> Bool:
        return self.value == rhs.value

    def contains(self, flag: WGPUInstanceFlag) -> Bool:
        return (self.value & flag.value) == flag.value

# ---------------------------------------------------------------------------
# Native extension structs
# ---------------------------------------------------------------------------

from wgpu._backend.wgpu_native.structs import WGPUChainedStruct, WGPUStringView

@fieldwise_init
struct NativeDisplayHandleData(TrivialRegisterPassable):
    """The union in WGPUNativeDisplayHandle, sized for its largest member.

    Xlib/Xcb use (pointer, screen); Wayland uses only the pointer.
    """
    var connection: OpaquePointer[MutUntrackedOrigin]  # Display* / xcb_connection_t* / wl_display*
    var screen:     Int32                              # unused for Wayland


@fieldwise_init
struct WGPUNativeDisplayHandle(TrivialRegisterPassable):
    var type_: UInt32  # WGPUNativeDisplayHandleType; 0 = None
    var data:  NativeDisplayHandleData


@fieldwise_init
struct WGPUInstanceExtras:
    var chain:                  WGPUChainedStruct
    var backends:               UInt64  # WGPUInstanceBackend
    var flags:                  UInt64  # WGPUInstanceFlag
    var dx12_shader_compiler:   UInt32
    var gles3_minor_version:    UInt32
    var gl_fence_behaviour:     UInt32
    var dxc_path:               WGPUStringView
    var dxc_max_shader_model:   UInt32
    var dx12_presentation_system: UInt32
    var budget_for_device_creation: OpaquePointer[MutUntrackedOrigin]  # nullable
    var budget_for_device_loss: OpaquePointer[MutUntrackedOrigin]      # nullable
    var display_handle: WGPUNativeDisplayHandle


@fieldwise_init
struct WGPUDeviceExtras:
    var chain:      WGPUChainedStruct
    var trace_path: WGPUStringView


@fieldwise_init
struct WGPUNativeLimits:
    var chain:                              WGPUChainedStruct
    var max_non_sampler_bindings:           UInt32
    var max_binding_array_elements_per_shader_stage: UInt32
    var max_binding_array_sampler_elements_per_shader_stage: UInt32
    var max_multiview_view_count:           UInt32


@fieldwise_init
struct WGPUInstanceEnumerateAdapterOptions:
    var next_in_chain: OpaquePointer[MutUntrackedOrigin]  # WGPUChainedStruct* nullable
    var backends:      UInt64    # WGPUInstanceBackend


# ---------------------------------------------------------------------------
# wgpu-native extension structs (report, extras)
# ---------------------------------------------------------------------------

@fieldwise_init
struct WGPURegistryReport(TrivialRegisterPassable):
    var num_allocated: UInt
    var num_kept_from_user: UInt
    var num_released_from_user: UInt
    var element_size: UInt


@fieldwise_init
struct WGPUHubReport(TrivialRegisterPassable):
    var adapters: WGPURegistryReport
    var devices: WGPURegistryReport
    var queues: WGPURegistryReport
    var pipeline_layouts: WGPURegistryReport
    var shader_modules: WGPURegistryReport
    var bind_group_layouts: WGPURegistryReport
    var bind_groups: WGPURegistryReport
    var command_buffers: WGPURegistryReport
    var render_bundles: WGPURegistryReport
    var render_pipelines: WGPURegistryReport
    var compute_pipelines: WGPURegistryReport
    var pipeline_caches: WGPURegistryReport
    var query_sets: WGPURegistryReport
    var buffers: WGPURegistryReport
    var textures: WGPURegistryReport
    var texture_views: WGPURegistryReport
    var samplers: WGPURegistryReport


@fieldwise_init
struct WGPUGlobalReport:
    var surfaces: WGPURegistryReport
    var hub: WGPUHubReport


@fieldwise_init
struct WGPUBindGroupEntryExtras:
    var chain:            WGPUChainedStruct
    var buffers:          Pointer[OpaquePointer[MutUntrackedOrigin], MutUntrackedOrigin]  # WGPUBuffer*
    var buffer_count:     UInt
    var samplers:         Pointer[OpaquePointer[MutUntrackedOrigin], MutUntrackedOrigin]  # WGPUSampler*
    var sampler_count:    UInt
    var texture_views:    Pointer[OpaquePointer[MutUntrackedOrigin], MutUntrackedOrigin]  # WGPUTextureView*
    var texture_view_count: UInt


@fieldwise_init
struct WGPUBindGroupLayoutEntryExtras:
    var chain: WGPUChainedStruct
    var count: UInt32


@fieldwise_init
struct WGPUQuerySetDescriptorExtras:
    var chain:                      WGPUChainedStruct
    var pipeline_statistics:        Pointer[UInt32, MutUntrackedOrigin]
    var pipeline_statistic_count:   UInt


@fieldwise_init
struct WGPUSurfaceConfigurationExtras:
    var chain:                  WGPUChainedStruct
    var desired_maximum_frame_latency: UInt32


@fieldwise_init
struct WGPUPrimitiveStateExtras:
    var chain:                      WGPUChainedStruct
    var polygon_mode:               UInt32
    var conservative:               UInt32  # WGPUBool


@fieldwise_init
struct WGPUSamplerDescriptorExtras:
    var chain:                WGPUChainedStruct
    var sampler_border_color: UInt32  # WGPUSamplerBorderColor


@fieldwise_init
struct WGPUImageSubresourceRange(TrivialRegisterPassable):
    """Argument of wgpuCommandEncoderClearTexture."""
    var aspect:            UInt32  # WGPUTextureAspect
    var base_mip_level:    UInt32
    var mip_level_count:   UInt32
    var base_array_layer:  UInt32
    var array_layer_count: UInt32
