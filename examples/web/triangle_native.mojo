"""
Native driver for examples/web/triangle_app.mojo: same app, GLFW window.

Setup goes through GPUBoot, the frame-driven path the web driver uses, so both
drivers exercise the same non-blocking code.

Run:
    pixi run example-web-triangle-native
"""

from wgpu.web.boot import GPUBoot
from wgpu.rendercanvas import RenderCanvas
from triangle_app import TriangleApp


def main() raises:
    var boot = GPUBoot("triangle")
    while not boot.step():
        pass
    var canvas = RenderCanvas(boot.adapter(), boot.device(), 640, 480, "wgpu-mojo: web triangle (native)")
    var app = TriangleApp(boot.device(), canvas.surface_format())
    print("Rendering — close the window to quit.")
    while canvas.is_open():
        canvas.poll()
        var frame = canvas.next_frame()
        if not frame.is_renderable():
            continue
        app.render(boot.device(), frame.texture)
        canvas.present()
