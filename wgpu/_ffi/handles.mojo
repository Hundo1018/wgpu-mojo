"""wgpu._ffi.handles — strongly typed handle wrappers (newtype pattern).

These wrappers are zero-cost containers around ``OpaquePtr`` that improve type
checking at call sites. Existing alias-based handle types remain in
``wgpu._ffi.types`` for backward compatibility while the migration is in
progress.
"""

from wgpu._ffi.types import OpaquePtr


@fieldwise_init
struct AdapterHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePtr

    @staticmethod
    def null() -> AdapterHandle:
        return AdapterHandle(OpaquePtr())


@fieldwise_init
struct DeviceHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePtr

    @staticmethod
    def null() -> DeviceHandle:
        return DeviceHandle(OpaquePtr())


@fieldwise_init
struct QueueHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePtr

    @staticmethod
    def null() -> QueueHandle:
        return QueueHandle(OpaquePtr())


@fieldwise_init
struct BufferHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePtr

    @staticmethod
    def null() -> BufferHandle:
        return BufferHandle(OpaquePtr())


@fieldwise_init
struct TextureHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePtr

    @staticmethod
    def null() -> TextureHandle:
        return TextureHandle(OpaquePtr())


@fieldwise_init
struct TextureViewHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePtr

    @staticmethod
    def null() -> TextureViewHandle:
        return TextureViewHandle(OpaquePtr())


@fieldwise_init
struct SamplerHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePtr

    @staticmethod
    def null() -> SamplerHandle:
        return SamplerHandle(OpaquePtr())


@fieldwise_init
struct ShaderModuleHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePtr

    @staticmethod
    def null() -> ShaderModuleHandle:
        return ShaderModuleHandle(OpaquePtr())


@fieldwise_init
struct BindGroupLayoutHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePtr

    @staticmethod
    def null() -> BindGroupLayoutHandle:
        return BindGroupLayoutHandle(OpaquePtr())


@fieldwise_init
struct BindGroupHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePtr

    @staticmethod
    def null() -> BindGroupHandle:
        return BindGroupHandle(OpaquePtr())


@fieldwise_init
struct PipelineLayoutHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePtr

    @staticmethod
    def null() -> PipelineLayoutHandle:
        return PipelineLayoutHandle(OpaquePtr())


@fieldwise_init
struct ComputePipelineHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePtr

    @staticmethod
    def null() -> ComputePipelineHandle:
        return ComputePipelineHandle(OpaquePtr())


@fieldwise_init
struct RenderPipelineHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePtr

    @staticmethod
    def null() -> RenderPipelineHandle:
        return RenderPipelineHandle(OpaquePtr())


@fieldwise_init
struct CommandEncoderHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePtr

    @staticmethod
    def null() -> CommandEncoderHandle:
        return CommandEncoderHandle(OpaquePtr())


@fieldwise_init
struct CommandBufferHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePtr

    @staticmethod
    def null() -> CommandBufferHandle:
        return CommandBufferHandle(OpaquePtr())


@fieldwise_init
struct QuerySetHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePtr

    @staticmethod
    def null() -> QuerySetHandle:
        return QuerySetHandle(OpaquePtr())


@fieldwise_init
struct SurfaceHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePtr

    @staticmethod
    def null() -> SurfaceHandle:
        return SurfaceHandle(OpaquePtr())