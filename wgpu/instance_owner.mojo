"""
Wgpu.instance_owner — Shared owner for WGPULib + WGPUInstance.
"""

from std.memory import ArcPointer
from wgpu._ffi.lib import WGPULib
from wgpu._ffi.types import WGPUInstanceHandle


struct InstanceOwner(Movable):
    """Owns the dynamic library handle and raw WGPUInstance."""

    var _lib: ArcPointer[WGPULib]
    var _inst: WGPUInstanceHandle

    def __init__(out self, lib: ArcPointer[WGPULib], inst: WGPUInstanceHandle):
        self._lib = lib
        self._inst = inst

    def __init__(out self, *, deinit take: Self):
        self._lib = take._lib^
        self._inst = take._inst

    def __del__(deinit self):
        self._lib[].instance_release(self._inst)

    def lib(self) -> ArcPointer[WGPULib]:
        return self._lib

    def handle(self) -> WGPUInstanceHandle:
        return self._inst
