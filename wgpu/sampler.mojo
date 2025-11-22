"""
wgpu.sampler — Sampler RAII wrapper.
"""

from std.memory import ArcPointer
from wgpu._ffi.lib import WGPULib
from wgpu._ffi.types import OpaquePtr, WGPUSamplerHandle
from wgpu._ffi.structs import WGPUStringView, str_to_sv
from wgpu._ffi.handles import SamplerHandle


struct Sampler(Movable):
    """RAII wrapper around a WGPUSampler."""

    var _lib:    ArcPointer[WGPULib]
    var _handle: WGPUSamplerHandle

    def __init__(out self, lib: ArcPointer[WGPULib], handle: WGPUSamplerHandle):
        self._lib    = lib
        self._handle = handle

    def __init__(out self, *, deinit take: Self):
        self._lib    = take._lib^
        self._handle = take._handle

    def __del__(deinit self):
        self._lib[].sampler_release(self._handle)

    def handle(self) -> SamplerHandle:
        return SamplerHandle(self._handle)

    def set_label(self, label: String):
        var sv = str_to_sv(label) if label.byte_length() > 0 else WGPUStringView.null_view()
        self._lib[].sampler_set_label(self._handle, sv)
