"""
Wgpu.pending — a non-blocking wgpu request.

`Pending` holds the heap slot a wgpu callback writes into. `ready()` lets
callbacks run without blocking and reports whether this one has; it is what a
frame-driven host (the web target, #14) calls once per frame. `wait()` blocks
and is native-only.

The typed requests built on it (`AdapterRequest`, `DeviceRequest`,
`MapRequest`, `WorkDoneRequest`, `ErrorScopeRequest`) live next to the object
that issues them.
"""

from std.memory import ArcPointer
from wgpu._ffi.lib import WGPULib
from wgpu._ffi.types import WGPUInstanceHandle, WGPUDeviceHandle
from wgpu._backend.wgpu_native.callbacks import CallbackResult


struct Pending[R: CallbackResult](Movable):
    var _lib: ArcPointer[WGPULib]
    var _instance: WGPUInstanceHandle
    var _device: WGPUDeviceHandle
    var _slot: Pointer[Self.R, MutUntrackedOrigin]

    def __init__(
        out self,
        lib: ArcPointer[WGPULib],
        instance: WGPUInstanceHandle,
        device: WGPUDeviceHandle,
        slot: Pointer[Self.R, MutUntrackedOrigin],
    ):
        self._lib = lib
        self._instance = instance
        self._device = device
        self._slot = slot

    def __init__(out self, *, deinit move: Self):
        self._lib = move._lib^
        self._instance = move._instance
        self._device = move._device
        self._slot = move._slot

    def __deinit__(deinit self):
        # The callback writes into the slot whenever it fires, so a request
        # dropped before then leaks its slot rather than risk a write into
        # freed memory.
        if self._slot[].done():
            self._slot.unsafe_free()

    def ready(self) -> Bool:
        """True once the callback has fired. Never blocks."""
        if self._slot[].done():
            return True
        self._lib[].pump(self._instance, self._device, False)
        return self._slot[].done()

    def wait(self) raises:
        """Block until the callback has fired. Native only."""
        self._lib[].wait_for(self._slot, self._instance, self._device)

    def result(self) raises -> Self.R:
        if not self._slot[].done():
            raise Error("wgpu request is still pending; check ready() first")
        return self._slot[]
