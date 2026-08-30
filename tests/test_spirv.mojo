"""
SPIR-V shader modules, both entry points.

Shader modules are built from SPIR-V by chaining a WGPUShaderSourceSPIRV onto
the standard descriptor. wgpu-native also exports a wgpuDeviceCreateShaderModuleSpirV
extension entry point; it is deliberately unbound (see scripts/excluded-symbols.txt)
because it reports an error on this driver even with SpirvShaderPassthrough
requested, while the standard path below works.

The module below is hand-assembled rather than compiled, so the tests need no
SPIR-V toolchain: it is the minimal valid compute shader, `void main() {}` at
local_size(1,1,1).

Requires GPU hardware.
"""

from std.testing import assert_true, assert_equal
from wgpu.device import Device
from wgpu.instance import Instance


def create_test_device() raises -> Device:
    var instance = Instance()
    var adapter = instance.request_adapter()
    return adapter.request_device()


def minimal_spirv() -> List[UInt32]:
    """Minimal valid SPIR-V compute module (35 words)."""
    return [
        UInt32(0x07230203), UInt32(0x00010000), UInt32(0), UInt32(5), UInt32(0),
        UInt32(0x00020011), UInt32(1),                                    # OpCapability Shader
        UInt32(0x0003000E), UInt32(0), UInt32(1),                         # OpMemoryModel Logical GLSL450
        UInt32(0x0005000F), UInt32(5), UInt32(1), UInt32(0x6E69616D), UInt32(0),
        UInt32(0x00060010), UInt32(1), UInt32(17), UInt32(1), UInt32(1), UInt32(1),
        UInt32(0x00020013), UInt32(2),                                    # OpTypeVoid %2
        UInt32(0x00030021), UInt32(3), UInt32(2),                         # OpTypeFunction %3 %2
        UInt32(0x00050036), UInt32(2), UInt32(1), UInt32(0), UInt32(3),   # OpFunction
        UInt32(0x000200F8), UInt32(4),                                    # OpLabel
        UInt32(0x000100FD),                                               # OpReturn
        UInt32(0x00010038),                                               # OpFunctionEnd
    ]


def test_spirv_standard_path() raises:
    """Create_shader_module_spirv() chains WGPUShaderSourceSPIRV."""
    var device = create_test_device()
    var words = minimal_spirv()
    assert_equal(len(words), 35)
    device.push_error_scope()
    var shader = device.create_shader_module_spirv(words, "spv_standard")
    var err = device.pop_error_scope()
    assert_true(shader, "SPIR-V shader module was not created")
    assert_equal(err.byte_length(), 0, "valid SPIR-V raised: " + err)
    _ = device^


def test_spirv_rejects_garbage() raises:
    """A bad magic number must be rejected, not silently accepted."""
    var device = create_test_device()
    var bad: List[UInt32] = [UInt32(0xDEADBEEF), UInt32(0), UInt32(0), UInt32(1), UInt32(0)]
    device.push_error_scope()
    var shader = device.create_shader_module_spirv(bad, "spv_bad")
    var err = device.pop_error_scope()
    assert_true(err.byte_length() > 0, "invalid SPIR-V should surface a scope error")
    _ = device^


def main() raises:
    test_spirv_standard_path()
    print("  PASS: test_spirv_standard_path")
    test_spirv_rejects_garbage()
    print("  PASS: test_spirv_rejects_garbage")
    print("test_spirv: ALL PASSED")
