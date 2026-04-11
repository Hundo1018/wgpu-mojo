/**
 * ffi/glfw_input_callbacks.c — GLFW input callback bridge for Mojo.
 *
 * Installs GLFW key/mouse/cursor/scroll callbacks that push events into a
 * fixed-size ring buffer.  Mojo drains the buffer each frame via
 * mojo_input_poll_event().
 *
 * Build (standalone .so):
 *   gcc -shared -fPIC -o ffi/lib/libglfw_input_cb.so \
 *       ffi/glfw_input_callbacks.c -lglfw
 */
#include <stdint.h>
#include <stddef.h>

/* ---- Forward-declare GLFW types so we don't need the full header ---- */
typedef struct GLFWwindow GLFWwindow;

typedef void (* GLFWkeyfun)(GLFWwindow*, int, int, int, int);
typedef void (* GLFWmousebuttonfun)(GLFWwindow*, int, int, int);
typedef void (* GLFWcursorposfun)(GLFWwindow*, double, double);
typedef void (* GLFWscrollfun)(GLFWwindow*, double, double);

extern GLFWkeyfun         glfwSetKeyCallback(GLFWwindow*, GLFWkeyfun);
extern GLFWmousebuttonfun glfwSetMouseButtonCallback(GLFWwindow*, GLFWmousebuttonfun);
extern GLFWcursorposfun   glfwSetCursorPosCallback(GLFWwindow*, GLFWcursorposfun);
extern GLFWscrollfun      glfwSetScrollCallback(GLFWwindow*, GLFWscrollfun);

/* ---- Event struct (must match MojoInputEvent in glfw.mojo) ---- */
typedef struct {
    int32_t type;           /* 1=key, 2=mouse_button, 3=cursor_pos, 4=scroll */
    int32_t key_or_button;
    int32_t action;
    int32_t mods;
    double  x;
    double  y;
} MojoInputEvent;

/* ---- Ring buffer ---- */
#define MOJO_INPUT_QUEUE_SIZE 256

static MojoInputEvent _queue[MOJO_INPUT_QUEUE_SIZE];
static int _head = 0;   /* next write position */
static int _tail = 0;   /* next read position  */

static void _push_event(MojoInputEvent e) {
    int next = (_head + 1) % MOJO_INPUT_QUEUE_SIZE;
    if (next == _tail) {
        /* Queue full — drop oldest event */
        _tail = (_tail + 1) % MOJO_INPUT_QUEUE_SIZE;
    }
    _queue[_head] = e;
    _head = next;
}

/* ---- Public API: poll / count ---- */

int mojo_input_poll_event(MojoInputEvent* out) {
    if (_head == _tail) return 0;  /* empty */
    *out = _queue[_tail];
    _tail = (_tail + 1) % MOJO_INPUT_QUEUE_SIZE;
    return 1;
}

int mojo_input_queue_count(void) {
    return (_head - _tail + MOJO_INPUT_QUEUE_SIZE) % MOJO_INPUT_QUEUE_SIZE;
}

/* ---- GLFW callbacks ---- */

static void _key_cb(GLFWwindow* win, int key, int scancode, int action, int mods) {
    (void)win; (void)scancode;
    MojoInputEvent e;
    e.type          = 1;
    e.key_or_button = key;
    e.action        = action;
    e.mods          = mods;
    e.x             = 0.0;
    e.y             = 0.0;
    _push_event(e);
}

static void _mouse_button_cb(GLFWwindow* win, int button, int action, int mods) {
    (void)win;
    MojoInputEvent e;
    e.type          = 2;
    e.key_or_button = button;
    e.action        = action;
    e.mods          = mods;
    e.x             = 0.0;
    e.y             = 0.0;
    _push_event(e);
}

static void _cursor_pos_cb(GLFWwindow* win, double xpos, double ypos) {
    (void)win;
    MojoInputEvent e;
    e.type          = 3;
    e.key_or_button = 0;
    e.action        = 0;
    e.mods          = 0;
    e.x             = xpos;
    e.y             = ypos;
    _push_event(e);
}

static void _scroll_cb(GLFWwindow* win, double xoffset, double yoffset) {
    (void)win;
    MojoInputEvent e;
    e.type          = 4;
    e.key_or_button = 0;
    e.action        = 0;
    e.mods          = 0;
    e.x             = xoffset;
    e.y             = yoffset;
    _push_event(e);
}

/* ---- Install / remove all callbacks ---- */

void mojo_glfw_install_input_callbacks(GLFWwindow* window) {
    glfwSetKeyCallback(window, _key_cb);
    glfwSetMouseButtonCallback(window, _mouse_button_cb);
    glfwSetCursorPosCallback(window, _cursor_pos_cb);
    glfwSetScrollCallback(window, _scroll_cb);
}

void mojo_glfw_remove_input_callbacks(GLFWwindow* window) {
    glfwSetKeyCallback(window, NULL);
    glfwSetMouseButtonCallback(window, NULL);
    glfwSetCursorPosCallback(window, NULL);
    glfwSetScrollCallback(window, NULL);
}
