"""
wgpu.descriptors — Builder helpers that eliminate null-field boilerplate.

Replace verbose WGPUBindGroupLayoutEntry construction with named factories:

    # Before (7 parameters with null-filled sub-structs):
    WGPUBindGroupLayoutEntry(
        null_opaque(), binding, WGPUShaderStage.COMPUTE.value, UInt32(0),
        WGPUBufferBindingLayout(null_opaque(), WGPUBufferBindingType.Storage, UInt32(0), UInt64(0)),
        WGPUSamplerBindingLayout(null_opaque(), UInt32(0)),
        WGPUTextureBindingLayout(null_opaque(), UInt32(0), UInt32(0), UInt32(0)),
        WGPUStorageTextureBindingLayout(null_opaque(), UInt32(0), UInt32(0), UInt32(0)),
    )

    # After (one readable call):
    BGL.buffer_storage(binding=0, visibility=ShaderStage.COMPUTE)
"""

from wgpu._ffi.structs import (
    WGPUBindGroupLayoutEntry,
    WGPUBufferBindingLayout,
    WGPUSamplerBindingLayout,
    WGPUTextureBindingLayout,
    WGPUStorageTextureBindingLayout,
)
from wgpu._ffi.types import (
    WGPUBufferBindingType, WGPUSamplerBindingType, WGPUTextureSampleType,
    WGPUStorageTextureAccess, WGPUTextureFormat, WGPUTextureViewDimension,
    WGPUShaderStage,
)
from wgpu._ffi.nulls import null_opaque


# ---------------------------------------------------------------------------
# Null sub-structs — used internally to fill unused binding slots
# ---------------------------------------------------------------------------

def _null_buffer_layout() -> WGPUBufferBindingLayout:
    return WGPUBufferBindingLayout(null_opaque(), UInt32(0), UInt32(0), UInt64(0))

def _null_sampler_layout() -> WGPUSamplerBindingLayout:
    return WGPUSamplerBindingLayout(null_opaque(), UInt32(0))

def _null_texture_layout() -> WGPUTextureBindingLayout:
    return WGPUTextureBindingLayout(null_opaque(), UInt32(0), UInt32(0), UInt32(0))

def _null_storage_texture_layout() -> WGPUStorageTextureBindingLayout:
    return WGPUStorageTextureBindingLayout(null_opaque(), UInt32(0), UInt32(0), UInt32(0))


# ---------------------------------------------------------------------------
# BGL — BindGroupLayoutEntry builder
# ---------------------------------------------------------------------------

struct BGL:
    """
    Factory methods for WGPUBindGroupLayoutEntry.

    Each method fills ONLY the relevant sub-struct; all others are zeroed.
    No more null_opaque() / UInt32(0) boilerplate.
    """

    @staticmethod
    def buffer_uniform(
        binding: UInt32,
        visibility: UInt64 = WGPUShaderStage.VERTEX.value | WGPUShaderStage.FRAGMENT.value,
        min_binding_size: UInt64 = 0,
    ) -> WGPUBindGroupLayoutEntry:
        return WGPUBindGroupLayoutEntry(
            null_opaque(), binding, visibility, UInt32(0),
            WGPUBufferBindingLayout(
                null_opaque(), WGPUBufferBindingType.Uniform, UInt32(0), min_binding_size
            ),
            _null_sampler_layout(), _null_texture_layout(), _null_storage_texture_layout(),
        )

    @staticmethod
    def buffer_storage(
        binding: UInt32,
        visibility: UInt64 = WGPUShaderStage.COMPUTE.value,
        read_only: Bool = False,
        min_binding_size: UInt64 = 0,
    ) -> WGPUBindGroupLayoutEntry:
        var buf_type = WGPUBufferBindingType.ReadOnlyStorage if read_only else WGPUBufferBindingType.Storage
        return WGPUBindGroupLayoutEntry(
            null_opaque(), binding, visibility, UInt32(0),
            WGPUBufferBindingLayout(null_opaque(), buf_type, UInt32(0), min_binding_size),
            _null_sampler_layout(), _null_texture_layout(), _null_storage_texture_layout(),
        )

    @staticmethod
    def sampler(
        binding: UInt32,
        visibility: UInt64 = WGPUShaderStage.FRAGMENT.value,
        sampler_type: UInt32 = WGPUSamplerBindingType.Filtering,
    ) -> WGPUBindGroupLayoutEntry:
        return WGPUBindGroupLayoutEntry(
            null_opaque(), binding, visibility, UInt32(0),
            _null_buffer_layout(),
            WGPUSamplerBindingLayout(null_opaque(), sampler_type),
            _null_texture_layout(), _null_storage_texture_layout(),
        )

    @staticmethod
    def texture_2d(
        binding: UInt32,
        visibility: UInt64 = WGPUShaderStage.FRAGMENT.value,
        sample_type: UInt32 = WGPUTextureSampleType.Float,
        multisampled: Bool = False,
    ) -> WGPUBindGroupLayoutEntry:
        return WGPUBindGroupLayoutEntry(
            null_opaque(), binding, visibility, UInt32(0),
            _null_buffer_layout(), _null_sampler_layout(),
            WGPUTextureBindingLayout(
                null_opaque(), sample_type,
                WGPUTextureViewDimension.D2,
                UInt32(1) if multisampled else UInt32(0),
            ),
            _null_storage_texture_layout(),
        )

    @staticmethod
    def storage_texture_2d(
        binding: UInt32,
        format: UInt32,
        visibility: UInt64 = WGPUShaderStage.COMPUTE.value,
        access: UInt32 = WGPUStorageTextureAccess.WriteOnly,
    ) -> WGPUBindGroupLayoutEntry:
        return WGPUBindGroupLayoutEntry(
            null_opaque(), binding, visibility, UInt32(0),
            _null_buffer_layout(), _null_sampler_layout(), _null_texture_layout(),
            WGPUStorageTextureBindingLayout(
                null_opaque(), access, format, WGPUTextureViewDimension.D2
            ),
        )

    @staticmethod
    def texture_depth_2d(
        binding: UInt32,
        visibility: UInt64 = WGPUShaderStage.FRAGMENT.value,
    ) -> WGPUBindGroupLayoutEntry:
        return WGPUBindGroupLayoutEntry(
            null_opaque(), binding, visibility, UInt32(0),
            _null_buffer_layout(), _null_sampler_layout(),
            WGPUTextureBindingLayout(
                null_opaque(), WGPUTextureSampleType.Depth,
                WGPUTextureViewDimension.D2, UInt32(0),
            ),
            _null_storage_texture_layout(),
        )
