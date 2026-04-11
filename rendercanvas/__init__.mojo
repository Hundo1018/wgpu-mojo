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
    GLFWLib, MojoInputEvent, InputEventType,
    GLFW_CLIENT_API, GLFW_NO_API, GLFW_RESIZABLE, GLFW_TRUE, GLFW_FALSE,
    GLFW_PRESS, GLFW_RELEASE, GLFW_REPEAT,
    GLFW_MOUSE_BUTTON_LEFT, GLFW_MOUSE_BUTTON_RIGHT, GLFW_MOUSE_BUTTON_MIDDLE,
    GLFW_MOD_SHIFT, GLFW_MOD_CONTROL, GLFW_MOD_ALT, GLFW_MOD_SUPER,
    GLFW_CURSOR, GLFW_CURSOR_NORMAL, GLFW_CURSOR_HIDDEN, GLFW_CURSOR_DISABLED,
    GLFW_KEY_SPACE, GLFW_KEY_ESCAPE, GLFW_KEY_ENTER, GLFW_KEY_TAB,
    GLFW_KEY_BACKSPACE, GLFW_KEY_DELETE,
    GLFW_KEY_RIGHT, GLFW_KEY_LEFT, GLFW_KEY_DOWN, GLFW_KEY_UP,
    GLFW_KEY_A, GLFW_KEY_B, GLFW_KEY_C, GLFW_KEY_D, GLFW_KEY_E, GLFW_KEY_F,
    GLFW_KEY_G, GLFW_KEY_H, GLFW_KEY_I, GLFW_KEY_J, GLFW_KEY_K, GLFW_KEY_L,
    GLFW_KEY_M, GLFW_KEY_N, GLFW_KEY_O, GLFW_KEY_P, GLFW_KEY_Q, GLFW_KEY_R,
    GLFW_KEY_S, GLFW_KEY_T, GLFW_KEY_U, GLFW_KEY_V, GLFW_KEY_W, GLFW_KEY_X,
    GLFW_KEY_Y, GLFW_KEY_Z,
    GLFW_KEY_F1, GLFW_KEY_F2, GLFW_KEY_F3, GLFW_KEY_F4,
    GLFW_KEY_F5, GLFW_KEY_F6, GLFW_KEY_F7, GLFW_KEY_F8,
    GLFW_KEY_F9, GLFW_KEY_F10, GLFW_KEY_F11, GLFW_KEY_F12,
    GLFW_KEY_LEFT_SHIFT, GLFW_KEY_LEFT_CONTROL, GLFW_KEY_LEFT_ALT,
)
from rendercanvas.input import InputState
