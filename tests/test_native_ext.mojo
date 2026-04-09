"""
tests/test_native_ext.mojo — Unit tests for wgpu-native extension types.
Tests NativeSType, NativeFeature, LogLevel, InstanceBackend, InstanceFlag, etc.
No GPU required.
"""

from testing import assert_equal, assert_true, assert_false
from wgpu._native import (
    WGPUNativeSType, WGPUNativeFeature, WGPULogLevel,
    WGPUInstanceBackend, WGPUInstanceFlag,
    WGPUInstanceExtras,
)
from wgpu._ffi.types import OpaquePtr
from wgpu._ffi.structs import WGPUChainedStruct, WGPUStringView


def test_native_stype_values():
    # DeviceExtras starts at 0x00030001 in wgpu-native
    assert_equal(WGPUNativeSType.DeviceExtras, UInt32(0x00030001))
    assert_equal(WGPUNativeSType.InstanceExtras, UInt32(0x00030006))


def test_log_level_values():
    assert_equal(WGPULogLevel.Off, UInt32(0))
    assert_equal(WGPULogLevel.Error, UInt32(1))
    assert_equal(WGPULogLevel.Warn, UInt32(2))
    assert_equal(WGPULogLevel.Info, UInt32(3))
    assert_equal(WGPULogLevel.Debug, UInt32(4))
    assert_equal(WGPULogLevel.Trace, UInt32(5))


def test_instance_backend_bitflags():
    var vulkan = WGPUInstanceBackend.VULKAN
    var gl     = WGPUInstanceBackend.GL
    var combined = vulkan | gl
    assert_true(combined.contains(vulkan))
    assert_true(combined.contains(gl))
    assert_false(combined.contains(WGPUInstanceBackend.DX12))
    # Verify raw values
    assert_equal(WGPUInstanceBackend.VULKAN.value, UInt64(1 << 0))
    assert_equal(WGPUInstanceBackend.GL.value, UInt64(1 << 1))
    assert_equal(WGPUInstanceBackend.METAL.value, UInt64(1 << 2))
    assert_equal(WGPUInstanceBackend.DX12.value, UInt64(1 << 3))
    assert_equal(WGPUInstanceBackend.DX11.value, UInt64(1 << 4))


def test_instance_flag_bitflags():
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


def test_native_feature_values():
    assert_equal(WGPUNativeFeature.PushConstants, UInt32(0x00030001))
    assert_equal(WGPUNativeFeature.TextureAdapterSpecificFormatFeatures, UInt32(0x00030002))


def test_instance_extras_construction():
    var sv = WGPUStringView.null_view()
    var chain = WGPUChainedStruct(OpaquePtr(), WGPUNativeSType.InstanceExtras)
    var extras = WGPUInstanceExtras(
        chain,
        WGPUInstanceBackend.VULKAN.value,
        WGPUInstanceFlag.DEFAULT.value,
        UInt32(0),   # dx12_shader_compiler
        UInt32(0),   # gles3_minor_version
        UInt32(0),   # gl_fence_behaviour
        sv,          # dxc_path
        UInt32(0),   # dxc_max_shader_model
        UInt32(0),   # dx12_presentation_system
        OpaquePtr(), # budget_for_device_creation
        OpaquePtr(), # budget_for_device_loss
    )
    assert_equal(extras.chain.stype, WGPUNativeSType.InstanceExtras)
    assert_equal(extras.backends, WGPUInstanceBackend.VULKAN.value)

