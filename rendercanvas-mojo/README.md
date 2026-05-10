# rendercanvas-mojo

GLFW-backed render canvas for [wgpu-mojo](https://github.com/Hundo1018/wgpu-mojo) on-screen rendering.

Provides `RenderCanvas` — a GLFW window wired to a `wgpu` Surface — plus a full
input system (`InputState`, key/mouse/cursor/scroll events) so you can write
interactive GPU applications in Mojo without any boilerplate.

## Nightly Toolchain

This package currently tracks the same Modular nightly toolchain as the root monorepo.

For a Pixi workspace, use:

```toml
[workspace]
channels = ["https://conda.modular.com/max-nightly", "conda-forge"]
preview = ["pixi-build"]
```

The package has been verified on Mojo `1.0.0b2.dev2026051006`.

## Quick start

```mojo
from rendercanvas import RenderCanvas
from wgpu.instance import Instance

var instance = Instance()
var adapter  = instance.request_adapter()
var device   = adapter.request_device()
var canvas   = RenderCanvas(adapter, device, 800, 600, "Hello wgpu")

while canvas.is_open():
    canvas.poll()
    var frame = canvas.next_frame()
    if not frame.is_renderable():
        continue
    # render to frame.texture …
    canvas.present()
```

## Dependency

`rendercanvas-mojo` depends on [wgpu-mojo](https://github.com/Hundo1018/wgpu-mojo)
for `Adapter`, `Device`, and `Surface` types.

### Local development (before wgpu-mojo is on a conda channel)

Clone both repos side-by-side and pass the wgpu-mojo path as a Mojo include flag:

```
git clone https://github.com/Hundo1018/wgpu-mojo
git clone https://github.com/Hundo1018/rendercanvas-mojo
cd rendercanvas-mojo
pixi run build-callbacks
mojo run -I . -I ../wgpu-mojo my_app.mojo
```

## Development

```bash
# Build the GLFW input callback bridge (C shared library)
pixi run build-callbacks

# Run non-GPU unit tests
pixi run test

# Integration test (requires a running display server)
pixi run test-glfw-input

# Package build
pixi build
```

## Verified Smoke Checks

Verified on 2026-05-11:

```bash
pixi install
pixi run test
pixi build
```

For local monorepo development, the package build now also resolves `wgpu` imports during isolated packaging, so `pixi build` is expected to succeed when run from this directory inside the repo.

## Platforms

| Platform | Status |
|----------|--------|
| Linux x86_64 (Wayland / X11) | ✅ |
| macOS arm64 | ✅ |

## License

Apache-2.0 — see [LICENSE](LICENSE).
