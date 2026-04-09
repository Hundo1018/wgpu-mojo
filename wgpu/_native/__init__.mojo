"""wgpu._native — wgpu-native extension types and structs."""

from wgpu._ffi.types import OpaquePtr, WGPUFlags

# ---------------------------------------------------------------------------
# WGPUNativeSType constants
# ---------------------------------------------------------------------------

struct WGPUNativeSType:
    comptime DeviceExtras: UInt32     = 0x00030001
    comptime NativeLimits: UInt32     = 0x00030002
    comptime PipelineLayoutExtras: UInt32 = 0x00030003
    comptime ShaderSourceGLSL: UInt32 = 0x00030004
    comptime InstanceExtras: UInt32   = 0x00030006
    comptime BindGroupEntryExtras: UInt32 = 0x00030007
    comptime BindGroupLayoutEntryExtras: UInt32 = 0x00030008
    comptime QuerySetDescriptorExtras: UInt32 = 0x00030009
    comptime SurfaceConfigurationExtras: UInt32 = 0x0003000A

# ---------------------------------------------------------------------------
# WGPUNativeFeature constants
# ---------------------------------------------------------------------------

struct WGPUNativeFeature:
    comptime PushConstants: UInt32     = 0x00030001
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
    comptime UniformBufferAndStorageTextureArrayNonUniformIndexing: UInt32 = 0x00030010
    comptime PolygonModeLine: UInt32 = 0x00030013
    comptime PolygonModePoint: UInt32 = 0x00030014
    comptime ConservativeRasterization: UInt32 = 0x00030015
    comptime SpirvShaderPassthrough: UInt32 = 0x00030017
    comptime VertexAttribute64bit: UInt32 = 0x00030019
    comptime RayQuery: UInt32 = 0x0003001C
    comptime ShaderF64: UInt32 = 0x0003001D
    comptime ShaderI16: UInt32 = 0x0003001E
    comptime ShaderInt64: UInt32 = 0x00030026

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
    comptime DX11       = WGPUInstanceBackend(1 << 4)
    comptime BROWSER    = WGPUInstanceBackend(1 << 5)
    comptime PRIMARY    = WGPUInstanceBackend((1 << 0) | (1 << 2) | (1 << 3) | (1 << 5))
    comptime SECONDARY  = WGPUInstanceBackend((1 << 1) | (1 << 4))

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
    comptime DEFAULT     = WGPUInstanceFlag(1 << 24)
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

from wgpu._ffi.structs import WGPUChainedStruct, WGPUStringView

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
    var budget_for_device_creation: OpaquePtr  # nullable
    var budget_for_device_loss: OpaquePtr      # nullable


@fieldwise_init
struct WGPUDeviceExtras:
    var chain:      WGPUChainedStruct
    var trace_path: WGPUStringView


@fieldwise_init
struct WGPUNativeLimits:
    var chain:                              WGPUChainedStruct
    var max_push_constant_size:             UInt32
    var max_non_sampler_bindings:           UInt32
    var max_binding_array_elements_per_shader_stage: UInt32


@fieldwise_init
struct WGPUInstanceEnumerateAdapterOptions:
    var next_in_chain: OpaquePtr  # WGPUChainedStruct* nullable
    var backends:      UInt64    # WGPUInstanceBackend


# ---------------------------------------------------------------------------
# wgpu-native extension structs (report, push constants, extras)
# ---------------------------------------------------------------------------

@fieldwise_init
struct WGPURegistryReport(TrivialRegisterPassable):
    var num_allocated: UInt
    var num_kept_from_user: UInt
    var num_released_from_user: UInt
    var num_destroyed_from_user: UInt
    var num_error: UInt
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
    var backend_type: UInt32
    var vulkan: WGPUHubReport
    var metal: WGPUHubReport
    var dx12: WGPUHubReport
    var gl: WGPUHubReport


@fieldwise_init
struct WGPUPushConstantRange(TrivialRegisterPassable):
    var stages: UInt64   # WGPUShaderStage
    var start: UInt32
    var end: UInt32


@fieldwise_init
struct WGPUPipelineLayoutExtras:
    var chain: WGPUChainedStruct
    var push_constant_range_count: UInt
    var push_constant_ranges: UnsafePointer[WGPUPushConstantRange, MutExternalOrigin]


@fieldwise_init
struct WGPUBindGroupEntryExtras:
    var chain:            WGPUChainedStruct
    var buffers:          UnsafePointer[OpaquePtr, MutExternalOrigin]  # WGPUBuffer*
    var buffer_count:     UInt
    var samplers:         UnsafePointer[OpaquePtr, MutExternalOrigin]  # WGPUSampler*
    var sampler_count:    UInt
    var texture_views:    UnsafePointer[OpaquePtr, MutExternalOrigin]  # WGPUTextureView*
    var texture_view_count: UInt


@fieldwise_init
struct WGPUBindGroupLayoutEntryExtras:
    var chain: WGPUChainedStruct
    var count: UInt32


@fieldwise_init
struct WGPUQuerySetDescriptorExtras:
    var chain:                      WGPUChainedStruct
    var pipeline_statistics:        UnsafePointer[UInt32, MutExternalOrigin]
    var pipeline_statistic_count:   UInt


@fieldwise_init
struct WGPUSurfaceConfigurationExtras:
    var chain:                  WGPUChainedStruct
    var maximum_frame_latency:  UInt32


@fieldwise_init
struct WGPUPrimitiveStateExtras:
    var chain:                      WGPUChainedStruct
    var polygon_mode:               UInt32
    var conservative_rasterization:  UInt32  # WGPUBool
