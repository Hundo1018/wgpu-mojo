"""
wgpu.gpu — Unified GPU facade (Layer 3).

Provides a single entry point for GPU compute operations that hides
the complexity of Instance → Adapter → Device initialization, command
encoding, bind group assembly, and resource lifetime management.

Usage (wgpu backend):
    var gpu = GPU.wgpu()
    var buf_a = gpu.buffer[Float32](1024, WGPUBufferUsage.STORAGE | WGPUBufferUsage.COPY_DST)
    var buf_b = gpu.buffer[Float32](1024, WGPUBufferUsage.STORAGE | WGPUBufferUsage.COPY_DST)
    var buf_c = gpu.buffer[Float32](1024, WGPUBufferUsage.STORAGE | WGPUBufferUsage.COPY_SRC)
    gpu.write(buf_a, my_data)
    gpu.write(buf_b, my_data2)
    var prog = gpu.compile_compute(ADD_WGSL, entry_point="main", n_storage_buffers=3)
    gpu.dispatch(prog^, [buf_a.handle(), buf_b.handle(), buf_c.handle()], 16, 1, 1)
    gpu.sync()
    var result = gpu.read[Float32](buf_c)
"""

from std.memory import ArcPointer
from wgpu.instance import Instance
from wgpu.adapter import Adapter
from wgpu.device import Device
from wgpu.buffer import Buffer
from wgpu.shader import ShaderModule
from wgpu.bind_group import BindGroup, BindGroupLayout
from wgpu.pipeline import ComputePipeline
from wgpu.pipeline_layout import PipelineLayout
from wgpu.command import CommandBuffer, CommandEncoder
from wgpu.descriptors import BGL
from wgpu._ffi.types import WGPUBufferUsage, WGPU_WHOLE_SIZE
from wgpu._ffi.structs import WGPUBindGroupEntry, WGPUBindGroupLayoutEntry
from wgpu._ffi.nulls import null_opaque, null_ptr
from wgpu._ffi.handles import BufferHandle, SamplerHandle, TextureViewHandle


def _elem_size[T: AnyType]() -> Int:
    """Compute sizeof(T) without requiring a real instance."""
    var p = null_ptr[T]()
    return Int(p + 1) - Int(p)


# ---------------------------------------------------------------------------
# WgpuComputeProgram — compiled pipeline + bind group layout
# ---------------------------------------------------------------------------

struct WgpuComputeProgram(Movable):
    """
    A compiled compute program ready for dispatch.

    Created by GPU.compile_compute(). Holds the pipeline and BGL
    needed to assemble bind groups at dispatch time.
    """

    var pipeline: ComputePipeline
    var bgl:      BindGroupLayout
    var layout:   PipelineLayout

    def __init__(
        out self,
        var pipeline: ComputePipeline,
        var bgl: BindGroupLayout,
        var layout: PipelineLayout,
    ):
        self.pipeline = pipeline^
        self.bgl      = bgl^
        self.layout   = layout^

    def __init__(out self, *, deinit move: Self):
        self.pipeline = move.pipeline^
        self.bgl      = move.bgl^
        self.layout   = move.layout^


# ---------------------------------------------------------------------------
# GPU — unified facade
# ---------------------------------------------------------------------------

