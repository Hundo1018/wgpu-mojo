"""
wgpu.buffer — Buffer RAII wrapper with map/read/write helpers.
"""

from std.memory import ArcPointer
from wgpu._ffi.lib import WGPULib
from wgpu._ffi.types import (
    OpaquePtr,
    WGPUInstanceHandle, WGPUDeviceHandle, WGPUBufferHandle,
    WGPUBufferUsage, WGPUMapMode, WGPU_WHOLE_SIZE,
    WGPUMapAsyncStatus,
)
from wgpu._ffi.structs import WGPUStringView, str_to_sv
from wgpu._ffi.handles import BufferHandle


def _sizeof[T: AnyType]() -> Int:
    var p = UnsafePointer[T, MutExternalOrigin]()
    return Int(p + 1) - Int(p)


struct Buffer(Movable):
    """RAII wrapper around a WGPUBuffer."""

    var _lib:      ArcPointer[WGPULib]
    var _instance: WGPUInstanceHandle
    var _device:   WGPUDeviceHandle
    var _handle:   WGPUBufferHandle
    var _size:     UInt64
    var _usage:    WGPUBufferUsage

    def __init__(
        out self,
        lib: ArcPointer[WGPULib],
        instance: WGPUInstanceHandle,
        device: WGPUDeviceHandle,
        handle: WGPUBufferHandle,
        size: UInt64,
        usage: WGPUBufferUsage,
    ):
        self._lib      = lib
        self._instance = instance
        self._device   = device
        self._handle   = handle
        self._size     = size
        self._usage    = usage

    def __init__(out self, *, deinit take: Self):
        self._lib      = take._lib^
        self._instance = take._instance
        self._device   = take._device
        self._handle   = take._handle
        self._size     = take._size
        self._usage    = take._usage

    def __del__(deinit self):
        self._lib[].buffer_release(self._handle)

    # ------------------------------------------------------------------
    # Properties
    # ------------------------------------------------------------------

    def size(self) -> UInt64:
        return self._size

    def usage(self) -> WGPUBufferUsage:
        return self._usage

    def map_state(self) -> UInt32:
        return self._lib[].buffer_get_map_state(self._handle)

    def handle(self) -> BufferHandle:
        return BufferHandle(self._handle)

    # ------------------------------------------------------------------
    # Mapping
    # ------------------------------------------------------------------

    def map_read(self, offset: UInt64 = 0, size: UInt64 = WGPU_WHOLE_SIZE) raises -> OpaquePtr:
        """Block until mapped for reading, return raw pointer."""
        var byte_size = UInt(size) if size != WGPU_WHOLE_SIZE else UInt(self._size - offset)
        var status = self._lib[].buffer_map_async(
            self._instance,
            self._device,
            self._handle,
            WGPUMapMode.READ.value,
            UInt(offset),
            byte_size,
        )
        if status != WGPUMapAsyncStatus.Success:
            raise Error("Buffer map (read) failed, status=" + String(status))
        return self._lib[].buffer_get_const_mapped_range(
            self._handle, UInt(offset), byte_size
        )

    def map_write(self, offset: UInt64 = 0, size: UInt64 = WGPU_WHOLE_SIZE) raises -> OpaquePtr:
        """Block until mapped for writing, return raw pointer."""
        var byte_size = UInt(size) if size != WGPU_WHOLE_SIZE else UInt(self._size - offset)
        var status = self._lib[].buffer_map_async(
            self._instance,
            self._device,
            self._handle,
            WGPUMapMode.WRITE.value,
            UInt(offset),
            byte_size,
        )
        if status != WGPUMapAsyncStatus.Success:
            raise Error("Buffer map (write) failed, status=" + String(status))
        return self._lib[].buffer_get_mapped_range(
            self._handle, UInt(offset), byte_size
        )

    def unmap(self):
        self._lib[].buffer_unmap(self._handle)

    # ------------------------------------------------------------------
    # Convenience typed read/write helpers
    # ------------------------------------------------------------------

    def read_data[T: ImplicitlyCopyable & Movable](self, offset: UInt64 = 0) raises -> List[T]:
        """Map, copy data into a List[T], then unmap."""
        var count = Int(self._size - offset) // _sizeof[T]()
        var raw = self.map_read(offset)
        var out = List[T](capacity=count)
        var src = raw.bitcast[T]()
        for i in range(count):
            out.append(src[i])
        self.unmap()
        return out^

    def write_data[T: ImplicitlyCopyable & Movable](self, data: List[T], offset: UInt64 = 0) raises:
        """Map for write, copy List[T] data, then unmap."""
        var byte_size = UInt64(len(data) * _sizeof[T]())
        var raw = self.map_write(offset, byte_size)
        var dst = raw.bitcast[T]()
        for i in range(len(data)):
            (dst + i).init_pointee_copy(data[i])
        self.unmap()

    # ------------------------------------------------------------------
    # Label
    # ------------------------------------------------------------------

    def set_label(self, label: String):
        var sv = str_to_sv(label) if label.byte_length() > 0 else WGPUStringView.null_view()
        self._lib[].buffer_set_label(self._handle, sv)
