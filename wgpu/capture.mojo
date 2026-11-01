"""
Wgpu.capture — read rendered frames back to the CPU (#14, video export).

    var cap = FrameCapture(device, width, height)
    # after rendering into `texture` (a surface configured with COPY_SRC):
    var req = cap.capture(device, texture)
    # ... later, without blocking:
    if req.ready():
        var px = req.take()          # rows of `cap.row_pitch()` bytes
        ... hand px to an encoder (WebCodecs, ffmpeg) ...
        cap.unmap()

Rows are padded to 256 bytes, as texture-to-buffer copies require. Pixels are
in the texture's own format: a surface is usually BGRA8.
"""

from wgpu._ffi.nulls import null_opaque
from wgpu._ffi.types import WGPUBufferUsage, WGPUMapMode, WGPUTextureHandle
from wgpu._ffi.structs import (
    WGPUTexelCopyBufferInfo, WGPUTexelCopyBufferLayout, WGPUTexelCopyTextureInfo,
    WGPUOrigin3D, WGPUExtent3D,
)
from wgpu._ffi.alloc_guard import AllocGuard
from wgpu.buffer import Buffer, MapRequest
from wgpu.device import Device


def padded_row_pitch(width: UInt32, bytes_per_pixel: UInt32 = 4) -> UInt32:
    var raw = width * bytes_per_pixel
    return (raw + 255) // 256 * 256


struct FrameCapture(Movable):
    """A readback buffer sized for one `width` x `height` frame."""

    var _buffer: Buffer
    var _width: UInt32
    var _height: UInt32
    var _row_pitch: UInt32

    def __init__(out self, device: Device, width: UInt32, height: UInt32) raises:
        self._width = width
        self._height = height
        self._row_pitch = padded_row_pitch(width)
        self._buffer = device.create_buffer(
            UInt64(self._row_pitch) * UInt64(height),
            WGPUBufferUsage.MAP_READ | WGPUBufferUsage.COPY_DST,
            False,
            "frame_capture",
        )

    def __init__(out self, *, deinit move: Self):
        self._buffer = move._buffer^
        self._width = move._width
        self._height = move._height
        self._row_pitch = move._row_pitch

    def width(self) -> UInt32:
        return self._width

    def height(self) -> UInt32:
        return self._height

    def row_pitch(self) -> UInt32:
        return self._row_pitch

    def byte_size(self) -> UInt:
        return UInt(self._row_pitch) * UInt(self._height)

    def capture(self, device: Device, texture: WGPUTextureHandle) raises -> MapRequest:
        """Copy `texture` into the readback buffer and start mapping it.

        `texture` needs COPY_SRC usage; for a surface, configure it with
        `extra_usage=WGPUTextureUsage.COPY_SRC`. Capture before present().
        """
        var enc = device.create_command_encoder("frame_capture")
        with AllocGuard[WGPUTexelCopyTextureInfo](1) as src:
            src[] = WGPUTexelCopyTextureInfo(texture, 0, WGPUOrigin3D(0, 0, 0), 0)
            with AllocGuard[WGPUTexelCopyBufferInfo](1) as dst:
                dst[] = WGPUTexelCopyBufferInfo(
                    WGPUTexelCopyBufferLayout(0, self._row_pitch, self._height),
                    self._buffer.handle().raw,
                )
                with AllocGuard[WGPUExtent3D](1) as size:
                    size[] = WGPUExtent3D(self._width, self._height, 1)
                    enc.copy_texture_to_buffer(src, dst, size)
        device.queue_submit(enc^.finish())
        return self._buffer.map_async(WGPUMapMode.READ)

    def unmap(self):
        """Release the mapped pixels so the next capture can reuse the buffer."""
        self._buffer.unmap()
