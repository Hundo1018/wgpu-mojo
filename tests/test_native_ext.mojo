"""
tests/test_native_ext.mojo — Unit tests for wgpu-native extension types.
No GPU required.
"""

from std.testing import assert_equal, assert_true, assert_false
from wgpu._native import (
    WGPUNativeSType, WGPUNativeFeature, WGPULogLevel,
    WGPUInstanceBackend, WGPUInstanceFlag,
    WGPUInstanceExtras,
)
from wgpu._ffi.types import OpaquePtr
from wgpu._ffi.structs import WGPUChainedStruct, WGPUStringView


def test_native_stype_values() raises:
    assert_equal(WGPUNativeSType.DeviceExtras, UInt32(0x00030001))
    assert_equal(WGPUNativeSType.InstanceExtras, UInt32(0x00030006))


def test_log_level_values() raises:
    assert_equal(WGPULogLevel.Off, UInt32(0))
    assert_equal(WGPULogLevel.Error, UInt32(1))
    assert_equal(WGPULogLevel.Warn, UInt32(2))
    assert_equal(WGPULogLevel.Info, UInt32(3))
    assert_equal(WGPULogLevel.Debug, UInt32(4))
    assert_equal(WGPULogLevel.Trace, UInt32(5))


def test_instance_backend_bitflags() raises:
    var vulkan = WGPUInstanceBackend.VULKAN
    var gl     = WGPUInstanceBackend.GL
    var combined = vulkan | gl
    assert_true(combined.contains(vulkan))
    assert_true(combined.contains(gl))
    assert_false(combined.contains(WGPUInstanceBackend.DX12))
    assert_equal(WGPUInstanceBackend.VULKAN.value, UInt64(1 << 0))
    assert_equal(WGPUInstanceBackend.GL.value, UInt64(1 << 1))
    assert_equal(WGPUInstanceBackend.METAL.value, UInt64(1 << 2))
    assert_equal(WGPUInstanceBackend.DX12.value, UInt64(1 << 3))
    assert_equal(WGPUInstanceBackend.DX11.value, UInt64(1 << 4))


def test_instance_flag_bitflags() raises:
    var empty = WGPUInstanceFlag.EMPTY
    assert_equal(empty.value, UInt64(0))
    var debug = WGPUInstanceFlag.DEBUG
    assert_equal(debug.value, UInt64(1))
    var default_flag = WGPUInstanceFlag.DEFAULT
    assert_equal(default_flag.value, UInt64(1 << 24))
    var combined = debug | WGPUInstanceFlag.VALIDATION
    assert_true(combined.contains(debug))
    assert_true(combined.contains(WGPUInstanceFlag.VALIDATION))
    assert_false(combined.contains(WGPUInstanceFlag.DEFAULT))


def test_native_feature_values() raises:
    assert_equal(WGPUNativeFeature.PushConstants, UInt32(0x00030001))
    assert_equal(WGPUNativeFeature.TextureAdapterSpecificFormatFeatures, UInt32(0x00030002))


def test_instance_extras_construction() raises:
    var sv = WGPUStringView.null_view()
    var chain = WGPUChainedStruct(OpaquePtr(), WGPUNativeSType.InstanceExtras)
    var extras = WGPUInstanceExtras(
        chain,
        WGPUInstanceBackend.VULKAN.value,
        WGPUInstanceFlag.DEFAULT.value,
        UInt32(0), UInt32(0), UInt32(0),
        sv, UInt32(0), UInt32(0),
        OpaquePtr(), OpaquePtr(),
    )
    assert_equal(extras.chain.stype, WGPUNativeSType.InstanceExtras)
    assert_equal(extras.backends, WGPUInstanceBackend.VULKAN.value)


def main() raises:
    test_native_stype_values()
    print("  PASS: test_native_stype_values")
    test_log_level_values()
    print("  PASS: test_log_level_values")
    test_instance_backend_bitflags()
    print("  PASS: test_instance_backend_bitflags")
    test_instance_flag_bitflags()
    print("  PASS: test_instance_flag_bitflags")
    test_native_feature_values()
    print("  PASS: test_native_feature_values")
    test_instance_extras_construction()
    print("  PASS: test_instance_extras_construction")
    print("All 6 tests passed!")
