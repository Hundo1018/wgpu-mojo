"""
Tests/test_shader.mojo — Tests for shader module creation (WGSL).
Requires GPU hardware.
"""

from std.testing import assert_true, assert_equal
from wgpu.device import Device
from wgpu.instance import Instance


def create_test_device() raises -> Device:
    var instance = Instance()
    var adapter = instance.request_adapter()
    return adapter.request_device()


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
    var device  = create_test_device()
    var shader  = device.create_shader_module_wgsl(NOOP_WGSL, "noop")
    assert_true(shader)


def test_create_shader_module_wgsl_add() raises:
    """A compute shader with storage buffer bindings should compile."""
    var device  = create_test_device()
    var shader  = device.create_shader_module_wgsl(ADD_WGSL, "vec_add")
    assert_true(shader)


def test_shader_module_handle_nonnull() raises:
    """Returned handle should be non-null pointer."""
    var device = create_test_device()
    var shader = device.create_shader_module_wgsl(NOOP_WGSL)
    assert_true(shader)


comptime BAD_WGSL = """
@compute @workgroup_size(1)
fn main() {
    let x: f32 = "not a float";
}
"""


def test_compilation_info_clean_shader() raises:
    """A valid shader should return zero compilation messages."""
    var device = create_test_device()
    var shader = device.create_shader_module_wgsl(NOOP_WGSL, "noop_info")
    assert_true(shader)
    # SKIP get_compilation_info(): wgpuShaderModuleGetCompilationInfo is
    # unimplemented in wgpu-native v29 (panics "not implemented" in
    # src/unimplemented.rs, aborting across the C ABI — uncatchable from Mojo).
    # Re-enable the assertion below when wgpu-native implements it:
    #   assert_equal(len(shader.get_compilation_info()), 0)
    print("  SKIP: get_compilation_info (unimplemented in wgpu-native v29)")
    _ = device^


def test_compilation_info_bad_shader() raises:
    """An invalid shader should return at least one Error message."""
    var device = create_test_device()
    # get_compilation_info() is unimplemented in wgpu-native v29 (aborts), so we
    # instead verify the bad shader is rejected via the error-scope mechanism.
    # NOTE: creating a bad shader WITHOUT an active error scope routes the error
    # to wgpu-native's default sink, which panics and aborts the process — the
    # push/pop scope below is what makes this test safe.
    device.push_error_scope()
    var shader = device.create_shader_module_wgsl(BAD_WGSL, "bad_shader")
    var msg = device.pop_error_scope()
    assert_true(shader)
    assert_true(msg.byte_length() > 0)  # invalid WGSL must surface a scope error
    _ = device^


def main() raises:
    test_create_shader_module_wgsl_noop()
    test_create_shader_module_wgsl_add()
    test_shader_module_handle_nonnull()
    test_compilation_info_clean_shader()
    test_compilation_info_bad_shader()
    print("test_shader: ALL PASSED")
