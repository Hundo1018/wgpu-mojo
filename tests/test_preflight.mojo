"""
Tests/test_preflight.mojo — Verify wgpu.preflight() returns a usable diagnostic string.

Requires: GPU hardware + built callback libraries (pixi run build-callbacks).
Run:
    pixi run mojo run -I . tests/test_preflight.mojo
"""

from std.testing import assert_equal, assert_true
from wgpu.diagnostics import check_symbols, critical_symbols, preflight


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


def test_critical_symbols_present() raises:
    """Every critical symbol must be exported by the loaded libwgpu_native.

    Guards against ABI drift. FFI symbols resolve lazily at each call site, so
    a name upstream has renamed still compiles cleanly and only fails when that
    code path first runs — which `check-compile` cannot catch. Needs no GPU,
    only the shared library.
    """
    var missing = check_symbols()
    var detail = String()
    for name in missing:
        detail += "\n    missing: " + name
    assert_equal(
        len(missing),
        0,
        "libwgpu_native does not export " + String(len(missing))
        + " symbol(s) this binding resolves:" + detail,
    )


def test_preflight_reports_symbol_check() raises:
    """preflight() must surface the symbol-check result."""
    var result = preflight()
    var ok = "symbol check: OK" in result or "FAILED" in result
    assert_true(ok, "preflight() output missing symbol check:\n" + result)


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
    test_critical_symbols_present()
    print("  PASS: test_critical_symbols_present ("
          + String(len(critical_symbols())) + " symbols checked)")
    test_preflight_reports_symbol_check()
    print("  PASS: test_preflight_reports_symbol_check")
    test_preflight_no_raise()
    print("  PASS: test_preflight_no_raise")

    # Also print the full diagnostic so the user can see adapter details.
    print("\n--- preflight() output ---")
    print(preflight())
    print("--------------------------")
    print("test_preflight: ALL PASSED")
