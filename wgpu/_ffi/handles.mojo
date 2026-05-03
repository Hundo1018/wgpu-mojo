"""wgpu._ffi.handles - strongly typed handle wrappers (newtype pattern)."""




@fieldwise_init
struct AdapterHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePointer[MutExternalOrigin]

    @staticmethod
    def null() -> AdapterHandle:
        return AdapterHandle(OpaquePointer[MutExternalOrigin](unsafe_from_address=0))


@fieldwise_init
struct DeviceHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePointer[MutExternalOrigin]

    @staticmethod
    def null() -> DeviceHandle:
        return DeviceHandle(OpaquePointer[MutExternalOrigin](unsafe_from_address=0))


@fieldwise_init
struct QueueHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePointer[MutExternalOrigin]

    @staticmethod
    def null() -> QueueHandle:
        return QueueHandle(OpaquePointer[MutExternalOrigin](unsafe_from_address=0))


@fieldwise_init
struct BufferHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePointer[MutExternalOrigin]

    @staticmethod
    def null() -> BufferHandle:
        return BufferHandle(OpaquePointer[MutExternalOrigin](unsafe_from_address=0))


@fieldwise_init
struct TextureHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePointer[MutExternalOrigin]

    @staticmethod
    def null() -> TextureHandle:
        return TextureHandle(OpaquePointer[MutExternalOrigin](unsafe_from_address=0))


@fieldwise_init
struct TextureViewHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePointer[MutExternalOrigin]

    @staticmethod
    def null() -> TextureViewHandle:
        return TextureViewHandle(OpaquePointer[MutExternalOrigin](unsafe_from_address=0))


@fieldwise_init
struct SamplerHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePointer[MutExternalOrigin]

    @staticmethod
    def null() -> SamplerHandle:
        return SamplerHandle(OpaquePointer[MutExternalOrigin](unsafe_from_address=0))


@fieldwise_init
struct ShaderModuleHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePointer[MutExternalOrigin]

    @staticmethod
    def null() -> ShaderModuleHandle:
        return ShaderModuleHandle(OpaquePointer[MutExternalOrigin](unsafe_from_address=0))


@fieldwise_init
struct BindGroupLayoutHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePointer[MutExternalOrigin]

    @staticmethod
    def null() -> BindGroupLayoutHandle:
        return BindGroupLayoutHandle(OpaquePointer[MutExternalOrigin](unsafe_from_address=0))


@fieldwise_init
struct BindGroupHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePointer[MutExternalOrigin]

    @staticmethod
    def null() -> BindGroupHandle:
        return BindGroupHandle(OpaquePointer[MutExternalOrigin](unsafe_from_address=0))


@fieldwise_init
struct PipelineLayoutHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePointer[MutExternalOrigin]

    @staticmethod
    def null() -> PipelineLayoutHandle:
        return PipelineLayoutHandle(OpaquePointer[MutExternalOrigin](unsafe_from_address=0))


@fieldwise_init
struct ComputePipelineHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePointer[MutExternalOrigin]

    @staticmethod
    def null() -> ComputePipelineHandle:
        return ComputePipelineHandle(OpaquePointer[MutExternalOrigin](unsafe_from_address=0))


@fieldwise_init
struct RenderPipelineHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePointer[MutExternalOrigin]

    @staticmethod
    def null() -> RenderPipelineHandle:
        return RenderPipelineHandle(OpaquePointer[MutExternalOrigin](unsafe_from_address=0))


@fieldwise_init
struct CommandEncoderHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePointer[MutExternalOrigin]

    @staticmethod
    def null() -> CommandEncoderHandle:
        return CommandEncoderHandle(OpaquePointer[MutExternalOrigin](unsafe_from_address=0))


@fieldwise_init
struct CommandBufferHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePointer[MutExternalOrigin]

    @staticmethod
    def null() -> CommandBufferHandle:
        return CommandBufferHandle(OpaquePointer[MutExternalOrigin](unsafe_from_address=0))


@fieldwise_init
struct QuerySetHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePointer[MutExternalOrigin]

    @staticmethod
    def null() -> QuerySetHandle:
        return QuerySetHandle(OpaquePointer[MutExternalOrigin](unsafe_from_address=0))


@fieldwise_init
struct SurfaceHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePointer[MutExternalOrigin]

    @staticmethod
    def null() -> SurfaceHandle:
        return SurfaceHandle(OpaquePointer[MutExternalOrigin](unsafe_from_address=0))


@fieldwise_init
struct InstanceHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePointer[MutExternalOrigin]

    @staticmethod
    def null() -> InstanceHandle:
        return InstanceHandle(OpaquePointer[MutExternalOrigin](unsafe_from_address=0))


@fieldwise_init
struct ComputePassEncoderHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePointer[MutExternalOrigin]

    @staticmethod
    def null() -> ComputePassEncoderHandle:
        return ComputePassEncoderHandle(OpaquePointer[MutExternalOrigin](unsafe_from_address=0))


@fieldwise_init
struct RenderPassEncoderHandle(TrivialRegisterPassable, Copyable):
    var raw: OpaquePointer[MutExternalOrigin]

    @staticmethod
    def null() -> RenderPassEncoderHandle:
        return RenderPassEncoderHandle(OpaquePointer[MutExternalOrigin](unsafe_from_address=0))
