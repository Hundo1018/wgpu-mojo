"""
wgpu._core.traits — Shared traits for all GPU resource types.

These traits define the minimum interface contract that both the
wgpu-native and Mojo-native backends must satisfy.
"""


trait GpuResource:
    """Any GPU-owned object that can be labeled and is movable."""

    def set_label(mut self, label: String):
        """Attach a debug label visible in GPU profilers."""
        ...


trait GpuBuffer(GpuResource):
    """A GPU buffer with a known byte size."""

    def size(self) -> UInt64:
        ...
