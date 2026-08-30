"""
Tests/test_add_ref.mojo — Shared ownership via clone() (wgpu*AddRef).

clone() bumps the wgpu-native refcount instead of copying the GPU object, so a
clone must stay usable after the original is dropped. If AddRef were missing,
the first drop would release the object and the clone's handle would dangle —
these tests would crash or fail rather than quietly pass.

Requires GPU hardware.
"""

from wgpu._ffi.nulls import null_opaque
from std.testing import assert_true, assert_equal
from wgpu.device import Device
from wgpu.instance import Instance
from wgpu.shader import ShaderModule
from wgpu._ffi.types import WGPUShaderStage
from wgpu._ffi.structs import (
    WGPUBindGroupLayoutEntry, WGPUBufferBindingLayout,
    WGPUSamplerBindingLayout, WGPUTextureBindingLayout,
    WGPUStorageTextureBindingLayout,
)

comptime NOOP_WGSL = """
@compute @workgroup_size(1)
fn main() {}
"""


def create_test_device() raises -> Device:
    var instance = Instance()
    var adapter = instance.request_adapter()
    return adapter.request_device()


def make_bgl_entry(binding: UInt32) -> WGPUBindGroupLayoutEntry:
    return WGPUBindGroupLayoutEntry(
        null_opaque(),
        binding,
        WGPUShaderStage.COMPUTE.value,
        UInt32(0),
        WGPUBufferBindingLayout(null_opaque(), UInt32(3), UInt32(0), UInt64(0)),
        WGPUSamplerBindingLayout(null_opaque(), UInt32(0)),
        WGPUTextureBindingLayout(null_opaque(), UInt32(0), UInt32(0), UInt32(0)),
        WGPUStorageTextureBindingLayout(null_opaque(), UInt32(0), UInt32(0), UInt32(0)),
    )


def test_shader_module_outlives_original() raises:
    """A cloned ShaderModule must still build a pipeline after the original drops."""
    var device = create_test_device()
    var shader = device.create_shader_module_wgsl(NOOP_WGSL, "clone_src")
    assert_true(shader)
    var clone = shader.clone()
    _ = shader^          # original released here; the clone must keep it alive

    assert_true(clone)
    var entries: List[WGPUBindGroupLayoutEntry] = [make_bgl_entry(UInt32(0))]
    var bgl = device.create_bind_group_layout(entries)
    var pl = device.create_pipeline_layout(bgl)
    var pipeline = device.create_compute_pipeline(clone, "main", pl)
    assert_true(pipeline)
    _ = device^


def test_clone_shares_handle() raises:
    """clone() shares the handle rather than creating a second GPU object."""
    var device = create_test_device()
    var sampler = device.create_sampler(label="clone_sampler")
    var copy = sampler.clone()
    assert_equal(
        Int(sampler.handle().raw), Int(copy.handle().raw),
        "clone() must share the handle, not allocate a new object",
    )
    _ = sampler^
    assert_true(copy)    # survives the original's release
    _ = device^


def test_repeated_clone_and_drop() raises:
    """Many clone/drop cycles must not underflow the refcount."""
    var device = create_test_device()
    var entries: List[WGPUBindGroupLayoutEntry] = [make_bgl_entry(UInt32(0))]
    var bgl = device.create_bind_group_layout(entries)
    for _ in range(64):
        var c = bgl.clone()
        assert_true(c)
    assert_true(bgl)     # still alive after 64 clones came and went
    _ = device^


def main() raises:
    test_shader_module_outlives_original()
    print("  PASS: test_shader_module_outlives_original")
    test_clone_shares_handle()
    print("  PASS: test_clone_shares_handle")
    test_repeated_clone_and_drop()
    print("  PASS: test_repeated_clone_and_drop")
    print("test_add_ref: ALL PASSED")
