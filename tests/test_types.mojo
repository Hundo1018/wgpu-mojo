"""
tests/test_types.mojo — Unit tests for FFI type definitions.
Tests enum values, bitflag operations, handle types, and constants.
No GPU required.
"""

from testing import assert_equal, assert_true, assert_false, assert_not_equal
from wgpu._ffi.types import (
    OpaquePtr,
    WGPU_FALSE, WGPU_TRUE, WGPU_STRLEN, WGPU_WHOLE_SIZE,
    WGPU_LIMIT_U32_UNDEFINED, WGPU_LIMIT_U64_UNDEFINED,
    WGPU_MIP_LEVEL_COUNT_UNDEFINED, WGPU_ARRAY_LAYER_COUNT_UNDEFINED,
    WGPUAdapterType, WGPUAddressMode, WGPUBackendType,
    WGPUBlendFactor, WGPUBlendOperation, WGPUBufferBindingType,
    WGPUCallbackMode, WGPUCompareFunction, WGPUCullMode,
    WGPUFeatureName, WGPUFilterMode, WGPUFrontFace, WGPUIndexFormat,
    WGPULoadOp, WGPUMapAsyncStatus, WGPUMipmapFilterMode,
    WGPUPresentMode, WGPUPrimitiveTopology, WGPUQueryType,
    WGPURequestAdapterStatus, WGPURequestDeviceStatus,
    WGPUSamplerBindingType, WGPUStatus, WGPUSType,
    WGPUStorageTextureAccess, WGPUStoreOp,
    WGPUTextureAspect, WGPUTextureDimension,
    WGPUTextureFormat, WGPUTextureSampleType, WGPUTextureViewDimension,
    WGPUVertexFormat, WGPUVertexStepMode,
    WGPUBufferUsage, WGPUColorWriteMask, WGPUMapMode, WGPUShaderStage, WGPUTextureUsage,
    WGPUPowerPreference,
)


def test_constants():
    assert_equal(WGPU_FALSE, UInt32(0))
    assert_equal(WGPU_TRUE, UInt32(1))
    assert_equal(WGPU_STRLEN, UInt.MAX)
    assert_equal(WGPU_WHOLE_SIZE, UInt64.MAX)
    assert_equal(WGPU_LIMIT_U32_UNDEFINED, UInt32.MAX)
    assert_equal(WGPU_LIMIT_U64_UNDEFINED, UInt64.MAX)
    assert_equal(WGPU_MIP_LEVEL_COUNT_UNDEFINED, UInt32.MAX)
    assert_equal(WGPU_ARRAY_LAYER_COUNT_UNDEFINED, UInt32.MAX)


def test_adapter_type_enum():
    assert_equal(WGPUAdapterType.DiscreteGPU, UInt32(1))
    assert_equal(WGPUAdapterType.IntegratedGPU, UInt32(2))
    assert_equal(WGPUAdapterType.CPU, UInt32(3))
    assert_equal(WGPUAdapterType.Unknown, UInt32(4))


def test_address_mode_enum():
    assert_equal(WGPUAddressMode.Undefined, UInt32(0))
    assert_equal(WGPUAddressMode.ClampToEdge, UInt32(1))
    assert_equal(WGPUAddressMode.Repeat, UInt32(2))
    assert_equal(WGPUAddressMode.MirrorRepeat, UInt32(3))


def test_backend_type_enum():
    assert_equal(WGPUBackendType.Undefined, UInt32(0))
    assert_equal(WGPUBackendType.Null, UInt32(1))
    assert_equal(WGPUBackendType.WebGPU, UInt32(2))
    assert_equal(WGPUBackendType.D3D11, UInt32(3))
    assert_equal(WGPUBackendType.D3D12, UInt32(4))
    assert_equal(WGPUBackendType.Metal, UInt32(5))
    assert_equal(WGPUBackendType.Vulkan, UInt32(6))
    assert_equal(WGPUBackendType.OpenGL, UInt32(7))
    assert_equal(WGPUBackendType.OpenGLES, UInt32(8))


def test_blend_factor_enum():
    assert_equal(WGPUBlendFactor.Undefined, UInt32(0))
    assert_equal(WGPUBlendFactor.Zero, UInt32(1))
    assert_equal(WGPUBlendFactor.One, UInt32(2))


