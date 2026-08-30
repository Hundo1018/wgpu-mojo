"""
wgpu.buffer — Buffer RAII wrapper with map/read/write helpers.
"""

from std.memory import ArcPointer
from wgpu._ffi.lib import WGPULib
from wgpu._ffi.nulls import null_opaque, null_ptr, null_any_ptr
from wgpu._ffi.types import (
    WGPUInstanceHandle, WGPUDeviceHandle, WGPUBufferHandle,
    WGPUBufferUsage, WGPUMapMode, WGPU_WHOLE_SIZE,
    WGPUMapAsyncStatus,
)
from wgpu._ffi.structs import WGPUStringView, str_to_sv
from wgpu._ffi.handles import BufferHandle


def _sizeof[T: AnyType]() -> Int:
    var p = null_ptr[T]()
    return Int(p.unsafe_offset(1)) - Int(p)


struct Buffer(Movable, Boolable):
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

    def __init__(out self, *, deinit move: Self):
        self._lib      = move._lib^
        self._instance = move._instance
        self._device   = move._device
        self._handle   = move._handle
        self._size     = move._size
        self._usage    = move._usage

    def __deinit__(deinit self):
        self._lib[].buffer_release(self._handle)

    def clone(self) -> Self:
        """Share ownership of this GPU object via `wgpuBufferAddRef`.

        A refcount bump, not a GPU-side copy: both wrappers refer to the same
        object and each releases on drop, so it survives until the last one
        goes away.
        """
        self._lib[].buffer_add_ref(self._handle)
        return Self(self._lib, self._instance, self._device, self._handle, self._size, self._usage)

    # ------------------------------------------------------------------
    # Properties
    # ------------------------------------------------------------------

    def size(self) -> UInt64:
        return self._size

    def usage(self) -> WGPUBufferUsage:
        return self._usage

    def handle(self) -> BufferHandle:
        return BufferHandle(self._handle)

    def __bool__(self) -> Bool:
        return Int(self._handle) != 0

    # ------------------------------------------------------------------
    # Mapping
    # ------------------------------------------------------------------

    def map_read(self, offset: UInt64 = 0, size: UInt64 = WGPU_WHOLE_SIZE) raises -> Pointer[NoneType, MutUntrackedOrigin]:
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
        return Pointer(self._lib[].buffer_get_const_mapped_range(
            self._handle, UInt(offset), byte_size
        ))

    def map_write(self, offset: UInt64 = 0, size: UInt64 = WGPU_WHOLE_SIZE) raises -> Pointer[NoneType, MutUntrackedOrigin]:
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
        return Pointer(self._lib[].buffer_get_mapped_range(
            self._handle, UInt(offset), byte_size
        ))

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
        var src = raw.unsafe_bitcast[T]()
        for i in range(count):
            out.append(src[unsafe_offset=i])
        self.unmap()
        return out^

    def write_data[T: ImplicitlyCopyable & Movable](self, data: List[T], offset: UInt64 = 0) raises:
        """Map for write, copy List[T] data, then unmap."""
        var byte_size = UInt64(len(data) * _sizeof[T]())
        var raw = self.map_write(offset, byte_size)
        var dst = raw.unsafe_bitcast[T]()
        for i in range(len(data)):
            (dst + i).init_pointee_copy(data[i])
        self.unmap()

    # ------------------------------------------------------------------
    # Label
    # ------------------------------------------------------------------