struct GPU(Movable):
    """
    Unified GPU context for compute operations.

    Wraps Instance + Adapter + Device into a single object and manages
    resource lifetimes via Session so users never need `_ = resource^`.
    """

    var _instance: Instance
    var _device:   Device

    @staticmethod
    def wgpu() raises -> GPU:
        """Initialize a GPU context using the wgpu-native backend."""
        var instance = Instance()
        var adapter  = instance.request_adapter()
        var device   = adapter.request_device()
        return GPU(instance^, device^)

    def __init__(out self, var instance: Instance, var device: Device):
        self._instance = instance^
        self._device   = device^

    def __init__(out self, *, deinit move: Self):
        self._instance = move._instance^
        self._device   = move._device^

    # ------------------------------------------------------------------
    # Buffer allocation
    # ------------------------------------------------------------------

    def buffer[T: AnyType](
        mut self,
        count: Int,
        usage: WGPUBufferUsage,
        label: String = "",
    ) raises -> Buffer:
        """Allocate a GPU buffer sized for `count` elements of type T."""
        return self._device.create_buffer(
            UInt64(count * _elem_size[T]()), usage, False, label
        )

    # ------------------------------------------------------------------
    # Data transfer
    # ------------------------------------------------------------------

    def write[T: Copyable & Movable](
        mut self,
        buffer: Buffer,
        data: List[T],
        offset: UInt64 = 0,
    ):
        """Upload host data to a GPU buffer."""
        self._device.queue_write_data(buffer, offset, data)

    def read[T: ImplicitlyCopyable & Movable](
        mut self,
        buffer: Buffer,
        offset: UInt64 = 0,
    ) raises -> List[T]:
        """Download GPU buffer data to host. Blocks until GPU finishes."""
        _ = self._device.poll(True)
        return buffer.read_data[T](offset)

    # ------------------------------------------------------------------
    # Shader compilation
    # ------------------------------------------------------------------

    def compile_compute(
        mut self,
        wgsl: String,
        entry_point: String = "main",
        n_storage_buffers: Int = 3,
        label: String = "",
    ) raises -> WgpuComputeProgram:
        """
        Compile a WGSL compute shader.

        Automatically builds a BindGroupLayout with `n_storage_buffers`
        read-write storage buffer bindings at group 0.
        """
        var shader = self._device.create_shader_module_wgsl(wgsl, label + "_shader")
        var entries = List[WGPUBindGroupLayoutEntry]()
        for i in range(n_storage_buffers):
            entries.append(BGL.buffer_storage(binding=UInt32(i)))
        var bgl    = self._device.create_bind_group_layout(entries, label + "_bgl")
        var layout = self._device.create_pipeline_layout(bgl, label + "_layout")
        var pipeline = self._device.create_compute_pipeline(shader, entry_point, layout, label)
        return WgpuComputeProgram(pipeline^, bgl^, layout^)

    # ------------------------------------------------------------------
    # Dispatch
    # ------------------------------------------------------------------

    def dispatch(
        mut self,
        var prog: WgpuComputeProgram,
        buffers: List[BufferHandle],
        wx: UInt32,
        wy: UInt32 = 1,
        wz: UInt32 = 1,
        label: String = "",
    ) raises:
        """
        Execute a compute program over a set of buffer handles.

        Assembles a BindGroup, records a compute pass, submits, and waits.
        `prog` and `bg` are kept in scope past poll() via tail pins.
        `buffers` takes `BufferHandle` (TrivialRegisterPassable) so the caller
        keeps ownership of the Buffer wrappers and can read them back afterwards.
        """
        # Build bind group (borrows prog.bgl)
        var bg_entries = List[WGPUBindGroupEntry]()
        for i in range(len(buffers)):
            bg_entries.append(WGPUBindGroupEntry(
                null_opaque(), UInt32(i),
                buffers[i].raw,
                UInt64(0), WGPU_WHOLE_SIZE,
                SamplerHandle.null().raw,
                TextureViewHandle.null().raw,
            ))
        var bg = self._device.create_bind_group(prog.bgl, bg_entries, label + "_bg")

        # Record compute commands (borrows prog.pipeline)
        var enc   = self._device.create_command_encoder(label + "_enc")
        var cpass = enc.begin_compute_pass(label + "_pass")
        cpass.set_pipeline(prog.pipeline)
        cpass.set_bind_group(UInt32(0), bg)
        cpass.dispatch_workgroups(wx, wy, wz)
        cpass^.end()
        var cmd = enc^.finish(label + "_cmd")

        # Submit and wait; tail-pin prog and bg to survive past poll
        self._device.queue_submit(cmd^)
        _ = self._device.poll(True)
        _ = bg^
        _ = prog^

    # ------------------------------------------------------------------
    # Synchronization
    # ------------------------------------------------------------------

    def sync(mut self):
        """Wait for all pending GPU work to complete."""
        _ = self._device.poll(True)