def test_callback_mode_enum():
    assert_equal(WGPUCallbackMode.WaitAnyOnly, UInt32(1))
    assert_equal(WGPUCallbackMode.AllowProcessEvents, UInt32(2))
    assert_equal(WGPUCallbackMode.AllowSpontaneous, UInt32(3))


def test_compare_function_enum():
    assert_equal(WGPUCompareFunction.Undefined, UInt32(0))
    assert_equal(WGPUCompareFunction.Never, UInt32(1))
    assert_equal(WGPUCompareFunction.Less, UInt32(2))
    assert_equal(WGPUCompareFunction.Equal, UInt32(3))


def test_load_store_op_enum():
    assert_equal(WGPULoadOp.Undefined, UInt32(0))
    assert_equal(WGPULoadOp.Load, UInt32(1))
    assert_equal(WGPULoadOp.Clear, UInt32(2))
    assert_equal(WGPUStoreOp.Undefined, UInt32(0))
    assert_equal(WGPUStoreOp.Store, UInt32(1))
    assert_equal(WGPUStoreOp.Discard, UInt32(2))


def test_texture_format_enum():
    # Spot-check key values from the enum
    assert_equal(WGPUTextureFormat.Undefined, UInt32(0x00000000))
    assert_equal(WGPUTextureFormat.RGBA8Unorm, UInt32(0x00000012))
    assert_equal(WGPUTextureFormat.Depth32Float, UInt32(0x0000002A))


def test_texture_usage_bitflag():
    var none_flag = WGPUTextureUsage(UInt64(0))
    var copy_src = WGPUTextureUsage.CopySrc
    var copy_dst = WGPUTextureUsage.CopyDst
    var combined = copy_src | copy_dst

    assert_true(combined.contains(copy_src))
    assert_true(combined.contains(copy_dst))
    assert_false(none_flag.contains(copy_src))

    var tb = WGPUTextureUsage.TextureBinding
    var only_src = combined & ~tb
    assert_true(only_src.contains(copy_src))
    assert_false(only_src.contains(tb))


def test_buffer_usage_bitflag():
    var usage = WGPUBufferUsage.Storage | WGPUBufferUsage.CopySrc
    assert_true(usage.contains(WGPUBufferUsage.Storage))
    assert_true(usage.contains(WGPUBufferUsage.CopySrc))
    assert_false(usage.contains(WGPUBufferUsage.Vertex))


def test_shader_stage_bitflag():
    var all_stages = WGPUShaderStage.Vertex | WGPUShaderStage.Fragment | WGPUShaderStage.Compute
    assert_true(all_stages.contains(WGPUShaderStage.Compute))
    assert_true(all_stages.contains(WGPUShaderStage.Vertex))
    assert_true(all_stages.contains(WGPUShaderStage.Fragment))


def test_map_mode_bitflag():
    assert_true(WGPUMapMode.Read.contains(WGPUMapMode.Read))
    assert_false(WGPUMapMode.Read.contains(WGPUMapMode.Write))


def test_color_write_mask_bitflag():
    var all_mask = WGPUColorWriteMask.All
    assert_true(all_mask.contains(WGPUColorWriteMask.Red))
    assert_true(all_mask.contains(WGPUColorWriteMask.Green))
    assert_true(all_mask.contains(WGPUColorWriteMask.Blue))
    assert_true(all_mask.contains(WGPUColorWriteMask.Alpha))


def test_power_preference_enum():
    assert_equal(WGPUPowerPreference.Undefined, UInt32(0))
    assert_equal(WGPUPowerPreference.LowPower, UInt32(1))
    assert_equal(WGPUPowerPreference.HighPerformance, UInt32(2))


def test_vertex_format_enum():
    assert_equal(WGPUVertexFormat.Float32, UInt32(0x0000001C))
    assert_equal(WGPUVertexFormat.Float32x2, UInt32(0x0000001D))


def test_stype_enum():
    assert_equal(WGPUSType.ShaderSourceSPIRV, UInt32(0x00000001))
    assert_equal(WGPUSType.ShaderSourceWGSL, UInt32(0x00000002))


def test_opaque_ptr_null():
    var p = OpaquePtr()
    assert_false(Bool(p))
