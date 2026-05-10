"""Quick smoke test for Instance -> Adapter -> Device compilation."""
from wgpu import Instance

def main() raises:
    var instance = Instance()
    var adapter = instance.request_adapter()
    var device = adapter.request_device()
    _ = device
    print("Instance, Adapter, and Device compiled and imported successfully")
