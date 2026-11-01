// Host for a wgpu-mojo web app (#14): owns the loop, the canvas and the DOM.
// The Mojo side exports wgpu_app_* (see examples/web/triangle_web.mojo); this
// calls wgpu_app_frame once per requestAnimationFrame and forwards input.

// DOM KeyboardEvent.code -> the GLFW key codes InputState uses.
const KEYS = { Space: 32, Escape: 256, Enter: 257, Tab: 258, Backspace: 259,
  ArrowRight: 262, ArrowLeft: 263, ArrowDown: 264, ArrowUp: 265,
  ShiftLeft: 340, ControlLeft: 341, AltLeft: 342 };
const keyCode = (code) => KEYS[code]
  ?? (/^Key[A-Z]$/.test(code) ? code.charCodeAt(3)
  : /^Digit[0-9]$/.test(code) ? code.charCodeAt(5) : -1);
const BUTTONS = [0, 2, 1];  // DOM left/middle/right -> GLFW left/middle/right
const EV = { KEY: 1, MOUSE_BUTTON: 2, CURSOR_POS: 3, SCROLL: 4 };

// M comes from loadWasm() in wgpu_loader.mjs.
export async function startApp(M, canvas) {
  const [sel, len] = M.rt.str_in('#' + canvas.id);
  // u64 parameters are BigInt on wasm64; the handle comes back as a BigInt too.
  const app = M.wgpu_app_init(sel, BigInt(len), canvas.width, canvas.height);
  M.rt.free(sel);
  if (!app) throw new Error('wgpu_app_init failed');

  const input = (kind, key, action, x = 0, y = 0) =>
    M.wgpu_app_input(app, kind, key, action, 0, x, y);
  addEventListener('keydown', (e) => input(EV.KEY, keyCode(e.code), e.repeat ? 2 : 1));
  addEventListener('keyup', (e) => input(EV.KEY, keyCode(e.code), 0));
  canvas.addEventListener('mousedown', (e) => input(EV.MOUSE_BUTTON, BUTTONS[e.button] ?? e.button, 1));
  canvas.addEventListener('mouseup', (e) => input(EV.MOUSE_BUTTON, BUTTONS[e.button] ?? e.button, 0));
  canvas.addEventListener('mousemove', (e) => input(EV.CURSOR_POS, 0, 0, e.offsetX, e.offsetY));
  canvas.addEventListener('wheel', (e) => input(EV.SCROLL, 0, 0, -e.deltaX / 100, -e.deltaY / 100));

  let last = performance.now(), failed = null;
  const loop = (now) => {
    const status = M.wgpu_app_frame(app, (now - last) / 1000);
    last = now;
    if (status < 0) { failed = new Error('wgpu_app_frame failed'); return; }
    requestAnimationFrame(loop);
  };
  requestAnimationFrame(loop);
  return { M, app, error: () => failed };
}

// Pixels of the next drawn frame, as {width, height, pitch, format, bytes}.
// For video: feed `bytes` to a WebCodecs VideoFrame or MediaRecorder canvas.
export async function captureFrame({ M, app }, width, height) {
  M.wgpu_app_request_capture(app);
  for (;;) {
    await new Promise((r) => requestAnimationFrame(r));
    const ptr = Number(M.wgpu_app_capture_ptr(app));
    if (ptr) {
      const pitch = M.wgpu_app_capture_pitch(app);
      const bytes = M.rt.u8.slice(ptr, ptr + pitch * height);
      M.wgpu_app_capture_release(app);
      return { width, height, pitch, format: M.wgpu_app_format(app), bytes };
    }
  }
}
