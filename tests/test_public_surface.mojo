"""Tests/test_public_surface.mojo: what a consumer may import from the top-level `wgpu` package.

ludens-engine reached into `wgpu._ffi` and `wgpu._backend` for these names. They are now exported from `wgpu`, and
this test imports them only from there, so removing one from the public surface fails here."""

from std.testing import assert_equal, assert_true
from wgpu import (
    null_opaque, null_ptr, raw_alloc,
    WGPUTextureHandle, WGPUPassTimestampWrites,
    WGPUTextureFormat, WGPUTextureUsage, WGPUTextureAspect,
    WGPUStringView, str_to_sv, WGPUOrigin3D, WGPUColor,
    WGPUBlendComponent, WGPUBlendState, WGPUConstantEntry, WGPUColorTargetState,
    WGPUDepthStencilState, WGPUFragmentState, WGPUMultisampleState, WGPUPrimitiveState,
    WGPURenderPassColorAttachment, WGPURenderPassDepthStencilAttachment, WGPURenderPassDescriptor,
    WGPURenderPipelineDescriptor, WGPUStencilFaceState, WGPUVertexAttribute, WGPUVertexBufferLayout,
    WGPUVertexState, WGPUTextureViewDescriptor,
)


def test_null_pointers() raises:
    var o = null_opaque()
    assert_equal(Int(o), 0)
    var p = null_ptr[Int]()
    assert_equal(Int(p), 0)


def test_raw_alloc() raises:
    var p = raw_alloc[Int](4)
    for i in range(4):
        p[unsafe_offset=i] = i * 11
    assert_equal(p[unsafe_offset=3], 33)
    p.unsafe_free()


def test_string_view() raises:
    var s = String("hello")
    var sv = str_to_sv(s)
    assert_equal(Int(sv.length), 5)


def test_texture_enums() raises:
    var both = WGPUTextureUsage.RENDER_ATTACHMENT | WGPUTextureUsage.TEXTURE_BINDING
    assert_true(both.contains(WGPUTextureUsage.RENDER_ATTACHMENT))
    assert_true(both.contains(WGPUTextureUsage.TEXTURE_BINDING))


def main() raises:
    test_null_pointers()
    print("  PASS: test_null_pointers")
    test_raw_alloc()
    print("  PASS: test_raw_alloc")
    test_string_view()
    print("  PASS: test_string_view")
    test_texture_enums()
    print("  PASS: test_texture_enums")
    print("test_public_surface: ALL PASSED")
