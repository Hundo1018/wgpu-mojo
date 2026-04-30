"""wgpu._ffi.handles - strongly typed handle wrappers (newtype pattern)."""

from wgpu._ffi.types import OpaquePtr


@fieldwise_init
struct AdapterHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePtr

    @staticmethod
    def null() -> AdapterHandle:
        return AdapterHandle(OpaquePtr(unsafe_from_address=0))


@fieldwise_init
struct DeviceHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePtr

    @staticmethod
    def null() -> DeviceHandle:
        return DeviceHandle(OpaquePtr(unsafe_from_address=0))


@fieldwise_init
struct QueueHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePtr

    @staticmethod
    def null() -> QueueHandle:
        return QueueHandle(OpaquePtr(unsafe_from_address=0))


@fieldwise_init
struct BufferHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePtr

    @staticmethod
    def null() -> BufferHandle:
        return BufferHandle(OpaquePtr(unsafe_from_address=0))


@fieldwise_init
struct TextureHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePtr

    @staticmethod
    def null() -> TextureHandle:
        return TextureHandle(OpaquePtr(unsafe_from_address=0))


@fieldwise_init
struct TextureViewHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePtr

    @staticmethod
    def null() -> TextureViewHandle:
        return TextureViewHandle(OpaquePtr(unsafe_from_address=0))


@fieldwise_init
struct SamplerHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePtr

    @staticmethod
    def null() -> SamplerHandle:
        return SamplerHandle(OpaquePtr(unsafe_from_address=0))


@fieldwise_init
struct ShaderModuleHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePtr

    @staticmethod
    def null() -> ShaderModuleHandle:
        return ShaderModuleHandle(OpaquePtr(unsafe_from_address=0))


@fieldwise_init
struct BindGroupLayoutHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePtr

    @staticmethod
    def null() -> BindGroupLayoutHandle:
        return BindGroupLayoutHandle(OpaquePtr(unsafe_from_address=0))


@fieldwise_init
struct BindGroupHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePtr

    @staticmethod
    def null() -> BindGroupHandle:
        return BindGroupHandle(OpaquePtr(unsafe_from_address=0))


@fieldwise_init
struct PipelineLayoutHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePtr

    @staticmethod
    def null() -> PipelineLayoutHandle:
        return PipelineLayoutHandle(OpaquePtr(unsafe_from_address=0))


@fieldwise_init
struct ComputePipelineHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePtr

    @staticmethod
    def null() -> ComputePipelineHandle:
        return ComputePipelineHandle(OpaquePtr(unsafe_from_address=0))


@fieldwise_init
struct RenderPipelineHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePtr

    @staticmethod
    def null() -> RenderPipelineHandle:
        return RenderPipelineHandle(OpaquePtr(unsafe_from_address=0))


@fieldwise_init
struct CommandEncoderHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePtr

    @staticmethod
    def null() -> CommandEncoderHandle:
        return CommandEncoderHandle(OpaquePtr(unsafe_from_address=0))


@fieldwise_init
struct CommandBufferHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePtr

    @staticmethod
    def null() -> CommandBufferHandle:
        return CommandBufferHandle(OpaquePtr(unsafe_from_address=0))


@fieldwise_init
struct QuerySetHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePtr

    @staticmethod
    def null() -> QuerySetHandle:
        return QuerySetHandle(OpaquePtr(unsafe_from_address=0))


@fieldwise_init
struct SurfaceHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePtr

    @staticmethod
    def null() -> SurfaceHandle:
        return SurfaceHandle(OpaquePtr(unsafe_from_address=0))


@fieldwise_init
struct InstanceHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePtr

    @staticmethod
    def null() -> InstanceHandle:
        return InstanceHandle(OpaquePtr(unsafe_from_address=0))


@fieldwise_init
struct ComputePassEncoderHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePtr

    @staticmethod
    def null() -> ComputePassEncoderHandle:
        return ComputePassEncoderHandle(OpaquePtr(unsafe_from_address=0))


@fieldwise_init
struct RenderPassEncoderHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePtr

    @staticmethod
    def null() -> RenderPassEncoderHandle:
        return RenderPassEncoderHandle(OpaquePtr(unsafe_from_address=0))
