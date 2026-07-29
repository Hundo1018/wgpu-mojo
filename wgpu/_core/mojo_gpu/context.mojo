"""
wgpu._core.mojo_gpu.context — Mojo native GPU program wrapper (stub).

When Mojo's gpu.host.DeviceContext is available in this environment,
replace the stubs below with actual implementations:

    from gpu.host import DeviceContext, DeviceBuffer

For now this establishes the architecture and type interfaces.
See MOJO_ROUGH_EDGES.md for the full Mojo GPU backend plan.
"""

from std.memory import ArcPointer
from wgpu._backend.mojo_gpu.context import MojoGPUContext


struct MojoComputeProgram[kernel_name: StaticString](Movable):
    """
    Wraps a Mojo native GPU kernel for dispatch.

    The kernel is a comptime parameter — it's not a runtime value.
    This struct holds the shared context needed at dispatch time.

    Usage (once DeviceContext is available):
        comptime var prog = gpu.bind_kernel[my_kernel]()
        gpu.enqueue(prog, tensor_a, tensor_b, output, N, grid_dim=G, block_dim=B)
    """

    var _ctx: ArcPointer[MojoGPUContext]

    def __init__(out self, ctx: ArcPointer[MojoGPUContext]):
        self._ctx = ctx

    def __init__(out self, *, deinit move: Self):
        self._ctx = move._ctx^

    def context(self) -> ArcPointer[MojoGPUContext]:
        return self._ctx
