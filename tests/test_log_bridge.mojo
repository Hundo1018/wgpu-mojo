"""
Wgpu-native log routed into Mojo.

wgpuSetLogCallback needs a stored C function pointer, which Mojo cannot produce,
and wgpu-native calls it from its own threads. ffi/wgpu_callbacks.c owns a
mutex-guarded ring buffer; these tests check the Mojo side drains it correctly.

Requires GPU hardware (adapter enumeration is what produces log traffic).
"""

from std.testing import assert_true, assert_equal
from wgpu.instance import Instance
from wgpu.diagnostics import install_log_callback, drain_log, log_dropped_count
from wgpu._backend.wgpu_native.native_ext import WGPULogLevel


def test_log_captures_messages() raises:
    """At Trace level, bringing up an adapter must produce log traffic."""
    var instance = Instance()
    install_log_callback(WGPULogLevel.Trace)
    var adapter = instance.request_adapter()
    var msgs = drain_log()
    assert_true(len(msgs) > 0, "no log messages captured at Trace level")
    # Every line is "LEVEL: text" — the level prefix must be a known name.
    for m in msgs:
        var known = (
            m.startswith("ERROR: ") or m.startswith("WARN: ")
            or m.startswith("INFO: ") or m.startswith("DEBUG: ")
            or m.startswith("TRACE: ")
        )
        assert_true(known, "unexpected log level prefix: " + m)
    _ = instance^


def test_drain_is_destructive() raises:
    """Draining removes messages, so a second drain returns nothing new."""
    var instance = Instance()
    install_log_callback(WGPULogLevel.Trace)
    var adapter = instance.request_adapter()
    var first = drain_log()
    assert_true(len(first) > 0, "expected messages on the first drain")
    var second = drain_log()
    assert_equal(len(second), 0, "second drain should be empty, got " + String(len(second)))
    _ = instance^


def test_log_off_produces_nothing() raises:
    """At Off, the callback must receive nothing."""
    var instance = Instance()
    install_log_callback(WGPULogLevel.Trace)
    var adapter = instance.request_adapter()
    _ = drain_log()                       # clear whatever the bring-up logged
    install_log_callback(WGPULogLevel.Off)
    var adapter2 = instance.request_adapter()
    assert_equal(len(drain_log()), 0, "messages arrived while logging was Off")
    _ = instance^


def main() raises:
    test_log_captures_messages()
    print("  PASS: test_log_captures_messages")
    test_drain_is_destructive()
    print("  PASS: test_drain_is_destructive")
    test_log_off_produces_nothing()
    print("  PASS: test_log_off_produces_nothing")
    print("  note: dropped =", log_dropped_count())
    print("test_log_bridge: ALL PASSED")
