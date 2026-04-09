"""
tests/test_structs.mojo — Unit tests for FFI struct construction and layout.
No GPU required.
"""

from testing import assert_equal, assert_true, assert_not_equal
from wgpu._ffi.types import (
    OpaquePtr, WGPU_STRLEN, WGPU_WHOLE_SIZE, WGPU_LIMIT_U32_UNDEFINED,
    WGPUBufferUsage, WGPUMapMode, WGPUTextureUsage, WGPUShaderStage,
)
from wgpu._ffi.structs import (
    WGPUStringView, WGPUChainedStruct, WGPUFuture, WGPUFutureWaitInfo,
    WGPUExtent3D, WGPUOrigin3D, WGPUColor, WGPUBlendComponent, WGPUBlendState,
    WGPULimits, wgpu_limits_default,
    str_to_sv,
)


def test_stringview_null():
    var sv = WGPUStringView.null_view()
    assert_equal(sv.length, WGPU_STRLEN)
    assert_false(Bool(sv.data))


def test_stringview_from_string():
    var s = String("hello")
    var sv = str_to_sv(s)
    assert_equal(sv.length, UInt(5))
    assert_true(Bool(sv.data))


def test_chained_struct_construction():
    var cs = WGPUChainedStruct(OpaquePtr(), UInt32(1))
    assert_equal(cs.stype, UInt32(1))
    assert_false(Bool(cs.next))


def test_future_construction():
    var f = WGPUFuture(UInt64(42))
    assert_equal(f.id, UInt64(42))


def test_future_wait_info():
    var f = WGPUFuture(UInt64(7))
    var w = WGPUFutureWaitInfo(f, UInt32(0))
    assert_equal(w.future.id, UInt64(7))
    assert_equal(w.completed, UInt32(0))


def test_extent3d():
    var e = WGPUExtent3D(UInt32(256), UInt32(128), UInt32(1))
    assert_equal(e.width, UInt32(256))
    assert_equal(e.height, UInt32(128))
    assert_equal(e.depth_or_array_layers, UInt32(1))


def test_origin3d():
    var o = WGPUOrigin3D(UInt32(0), UInt32(0), UInt32(0))
    assert_equal(o.x, UInt32(0))


def test_color():
    var c = WGPUColor(0.1, 0.2, 0.3, 1.0)
    assert_equal(c.a, 1.0)


def test_blend_state():
    var bc = WGPUBlendComponent(UInt32(0), UInt32(2), UInt32(1))  # Add, One, Zero
    var bs = WGPUBlendState(bc, bc)
    assert_equal(bs.color.operation, UInt32(0))


def test_limits_default():
    var lim = wgpu_limits_default()
    assert_equal(lim.max_texture_dimension_1d, WGPU_LIMIT_U32_UNDEFINED)
    assert_equal(lim.max_buffer_size, UInt64.MAX)
    assert_equal(lim.max_compute_workgroups_per_dimension, WGPU_LIMIT_U32_UNDEFINED)


def test_buffer_usage_bitflag_value():
    assert_equal(WGPUBufferUsage.Storage.value, UInt64(0x0080))
    assert_equal(WGPUBufferUsage.CopySrc.value, UInt64(0x0004))
    var combined = WGPUBufferUsage.Storage | WGPUBufferUsage.CopyDst
    assert_equal(combined.value, WGPUBufferUsage.Storage.value | WGPUBufferUsage.CopyDst.value)


def test_stringview_equality():
    var s1 = String("test")
    var s2 = String("test")
    var sv1 = str_to_sv(s1)
    var sv2 = str_to_sv(s2)
    assert_equal(sv1.length, sv2.length)
