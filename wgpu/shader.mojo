"""
ShaderModule RAII wrapper.
"""

from std.memory import ArcPointer
from wgpu._backend.wgpu_native.loader import WGPULib
from wgpu._backend.wgpu_native.nulls import null_opaque
from wgpu._backend.wgpu_native.types import WGPUDeviceHandle, WGPUShaderModuleHandle, WGPUInstanceHandle, WGPUCallbackMode
from wgpu._backend.wgpu_native.structs import WGPUStringView, str_to_sv
from wgpu._backend.wgpu_native.handles import ShaderModuleHandle
from wgpu._backend.wgpu_native.alloc_guard import AllocGuard


struct ShaderModule(Movable, Boolable):
    """RAII wrapper around a WGPUShaderModule."""

    var _lib:      ArcPointer[WGPULib]
    var _handle:   WGPUShaderModuleHandle
    var _instance: WGPUInstanceHandle

    def __init__(
        out self,
        lib: ArcPointer[WGPULib],
        handle: WGPUShaderModuleHandle,
        instance: WGPUInstanceHandle,
    ):
        self._lib      = lib
        self._handle   = handle
        self._instance = instance

    def __init__(out self, *, deinit move: Self):
        self._lib      = move._lib^
        self._handle   = move._handle
        self._instance = move._instance

    def __deinit__(deinit self):
        self._lib[].shader_module_release(self._handle)

    def clone(self) -> Self:
        """Share ownership of this GPU object via `wgpuShaderModuleAddRef`.

        A refcount bump, not a GPU-side copy: both wrappers refer to the same
        object and each releases on drop, so it survives until the last one
        goes away.
        """
        self._lib[].shader_module_add_ref(self._handle)
        return Self(self._lib, self._handle, self._instance)

    def handle(self) -> ShaderModuleHandle:
        return ShaderModuleHandle(self._handle)

    def __bool__(self) -> Bool:
        return Int(self._handle) != 0

