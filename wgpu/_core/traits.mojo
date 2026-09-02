"""
wgpu._core.traits — Shared traits for all GPU resource types.

These traits define the minimum interface contract that both the
wgpu-native and Mojo-native backends must satisfy.
"""


trait GpuResource:
    """Any GPU-owned object with a wgpu-native handle behind it.

    Deliberately empty: the only requirement used to be set_label(), but every
    wgpu*SetLabel entry point is an unimplemented!() stub in wgpu-native v29
    that aborts the process when called, so the wrappers were removed. See
    scripts/known-unimplemented.txt.
    """

    pass


trait GpuBuffer(GpuResource):
    """A GPU buffer with a known byte size."""

    def size(self) -> UInt64:
        ...
