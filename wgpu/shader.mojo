"""
wgpu.shader — ShaderModule RAII wrapper.
"""

from wgpu._ffi.lib import WGPULib
from wgpu._ffi.types import OpaquePtr, WGPUDeviceHandle, WGPUShaderModuleHandle


struct ShaderModule(Movable):
    """RAII wrapper around a WGPUShaderModule."""

    var _lib:    WGPULib
    var _handle: WGPUShaderModuleHandle

    def __init__(
        out self,
        var lib: WGPULib,
        handle: WGPUShaderModuleHandle,
    ):
        self._lib    = lib^
        self._handle = handle

    def __init__(out self, *, deinit take: Self):
        self._lib    = take._lib^
        self._handle = take._handle

    def __del__(deinit self):
        self._lib.shader_module_release(self._handle)

    def handle(self) -> WGPUShaderModuleHandle:
        return self._handle
