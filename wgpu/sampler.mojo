"""
wgpu.sampler — Sampler RAII wrapper.
"""

from std.memory import ArcPointer
from wgpu._ffi.lib import WGPULib
from wgpu._ffi.types import WGPUSamplerHandle
from wgpu._ffi.structs import WGPUStringView, str_to_sv
from wgpu._ffi.handles import SamplerHandle


struct Sampler(Movable, Boolable):
    """RAII wrapper around a WGPUSampler."""

    var _lib:    ArcPointer[WGPULib]
    var _handle: WGPUSamplerHandle

    def __init__(out self, lib: ArcPointer[WGPULib], handle: WGPUSamplerHandle):
        self._lib    = lib
        self._handle = handle

    def __init__(out self, *, deinit move: Self):
        self._lib    = move._lib^
        self._handle = move._handle

    def __del__(deinit self):
        self._lib[].sampler_release(self._handle)

    def handle(self) -> SamplerHandle:
        return SamplerHandle(self._handle)

    def __bool__(self) -> Bool:
        return Int(self._handle) != 0

