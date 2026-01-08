"""
tests/test_types.mojo — Unit tests for FFI type definitions.
No GPU required.
"""

from std.testing import assert_equal, assert_true, assert_false
from wgpu._ffi.types import (
    OpaquePtr,
    WGPU_FALSE, WGPU_TRUE, WGPU_STRLEN, WGPU_WHOLE_SIZE,
    WGPU_LIMIT_U32_UNDEFINED, WGPU_LIMIT_U64_UNDEFINED,
    WGPU_MIP_LEVEL_COUNT_UNDEFINED, WGPU_ARRAY_LAYER_COUNT_UNDEFINED,
    WGPUAdapterType, WGPUBackendType,
    WGPUCallbackMode, WGPUCompareFunction,
    WGPULoadOp, WGPUStoreOp,
    WGPUTextureFormat, WGPUSType,
    WGPUBufferUsage, WGPUColorWriteMask, WGPUMapMode, WGPUShaderStage, WGPUTextureUsage,
    WGPUPowerPreference,
)


def test_constants() raises:
    assert_equal(WGPU_FALSE, UInt32(0))
    assert_equal(WGPU_TRUE, UInt32(1))
    assert_equal(WGPU_STRLEN, UInt.MAX)
    assert_equal(WGPU_WHOLE_SIZE, UInt64.MAX)
    assert_equal(WGPU_LIMIT_U32_UNDEFINED, UInt32.MAX)
    assert_equal(WGPU_LIMIT_U64_UNDEFINED, UInt64.MAX)


def test_adapter_type_enum() raises:
    assert_equal(WGPUAdapterType.DiscreteGPU, UInt32(1))
    assert_equal(WGPUAdapterType.IntegratedGPU, UInt32(2))
    assert_equal(WGPUAdapterType.CPU, UInt32(3))
    assert_equal(WGPUAdapterType.Unknown, UInt32(4))


def test_backend_type_enum() raises:
    assert_equal(WGPUBackendType.Undefined, UInt32(0))
    assert_equal(WGPUBackendType.Null, UInt32(1))
    assert_equal(WGPUBackendType.Vulkan, UInt32(6))


def test_texture_format_enum() raises:
    assert_equal(WGPUTextureFormat.Undefined, UInt32(0x00000000))
    assert_equal(WGPUTextureFormat.RGBA8Unorm, UInt32(0x00000016))
    assert_equal(WGPUTextureFormat.Depth32Float, UInt32(0x00000030))


def test_texture_usage_bitflag() raises:
    var none_flag = WGPUTextureUsage(UInt64(0))
    var copy_src = WGPUTextureUsage.COPY_SRC
    var copy_dst = WGPUTextureUsage.COPY_DST
    var combined = copy_src | copy_dst
    assert_true(combined.contains(copy_src))
    assert_true(combined.contains(copy_dst))
    assert_false(none_flag.contains(copy_src))


def test_buffer_usage_bitflag() raises:
    var usage = WGPUBufferUsage.STORAGE | WGPUBufferUsage.COPY_SRC
    assert_true(usage.contains(WGPUBufferUsage.STORAGE))
    assert_true(usage.contains(WGPUBufferUsage.COPY_SRC))
    assert_false(usage.contains(WGPUBufferUsage.VERTEX))


def test_shader_stage_bitflag() raises:
    var all_stages = WGPUShaderStage.VERTEX | WGPUShaderStage.FRAGMENT | WGPUShaderStage.COMPUTE
    assert_true(all_stages.contains(WGPUShaderStage.COMPUTE))
    assert_true(all_stages.contains(WGPUShaderStage.VERTEX))
    assert_true(all_stages.contains(WGPUShaderStage.FRAGMENT))


def test_map_mode_bitflag() raises:
    assert_true(WGPUMapMode.READ.contains(WGPUMapMode.READ))
    assert_false(WGPUMapMode.READ.contains(WGPUMapMode.WRITE))


def test_color_write_mask_bitflag() raises:
    var all_mask = WGPUColorWriteMask.ALL
    assert_true(all_mask.contains(WGPUColorWriteMask.RED))
    assert_true(all_mask.contains(WGPUColorWriteMask.GREEN))
    assert_true(all_mask.contains(WGPUColorWriteMask.BLUE))
    assert_true(all_mask.contains(WGPUColorWriteMask.ALPHA))


def test_power_preference_enum() raises:
    assert_equal(WGPUPowerPreference.Undefined, UInt32(0))
    assert_equal(WGPUPowerPreference.LowPower, UInt32(1))
    assert_equal(WGPUPowerPreference.HighPerformance, UInt32(2))


def test_stype_enum() raises:
    assert_equal(WGPUSType.ShaderSourceSPIRV, UInt32(0x00000001))
    assert_equal(WGPUSType.ShaderSourceWGSL, UInt32(0x00000002))


def test_opaque_ptr_null() raises:
    var p = OpaquePtr()
    assert_false(Bool(p))


def main() raises:
    test_constants()
    print("  PASS: test_constants")
    test_adapter_type_enum()
    print("  PASS: test_adapter_type_enum")
    test_backend_type_enum()
    print("  PASS: test_backend_type_enum")
    test_texture_format_enum()
    print("  PASS: test_texture_format_enum")
    test_texture_usage_bitflag()
    print("  PASS: test_texture_usage_bitflag")
    test_buffer_usage_bitflag()
    print("  PASS: test_buffer_usage_bitflag")
    test_shader_stage_bitflag()
    print("  PASS: test_shader_stage_bitflag")
    test_map_mode_bitflag()
    print("  PASS: test_map_mode_bitflag")
    test_color_write_mask_bitflag()
    print("  PASS: test_color_write_mask_bitflag")
    test_power_preference_enum()
    print("  PASS: test_power_preference_enum")
    test_stype_enum()
    print("  PASS: test_stype_enum")
    test_opaque_ptr_null()
    print("  PASS: test_opaque_ptr_null")
    print("All 12 tests passed!")
