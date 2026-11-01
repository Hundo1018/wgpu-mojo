"""
wgpu.capture.FrameCapture: read a rendered frame back without blocking (#14).
Requires GPU hardware.
"""

from std.testing import assert_true, assert_equal
from wgpu.instance import Instance
from wgpu.capture import FrameCapture, padded_row_pitch
from wgpu._ffi.types import WGPUTextureUsage, WGPUTextureFormat
from wgpu._ffi.structs import WGPUColor


def test_row_pitch() raises:
    assert_equal(padded_row_pitch(1), UInt32(256))
    assert_equal(padded_row_pitch(64), UInt32(256))
    assert_equal(padded_row_pitch(65), UInt32(512))


def test_capture_clear_color() raises:
    var instance = Instance()
    var device = instance.request_adapter().request_device()
    var w: UInt32 = 70  # not a multiple of 64, so rows are padded
    var h: UInt32 = 3
    var tex = device.create_texture(
        w, h, 1, WGPUTextureFormat.RGBA8Unorm,
        WGPUTextureUsage.RENDER_ATTACHMENT | WGPUTextureUsage.COPY_SRC,
        label="capture_target",
    )
    var enc = device.create_command_encoder("clear")
    var rpass = enc.begin_surface_clear_pass(tex.handle().raw, WGPUColor(1.0, 0.5, 0.0, 1.0), "clear")
    rpass^.end()
    device.queue_submit(enc^.finish())

    var cap = FrameCapture(device, w, h)
    var req = cap.capture(device, tex.handle().raw)
    var polls = 0
    while not req.ready():
        polls += 1
        if polls > 1_000_000:
            raise Error("capture never completed")
    var px = req.take().unsafe_bitcast[UInt8]()
    var pitch = Int(cap.row_pitch())
    for y in range(Int(h)):
        for x in [0, Int(w) - 1]:
            var i = y * pitch + x * 4
            assert_equal(px[unsafe_offset=i], UInt8(255))
            assert_true(px[unsafe_offset=i + 1] >= 127 and px[unsafe_offset=i + 1] <= 128)
            assert_equal(px[unsafe_offset=i + 2], UInt8(0))
            assert_equal(px[unsafe_offset=i + 3], UInt8(255))
    cap.unmap()
    _ = tex^
    _ = device^


def main() raises:
    test_row_pitch()
    print("  PASS: row pitch padded to 256")
    test_capture_clear_color()
    print("  PASS: captured pixels == clear color")
    print("test_capture: ALL PASSED")
