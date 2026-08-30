"""
wgpu.bind_group — BindGroupLayout and BindGroup RAII wrappers.
"""

from std.memory import ArcPointer
from wgpu._ffi.lib import WGPULib
from wgpu._ffi.types import (
    WGPUBindGroupHandle, WGPUBindGroupLayoutHandle,
)
from wgpu._ffi.structs import WGPUStringView, str_to_sv
from wgpu._ffi.handles import BindGroupHandle, BindGroupLayoutHandle


struct BindGroupLayout(Movable, Boolable):
    """RAII wrapper around a WGPUBindGroupLayout."""

    var _lib:    ArcPointer[WGPULib]
    var _handle: WGPUBindGroupLayoutHandle

    def __init__(out self, lib: ArcPointer[WGPULib], handle: WGPUBindGroupLayoutHandle):
        self._lib    = lib
        self._handle = handle

    def __init__(out self, *, deinit move: Self):
        self._lib    = move._lib^
        self._handle = move._handle

    def __deinit__(deinit self):
        self._lib[].bind_group_layout_release(self._handle)

    def clone(self) -> Self:
        """Share ownership of this GPU object via `wgpuBindGroupLayoutAddRef`.

        A refcount bump, not a GPU-side copy: both wrappers refer to the same
        object and each releases on drop, so it survives until the last one
        goes away.
        """
        self._lib[].bind_group_layout_add_ref(self._handle)
        return Self(self._lib, self._handle)

    def handle(self) -> BindGroupLayoutHandle:
        return BindGroupLayoutHandle(self._handle)

    def __bool__(self) -> Bool:
        return Int(self._handle) != 0

struct BindGroup(Movable, Boolable):
    """RAII wrapper around a WGPUBindGroup."""

    var _lib:    ArcPointer[WGPULib]
    var _handle: WGPUBindGroupHandle

    def __init__(out self, lib: ArcPointer[WGPULib], handle: WGPUBindGroupHandle):
        self._lib    = lib
        self._handle = handle

    def __init__(out self, *, deinit move: Self):
        self._lib    = move._lib^
        self._handle = move._handle

    def __deinit__(deinit self):
        self._lib[].bind_group_release(self._handle)

    def clone(self) -> Self:
        """Share ownership of this GPU object via `wgpuBindGroupAddRef`.

        A refcount bump, not a GPU-side copy: both wrappers refer to the same
        object and each releases on drop, so it survives until the last one
        goes away.
        """
        self._lib[].bind_group_add_ref(self._handle)
        return Self(self._lib, self._handle)

    def handle(self) -> BindGroupHandle:
        return BindGroupHandle(self._handle)

    def __bool__(self) -> Bool:
        return Int(self._handle) != 0

