"""
wgpu.sampler — Sampler RAII wrapper.
"""

from wgpu._ffi.lib import WGPULib
from wgpu._ffi.types import OpaquePtr, WGPUSamplerHandle


struct Sampler(Movable):
    """RAII wrapper around a WGPUSampler."""

    var _lib:    WGPULib
    var _handle: WGPUSamplerHandle

    def __init__(out self, var lib: WGPULib, handle: WGPUSamplerHandle):
        self._lib    = lib^
        self._handle = handle

    def __init__(out self, *, deinit take: Self):
        self._lib    = take._lib^
        self._handle = take._handle

    def __del__(deinit self):
        self._lib.sampler_release(self._handle)

    def handle(self) -> WGPUSamplerHandle:
        return self._handle
