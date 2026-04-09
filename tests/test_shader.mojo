"""
tests/test_shader.mojo — Tests for shader module creation (WGSL).
Requires GPU hardware.
"""

from std.testing import assert_true
from wgpu.gpu import request_adapter


comptime NOOP_WGSL = """
@compute @workgroup_size(1)
fn main() {}
"""

comptime ADD_WGSL = """
@group(0) @binding(0) var<storage, read>       a : array<f32>;
@group(0) @binding(1) var<storage, read>       b : array<f32>;
@group(0) @binding(2) var<storage, read_write> c : array<f32>;

@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let i = gid.x;
    if i < arrayLength(&a) {
        c[i] = a[i] + b[i];
    }
}
"""


def test_create_shader_module_wgsl_noop() raises:
    """A minimal WGSL shader should compile without errors."""
    var inst    = request_adapter()
    var device  = inst.request_device()
    var shader  = device.create_shader_module_wgsl(NOOP_WGSL, "noop")
    assert_true(Bool(shader.handle()))


def test_create_shader_module_wgsl_add() raises:
    """A compute shader with storage buffer bindings should compile."""
    var inst    = request_adapter()
    var device  = inst.request_device()
    var shader  = device.create_shader_module_wgsl(ADD_WGSL, "vec_add")
    assert_true(Bool(shader.handle()))


def test_shader_module_handle_nonnull() raises:
    """Returned handle should be non-null pointer."""
    var inst   = request_adapter()
    var device = inst.request_device()
    var shader = device.create_shader_module_wgsl(NOOP_WGSL)
    assert_true(Bool(shader.handle()))


def main() raises:
    test_create_shader_module_wgsl_noop()
    test_create_shader_module_wgsl_add()
    test_shader_module_handle_nonnull()
    print("test_shader: ALL PASSED")
