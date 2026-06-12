"""wgpu._backend.wgpu_native.handles - strongly typed handle wrappers (newtype pattern)."""

from wgpu._backend.wgpu_native.nulls import null_opaque


@fieldwise_init
struct AdapterHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePointer[MutUntrackedOrigin]

    @staticmethod
    def null() -> AdapterHandle:
        return AdapterHandle(null_opaque())


@fieldwise_init
struct DeviceHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePointer[MutUntrackedOrigin]

    @staticmethod
    def null() -> DeviceHandle:
        return DeviceHandle(null_opaque())


@fieldwise_init
struct QueueHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePointer[MutUntrackedOrigin]

    @staticmethod
    def null() -> QueueHandle:
        return QueueHandle(null_opaque())


@fieldwise_init
struct BufferHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePointer[MutUntrackedOrigin]

    @staticmethod
    def null() -> BufferHandle:
        return BufferHandle(null_opaque())


@fieldwise_init
struct TextureHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePointer[MutUntrackedOrigin]

    @staticmethod
    def null() -> TextureHandle:
        return TextureHandle(null_opaque())


@fieldwise_init
struct TextureViewHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePointer[MutUntrackedOrigin]

    @staticmethod
    def null() -> TextureViewHandle:
        return TextureViewHandle(null_opaque())


@fieldwise_init
struct SamplerHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePointer[MutUntrackedOrigin]

    @staticmethod
    def null() -> SamplerHandle:
        return SamplerHandle(null_opaque())


@fieldwise_init
struct ShaderModuleHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePointer[MutUntrackedOrigin]

    @staticmethod
    def null() -> ShaderModuleHandle:
        return ShaderModuleHandle(null_opaque())


@fieldwise_init
struct BindGroupLayoutHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePointer[MutUntrackedOrigin]

    @staticmethod
    def null() -> BindGroupLayoutHandle:
        return BindGroupLayoutHandle(null_opaque())


@fieldwise_init
struct BindGroupHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePointer[MutUntrackedOrigin]

    @staticmethod
    def null() -> BindGroupHandle:
        return BindGroupHandle(null_opaque())


@fieldwise_init
struct PipelineLayoutHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePointer[MutUntrackedOrigin]

    @staticmethod
    def null() -> PipelineLayoutHandle:
        return PipelineLayoutHandle(null_opaque())


@fieldwise_init
struct ComputePipelineHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePointer[MutUntrackedOrigin]

    @staticmethod
    def null() -> ComputePipelineHandle:
        return ComputePipelineHandle(null_opaque())


@fieldwise_init
struct RenderPipelineHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePointer[MutUntrackedOrigin]

    @staticmethod
    def null() -> RenderPipelineHandle:
        return RenderPipelineHandle(null_opaque())


@fieldwise_init
struct CommandEncoderHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePointer[MutUntrackedOrigin]

    @staticmethod
    def null() -> CommandEncoderHandle:
        return CommandEncoderHandle(null_opaque())


@fieldwise_init
struct CommandBufferHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePointer[MutUntrackedOrigin]

    @staticmethod
    def null() -> CommandBufferHandle:
        return CommandBufferHandle(null_opaque())


@fieldwise_init
struct QuerySetHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePointer[MutUntrackedOrigin]

    @staticmethod
    def null() -> QuerySetHandle:
        return QuerySetHandle(null_opaque())


@fieldwise_init
struct SurfaceHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePointer[MutUntrackedOrigin]

    @staticmethod
    def null() -> SurfaceHandle:
        return SurfaceHandle(null_opaque())


@fieldwise_init
struct InstanceHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePointer[MutUntrackedOrigin]

    @staticmethod
    def null() -> InstanceHandle:
        return InstanceHandle(null_opaque())


@fieldwise_init
struct ComputePassEncoderHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePointer[MutUntrackedOrigin]

    @staticmethod
    def null() -> ComputePassEncoderHandle:
        return ComputePassEncoderHandle(null_opaque())


@fieldwise_init
struct RenderPassEncoderHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePointer[MutUntrackedOrigin]

    @staticmethod
    def null() -> RenderPassEncoderHandle:
        return RenderPassEncoderHandle(null_opaque())
