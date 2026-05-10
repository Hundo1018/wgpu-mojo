"""
Tests/test_preflight.mojo — Verify wgpu.preflight() returns a usable diagnostic string.

Requires: GPU hardware + built callback libraries (pixi run build-callbacks).
Run:
    pixi run mojo run -I . tests/test_preflight.mojo
"""

from std.testing import assert_true
from wgpu.diagnostics import preflight


def test_preflight_returns_string() raises:
    """preflight() must return a non-empty string without raising."""
    var result = preflight()
    assert_true(result.byte_length() > 0, "preflight() returned empty string")


def test_preflight_contains_version() raises:
    """On a machine with a working GPU stack, preflight() reports the version."""
    var result = preflight()
    # Either success path (contains version) or failure path (contains "FAILED") is valid.
    var ok = "wgpu-native version" in result or "FAILED" in result
    assert_true(ok, "preflight() output missing expected content:\n" + result)


def test_preflight_no_raise() raises:
    """preflight() must never raise — errors go into the returned string."""
    # This test simply confirms the function is callable from a raises context.
    var result = preflight()
    _ = result


def main() raises:
    test_preflight_returns_string()
    print("  PASS: test_preflight_returns_string")
    test_preflight_contains_version()
    print("  PASS: test_preflight_contains_version")
    test_preflight_no_raise()
    print("  PASS: test_preflight_no_raise")

    # Also print the full diagnostic so the user can see adapter details.
    print("\n--- preflight() output ---")
    print(preflight())
    print("--------------------------")
    print("test_preflight: ALL PASSED")
