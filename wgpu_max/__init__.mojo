"""wgpu_max — opt-in bridge between wgpu-mojo and Mojo's built-in GPU stack.

This package is deliberately NOT part of the `wgpu` package. It is the only
code in this repository that imports `max`, and `mojo package wgpu` never
compiles it, so the published wgpu-mojo package keeps its `mojo`-only
dependency set. See `wgpu_max/interop.mojo` for why that separation exists.

Install the extra dependency and run it through the opt-in environment:

    pixi run -e maxinterop test-max-interop
    pixi run -e maxinterop example-max-interop
"""

from wgpu_max.interop import (
    device_buffer_to_list,
    list_to_device_buffer,
    wgpu_to_device_buffer,
    wgpu_storage_to_device_buffer,
    device_buffer_to_wgpu,
)
