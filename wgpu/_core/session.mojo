"""
wgpu._core.session — Resource lifetime manager for GPU submissions.

Session solves Mojo's ASAP-destruction problem for GPU resources.
Mojo's compiler drops variables as soon as they leave their last
observed use, but GPU resources submitted to the queue must stay
alive until the GPU finishes executing.

Without Session, user code needs explicit lifetime pins:
    device.queue_submit(cmd)
    _ = pipeline^          # workaround: prevent ASAP drop
    _ = bg^
    _ = buf_a^
    device.poll(True)

With Session:
    var session = Session(lib, device_handle, queue_handle)
    session.pin(pipeline^)
    session.pin(bg^)
    session.pin(buf_a^)
    session.submit_and_flush(cmd)
"""

from std.memory import ArcPointer
from wgpu._backend.wgpu_native.loader import WGPULib
from wgpu._backend.wgpu_native.nulls import null_any_ptr
from wgpu._backend.wgpu_native.types import (
    WGPUDeviceHandle, WGPUQueueHandle, WGPUCommandBufferHandle, WGPU_TRUE,
)
from wgpu.buffer import Buffer
from wgpu.bind_group import BindGroup, BindGroupLayout
from wgpu.pipeline import ComputePipeline, RenderPipeline
from wgpu.pipeline_layout import PipelineLayout
from wgpu.shader import ShaderModule
from wgpu.texture import Texture, TextureView
from wgpu.sampler import Sampler
from wgpu.command import CommandBuffer


struct Session(Movable):
    """
    Keeps GPU resources alive across a queue_submit + poll cycle.

    All resources pin()ned into a Session are owned by the Session
    and released only when flush() is called (after the GPU finishes).
    This eliminates the need for `_ = resource^` workarounds.
    """

    var _lib:           ArcPointer[WGPULib]
    var _queue_handle:  WGPUQueueHandle
    var _device_handle: WGPUDeviceHandle

    # Pinned resources — kept alive until flush()
    var _buffers:            List[Buffer]
    var _bind_groups:        List[BindGroup]
    var _bind_group_layouts: List[BindGroupLayout]
    var _compute_pipelines:  List[ComputePipeline]
    var _render_pipelines:   List[RenderPipeline]
    var _pipeline_layouts:   List[PipelineLayout]
    var _shaders:            List[ShaderModule]
    var _textures:           List[Texture]
    var _texture_views:      List[TextureView]
    var _samplers:           List[Sampler]

    def __init__(
        out self,
        lib: ArcPointer[WGPULib],
        device_handle: WGPUDeviceHandle,
        queue_handle: WGPUQueueHandle,
    ):
        self._lib            = lib
        self._device_handle  = device_handle
        self._queue_handle   = queue_handle
        self._buffers            = List[Buffer]()
        self._bind_groups        = List[BindGroup]()
        self._bind_group_layouts = List[BindGroupLayout]()
        self._compute_pipelines  = List[ComputePipeline]()
        self._render_pipelines   = List[RenderPipeline]()
        self._pipeline_layouts   = List[PipelineLayout]()
        self._shaders            = List[ShaderModule]()
        self._textures           = List[Texture]()
        self._texture_views      = List[TextureView]()
        self._samplers           = List[Sampler]()

    def __init__(out self, *, deinit move: Self):
        self._lib            = move._lib^
        self._device_handle  = move._device_handle
        self._queue_handle   = move._queue_handle
        self._buffers            = move._buffers^
        self._bind_groups        = move._bind_groups^
        self._bind_group_layouts = move._bind_group_layouts^
        self._compute_pipelines  = move._compute_pipelines^
        self._render_pipelines   = move._render_pipelines^
        self._pipeline_layouts   = move._pipeline_layouts^
        self._shaders            = move._shaders^
        self._textures           = move._textures^
        self._texture_views      = move._texture_views^
        self._samplers           = move._samplers^

    # ------------------------------------------------------------------
    # pin() overloads — one per resource type
    # (var = owned/consuming parameter in Mojo nightly)
    # ------------------------------------------------------------------

    def pin(mut self, var resource: Buffer):
        """Transfer ownership of a Buffer into the session."""
        self._buffers.append(resource^)

    def pin(mut self, var resource: BindGroup):
        self._bind_groups.append(resource^)

    def pin(mut self, var resource: BindGroupLayout):
        self._bind_group_layouts.append(resource^)

    def pin(mut self, var resource: ComputePipeline):
        self._compute_pipelines.append(resource^)

    def pin(mut self, var resource: RenderPipeline):
        self._render_pipelines.append(resource^)

    def pin(mut self, var resource: PipelineLayout):
        self._pipeline_layouts.append(resource^)

    def pin(mut self, var resource: ShaderModule):
        self._shaders.append(resource^)

    def pin(mut self, var resource: Texture):
        self._textures.append(resource^)

    def pin(mut self, var resource: TextureView):
        self._texture_views.append(resource^)

    def pin(mut self, var resource: Sampler):
        self._samplers.append(resource^)

    # ------------------------------------------------------------------
    # Submission helpers
    # ------------------------------------------------------------------

    def submit(mut self, var cmd: CommandBuffer):
        """Submit a command buffer to the GPU queue (does not poll)."""
        var handle = cmd.raw()
        var handle_p = alloc[WGPUCommandBufferHandle](1)
        handle_p[] = handle
        var arr = rebind[Pointer[WGPUCommandBufferHandle, MutUntrackedOrigin]](handle_p)
        self._lib[].queue_submit(self._queue_handle, UInt(1), arr)
        handle_p.unsafe_free()

    def flush(mut self):
        """Poll until GPU finishes, then release all pinned resources."""
        _ = self._lib[].device_poll(self._device_handle, True)
        self._drop_all()

    def submit_and_flush(mut self, var cmd: CommandBuffer):
        """Submit, wait for GPU completion, release all pinned resources."""
        self.submit(cmd^)
        self.flush()

    # ------------------------------------------------------------------
    # Internal
    # ------------------------------------------------------------------

    def _drop_all(mut self):
        self._buffers.clear()
        self._bind_groups.clear()
        self._bind_group_layouts.clear()
        self._compute_pipelines.clear()
        self._render_pipelines.clear()
        self._pipeline_layouts.clear()
        self._shaders.clear()
        self._textures.clear()
        self._texture_views.clear()
        self._samplers.clear()
