"""
Unit tests for FFI struct construction and layout.
No GPU required.
"""

from wgpu._ffi.nulls import null_opaque, null_ptr, null_any_ptr
from std.testing import assert_equal, assert_true, assert_false
from wgpu._ffi.types import (
    WGPU_STRLEN, WGPU_WHOLE_SIZE, WGPU_LIMIT_U32_UNDEFINED,
    WGPUBufferUsage,
)
from wgpu._ffi.structs import (
    WGPUStringView, WGPUChainedStruct, WGPUFuture,
    WGPUExtent3D, WGPUOrigin3D, WGPUColor, WGPUBlendComponent, WGPUBlendState,
    WGPULimits, wgpu_limits_default,
    WGPUCompatibilityModeLimits, WGPUInstanceLimits,
    WGPUSupportedInstanceFeatures, WGPUSupportedWGSLLanguageFeatures,
    WGPUShaderModuleDescriptorSpirV,
    WGPURenderPassMaxDrawCount, WGPUSurfaceColorManagement,
    WGPUTextureComponentSwizzle, WGPUTextureComponentSwizzleDescriptor,
    WGPUShaderSourceGLSL, WGPUShaderDefine,
    str_to_sv,
)


def _struct_size[T: AnyType]() -> Int:
    """sizeof(T) via pointer arithmetic — mirrors wgpu.gpu._elem_size."""
    var p = null_ptr[T]()
    return Int(p.unsafe_offset(1)) - Int(p)


def test_instance_struct_layout() raises:
    """Byte sizes must match webgpu.h — a mismatch silently corrupts every read.

    Reference values are gcc `sizeof()` against ffi/include/webgpu/webgpu.h.
    WGPUSupportedInstanceFeatures previously carried a spurious nextInChain
    field and WGPUInstanceLimits was missing timedWaitAnyMaxCount; both were
    16 bytes off / short until these assertions existed.
    """
    assert_equal(_struct_size[WGPUSupportedInstanceFeatures](), 16)
    assert_equal(_struct_size[WGPUSupportedWGSLLanguageFeatures](), 16)
    assert_equal(_struct_size[WGPUInstanceLimits](), 16)
    assert_equal(_struct_size[WGPUCompatibilityModeLimits](), 32)


def test_chained_descriptor_layout() raises:
    """Chained-descriptor byte sizes, against gcc sizeof() on the headers."""
    assert_equal(_struct_size[WGPURenderPassMaxDrawCount](), 24)
    assert_equal(_struct_size[WGPUSurfaceColorManagement](), 24)
    assert_equal(_struct_size[WGPUTextureComponentSwizzle](), 16)
    assert_equal(_struct_size[WGPUTextureComponentSwizzleDescriptor](), 32)
    assert_equal(_struct_size[WGPUShaderSourceGLSL](), 56)
    assert_equal(_struct_size[WGPUShaderDefine](), 32)
    assert_equal(_struct_size[WGPUShaderModuleDescriptorSpirV](), 32)


def test_stringview_null() raises:
    var sv = WGPUStringView.null_view()
    assert_equal(sv.length, WGPU_STRLEN)
    assert_true(sv.data == null_any_ptr())


def test_stringview_from_string() raises:
    var s = String("hello")
    var sv = str_to_sv(s)
    assert_equal(sv.length, UInt(5))
    assert_true(sv.data != null_any_ptr())


def test_chained_struct() raises:
    var cs = WGPUChainedStruct(null_opaque(), UInt32(1))
    assert_equal(cs.stype, UInt32(1))
    assert_true(cs.next == null_ptr[NoneType]())


def test_future() raises:
    var f = WGPUFuture(UInt64(42))
    assert_equal(f.id, UInt64(42))


def test_extent3d() raises:
    var e = WGPUExtent3D(UInt32(256), UInt32(128), UInt32(1))
    assert_equal(e.width, UInt32(256))
    assert_equal(e.height, UInt32(128))
    assert_equal(e.depth_or_array_layers, UInt32(1))


def test_color() raises:
    var c = WGPUColor(0.1, 0.2, 0.3, 1.0)
    assert_equal(c.a, 1.0)


def test_blend_state() raises:
    var bc = WGPUBlendComponent(UInt32(0), UInt32(2), UInt32(1))
    var bs = WGPUBlendState(bc, bc)
    assert_equal(bs.color.operation, UInt32(0))


def test_limits_default() raises:
    var lim = wgpu_limits_default()
    assert_equal(lim.max_texture_dimension_1d, WGPU_LIMIT_U32_UNDEFINED)
    assert_equal(lim.max_buffer_size, UInt64.MAX)


def test_buffer_usage_value() raises:
    assert_equal(WGPUBufferUsage.STORAGE.value, UInt64(0x0080))
    assert_equal(WGPUBufferUsage.COPY_SRC.value, UInt64(0x0004))
    var combined = WGPUBufferUsage.STORAGE | WGPUBufferUsage.COPY_DST
    assert_equal(combined.value, WGPUBufferUsage.STORAGE.value | WGPUBufferUsage.COPY_DST.value)


def main() raises:
    test_stringview_null()
    print("  PASS: test_stringview_null")
    test_stringview_from_string()
    print("  PASS: test_stringview_from_string")
    test_chained_struct()
    print("  PASS: test_chained_struct")
    test_future()
    print("  PASS: test_future")
    test_extent3d()
    print("  PASS: test_extent3d")
    test_color()
    print("  PASS: test_color")
    test_blend_state()
    print("  PASS: test_blend_state")
    test_limits_default()
    print("  PASS: test_limits_default")
    test_buffer_usage_value()
    print("  PASS: test_buffer_usage_value")
    test_instance_struct_layout()
    print("  PASS: test_instance_struct_layout")
    test_chained_descriptor_layout()
    print("  PASS: test_chained_descriptor_layout")
    print("All 11 tests passed!")
