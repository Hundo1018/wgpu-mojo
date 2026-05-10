"""
Tests/test_pipeline_layout.mojo — Tests for PipelineLayout creation.
Requires GPU hardware.
"""

from std.testing import assert_true
from wgpu.device import Device
from wgpu.instance import Instance
from wgpu._ffi.types import WGPUShaderStage
from wgpu._ffi.structs import (
    WGPUBindGroupLayoutEntry, WGPUBindGroupLayoutDescriptor,
    WGPUBufferBindingLayout, WGPUSamplerBindingLayout,
    WGPUTextureBindingLayout, WGPUStorageTextureBindingLayout,
    WGPUStringView,
)


def create_test_device() raises -> Device:
    var instance = Instance()
    var adapter = instance.request_adapter()
    return adapter.request_device()


def test_create_empty_pipeline_layout() raises:
    """PipelineLayout with no bind group layouts should succeed."""
    var device = create_test_device()
    var pl     = device.create_pipeline_layout(List[OpaquePointer[MutExternalOrigin]](), "empty_pl")
    assert_true(pl)


def test_create_pipeline_layout_with_bgl() raises:
    """PipelineLayout referencing one BindGroupLayout should succeed."""
    var device = create_test_device()

    var bgl_desc = WGPUBindGroupLayoutDescriptor(
        OpaquePointer[MutExternalOrigin](unsafe_from_address=0), WGPUStringView.null_view(), UInt(0),
        UnsafePointer[WGPUBindGroupLayoutEntry, MutExternalOrigin](unsafe_from_address=0)
    )
    var bgl = device.create_bind_group_layout(bgl_desc)

    var pl = device.create_pipeline_layout(bgl, "pl_with_bgl")
    assert_true(pl)


def main() raises:
    test_create_empty_pipeline_layout()
    test_create_pipeline_layout_with_bgl()
    print("test_pipeline_layout: ALL PASSED")
