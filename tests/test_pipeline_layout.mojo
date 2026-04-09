"""
tests/test_pipeline_layout.mojo — Tests for PipelineLayout creation.
Requires GPU hardware.
"""

from testing import assert_true
from wgpu.gpu import request_adapter
from wgpu._ffi.types import OpaquePtr, WGPUShaderStage
from wgpu._ffi.structs import (
    WGPUBindGroupLayoutEntry, WGPUBindGroupLayoutDescriptor,
    WGPUBufferBindingLayout, WGPUSamplerBindingLayout,
    WGPUTextureBindingLayout, WGPUStorageTextureBindingLayout,
    WGPUPipelineLayoutDescriptor, WGPUStringView,
)


def test_create_empty_pipeline_layout() raises:
    """PipelineLayout with no bind group layouts should succeed."""
    var inst   = request_adapter()
    var device = inst.request_device()
    var pl     = device.create_pipeline_layout(List[OpaquePtr](), "empty_pl")
    assert_true(Bool(pl))
    device._lib.pipeline_layout_release(pl)


def test_create_pipeline_layout_with_bgl() raises:
    """PipelineLayout referencing one BindGroupLayout should succeed."""
    var inst   = request_adapter()
    var device = inst.request_device()

    # Empty BGL
    var bgl_desc = WGPUBindGroupLayoutDescriptor(
        OpaquePtr(), WGPUStringView.null_view(), UInt(0),
        UnsafePointer[WGPUBindGroupLayoutEntry, MutExternalOrigin]()
    )
    var bgl = device.create_bind_group_layout(bgl_desc)

    var pl = device.create_pipeline_layout(List[OpaquePtr](bgl), "pl_with_bgl")
    assert_true(Bool(pl))

    device._lib.pipeline_layout_release(pl)
    device._lib.bind_group_layout_release(bgl)
