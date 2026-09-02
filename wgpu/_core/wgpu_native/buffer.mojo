"""
wgpu._core.wgpu_native.buffer — Buffer RAII wrapper with typed MappedBuffer[T].

Key improvement over the old wgpu/buffer.mojo:
- map_read() / map_write() return MappedBuffer[T] (typed, RAII)
  instead of raw OpaquePointer[MutUntrackedOrigin]
- Automatic unmap on MappedBuffer destruction — no manual unmap() needed
- No Pointer in any public method signature
"""

from std.memory import ArcPointer
from wgpu._backend.wgpu_native.loader import WGPULib
from wgpu._backend.wgpu_native.nulls import null_ptr
from wgpu._backend.wgpu_native.types import (
    WGPUInstanceHandle, WGPUDeviceHandle, WGPUBufferHandle,
    WGPUBufferUsage, WGPUMapMode, WGPU_WHOLE_SIZE,
    WGPUMapAsyncStatus,
)
from wgpu._backend.wgpu_native.structs import WGPUStringView, str_to_sv
from wgpu._backend.wgpu_native.handles import BufferHandle


def _sizeof[T: AnyType]() -> Int:
    var p = null_ptr[T]()
    return Int(p.unsafe_offset(1)) - Int(p)


struct MappedBuffer[T: ImplicitlyCopyable](Movable):
    """
    RAII typed view into a mapped GPU buffer.

    Returned by Buffer.map_read() or Buffer.map_write().
    Automatically calls buffer_unmap on destruction — no manual unmap() needed.

    Usage:
        var mapped = buf.map_read[Float32]()
        print(mapped[0], mapped[1])
        var values = mapped.to_list()
        # mapped unmaps when it goes out of scope
    """

    var _lib:    ArcPointer[WGPULib]
    var _handle: WGPUBufferHandle
    var _data:   Pointer[Self.T, MutUntrackedOrigin]
    var _count:  Int

    def __init__(
        out self,
        lib: ArcPointer[WGPULib],
        handle: WGPUBufferHandle,
        raw: OpaquePointer[MutUntrackedOrigin],
        count: Int,
    ):
        self._lib    = lib
        self._handle = handle
        self._data   = Pointer(raw).unsafe_bitcast[Self.T]()
        self._count  = count

    def __init__(out self, *, deinit move: Self):
        self._lib    = move._lib^
        self._handle = move._handle
        self._data   = move._data
        self._count  = move._count

    def __deinit__(deinit self):
        self._lib[].buffer_unmap(self._handle)

    def __getitem__(self, i: Int) -> Self.T:
        return self._data[unsafe_offset=i]

    def len(self) -> Int:
        return self._count

    def to_list(self) -> List[Self.T]:
        """Copy all mapped values into a new List."""
        var out = List[Self.T](capacity=self._count)
        for i in range(self._count):
            out.append(self._data[unsafe_offset=i])
        return out^


struct Buffer(Movable, Boolable):
    """
    RAII wrapper around a WGPUBuffer.

    No Pointer in any public method.
    map_read[T]() / map_write[T]() return MappedBuffer[T], which auto-unmaps.
    """

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
    # Typed mapping (no raw pointers in public API)
    # ------------------------------------------------------------------

    def map_read[T: ImplicitlyCopyable](
        self, offset: UInt64 = 0, size: UInt64 = WGPU_WHOLE_SIZE
    ) raises -> MappedBuffer[T]:
        """Map buffer for reading. Returns a RAII MappedBuffer[T] that auto-unmaps."""
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
        var raw = self._lib[].buffer_get_const_mapped_range(
            self._handle, UInt(offset), byte_size
        )
        return MappedBuffer[T](self._lib, self._handle, raw, Int(byte_size) // _sizeof[T]())

    def map_write[T: ImplicitlyCopyable](
        self, offset: UInt64 = 0, size: UInt64 = WGPU_WHOLE_SIZE
    ) raises -> MappedBuffer[T]:
        """Map buffer for writing. Returns a RAII MappedBuffer[T] that auto-unmaps."""
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
        var raw = self._lib[].buffer_get_mapped_range(
            self._handle, UInt(offset), byte_size
        )
        return MappedBuffer[T](self._lib, self._handle, raw, Int(byte_size) // _sizeof[T]())

    # ------------------------------------------------------------------
    # Convenience helpers (higher level, still no raw pointers)
    # ------------------------------------------------------------------

    def read_data[T: ImplicitlyCopyable](self, offset: UInt64 = 0) raises -> List[T]:
        """Map, copy all data into a List[T], return it (auto-unmaps on scope exit)."""
        var mapped = self.map_read[T](offset)
        return mapped.to_list()

    def write_data[T: ImplicitlyCopyable](
        self, data: List[T], offset: UInt64 = 0
    ) raises:
        """Map for writing, copy List[T] data into GPU buffer (auto-unmaps)."""
        var byte_size = UInt64(len(data) * _sizeof[T]())
        var mapped = self.map_write[T](offset, byte_size)
        for i in range(len(data)):
            mapped._data.unsafe_offset(i).unsafe_write(data[i])

    # ------------------------------------------------------------------
    # Label
    # ------------------------------------------------------------------

