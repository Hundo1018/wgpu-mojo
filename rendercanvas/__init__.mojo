"""
rendercanvas — GLFW-backed render canvas for wgpu-mojo on-screen rendering.

Quick start:
    from rendercanvas import RenderCanvas
    from wgpu import request_adapter

    var inst   = request_adapter()
    var device = inst.request_device()
    var canvas = RenderCanvas(inst, device, 800, 600, "Hello wgpu")

    while canvas.is_open():
        canvas.poll()
        var (tex, status) = canvas.next_frame()
        if status == 1 or status == 2:
            # render to tex ...
            canvas.present()
"""

from rendercanvas.canvas import RenderCanvas
from rendercanvas.glfw import (
    GLFWLib,
    GLFW_CLIENT_API, GLFW_NO_API, GLFW_RESIZABLE, GLFW_TRUE, GLFW_FALSE,
)
