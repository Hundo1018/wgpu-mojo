"""
Wgpu.web.boot — adapter and device setup, advanced one frame at a time.

    var boot = GPUBoot()
    # each frame:
    if not boot.step():
        return            # still waiting on the browser
    var device = boot.device()

A browser only runs wgpu callbacks after control returns to its event loop, so
setup that blocks (Instance.request_adapter, Adapter.request_device) cannot
work there. GPUBoot issues the async requests and checks them on each step.
"""

from wgpu.instance import Instance, AdapterRequest
from wgpu.adapter import Adapter, DeviceRequest
from wgpu.device import Device


struct GPUBoot(Movable):
    var instance: Instance
    var _adapter_req: Optional[AdapterRequest]
    var _adapter: Optional[Adapter]
    var _device_req: Optional[DeviceRequest]
    var _device: Optional[Device]
    var _label: String

    def __init__(out self, device_label: String = "wgpu") raises:
        self.instance = Instance()
        self._adapter_req = self.instance.request_adapter_async()
        self._adapter = None
        self._device_req = None
        self._device = None
        self._label = device_label

    def __init__(out self, *, deinit move: Self):
        self.instance = move.instance^
        self._adapter_req = move._adapter_req^
        self._adapter = move._adapter^
        self._device_req = move._device_req^
        self._device = move._device^
        self._label = move._label^

    def step(mut self) raises -> Bool:
        """Advance setup without blocking. True once the device is ready.
        Raises if a request failed."""
        if self._device:
            return True
        if self._adapter_req and self._adapter_req.value().ready():
            var req = self._adapter_req.take()
            self._adapter = req.take()
            self._device_req = self._adapter.value().request_device_async(self._label)
        if self._device_req and self._device_req.value().ready():
            var req = self._device_req.take()
            self._device = req.take()
        return Bool(self._device)

    def adapter(ref self) raises -> ref [self._adapter._value] Adapter:
        if not self._adapter:
            raise Error("GPUBoot: adapter not ready; call step() until it returns True")
        return self._adapter.value()

    def device(ref self) raises -> ref [self._device._value] Device:
        if not self._device:
            raise Error("GPUBoot: device not ready; call step() until it returns True")
        return self._device.value()
