"""
examples/input_demo.mojo — Interactive input demo.

Opens a window and prints keyboard/mouse events in real-time.
Press ESC to quit.

Run:
    pixi run mojo run -I . examples/input_demo.mojo
"""

from wgpu.gpu import GPU
from rendercanvas import RenderCanvas
from rendercanvas.glfw import (
    GLFW_KEY_ESCAPE, GLFW_KEY_W, GLFW_KEY_A, GLFW_KEY_S, GLFW_KEY_D,
    GLFW_KEY_SPACE,
    GLFW_MOUSE_BUTTON_LEFT, GLFW_MOUSE_BUTTON_RIGHT,
)


def main() raises:
    var gpu    = GPU()
    var device = gpu.request_device()
    var canvas = RenderCanvas(gpu, device, 640, 480, "wgpu-mojo: input demo")

    print("=== Input Demo ===")
    print("WASD / Space / Mouse — press keys and click to see events")
    print("ESC to quit")
    print()

    var frame_count = 0

    while canvas.is_open():
        canvas.poll()
        frame_count += 1

        # --- Keyboard: just-pressed ---------------------------------
        if canvas.input.is_key_just_pressed(GLFW_KEY_W):
            print("[key] W pressed")
        if canvas.input.is_key_just_pressed(GLFW_KEY_A):
            print("[key] A pressed")
        if canvas.input.is_key_just_pressed(GLFW_KEY_S):
            print("[key] S pressed")
        if canvas.input.is_key_just_pressed(GLFW_KEY_D):
            print("[key] D pressed")
        if canvas.input.is_key_just_pressed(GLFW_KEY_SPACE):
            print("[key] Space pressed")

        # --- Keyboard: just-released --------------------------------
        if canvas.input.is_key_just_released(GLFW_KEY_W):
            print("[key] W released")
        if canvas.input.is_key_just_released(GLFW_KEY_A):
            print("[key] A released")
        if canvas.input.is_key_just_released(GLFW_KEY_S):
            print("[key] S released")
        if canvas.input.is_key_just_released(GLFW_KEY_D):
            print("[key] D released")

        # --- Mouse buttons ------------------------------------------
        if canvas.input.is_mouse_button_just_pressed(GLFW_MOUSE_BUTTON_LEFT):
            print(
                "[mouse] Left click at",
                canvas.input.mouse_x,
                canvas.input.mouse_y,
            )
        if canvas.input.is_mouse_button_just_pressed(GLFW_MOUSE_BUTTON_RIGHT):
            print(
                "[mouse] Right click at",
                canvas.input.mouse_x,
                canvas.input.mouse_y,
            )

        # --- Scroll -------------------------------------------------
        if canvas.input.scroll_y != 0.0:
            print("[scroll] y =", canvas.input.scroll_y)

        # --- ESC to quit --------------------------------------------
        if canvas.input.is_key_just_pressed(GLFW_KEY_ESCAPE):
            print("ESC — bye!")
            break

        # Acquire & present a frame so the window doesn't go blank
        var frame = canvas.next_frame()
        if frame.is_renderable():
            canvas.present()
